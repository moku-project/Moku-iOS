"""Regression checks for the acceptance gate's failure detection itself."""
import http.server
import json
from pathlib import Path
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET

from backend_acceptance import API, Blocked, Suite, Website, png


class GateTests(unittest.TestCase):
    def test_graphql_errors_and_null_data_never_pass(self):
        api = API({"baseURL": "http://127.0.0.1:1", "token": "test"})
        for response in ({"errors": [{"message": "capability missing"}], "data": {"value": True}}, {"data": None}, {}):
            api.request = lambda *_, r=response: (200, {}, json.dumps(r).encode())
            with self.assertRaises(AssertionError):
                api.gql("{about{name}}")

    def test_external_media_url_rejected_before_sending_credential(self):
        api = API({"baseURL": "http://127.0.0.1:1", "token": "private"})
        with self.assertRaisesRegex(AssertionError, "non-local"):
            api.request("https://example.com/page.png")

    def test_redirect_does_not_forward_credential(self):
        received = []

        class Target(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                received.append(self.headers.get("Authorization"))
                self.send_response(200)
                self.end_headers()

        target = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Target)

        class Redirect(Target):
            def do_GET(self):
                self.send_response(302)
                self.send_header("Location", f"http://127.0.0.1:{target.server_port}/")
                self.end_headers()

        redirect = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Redirect)
        servers = [target, redirect]
        threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in servers]
        for thread in threads:
            thread.start()
        try:
            api = API({"baseURL": f"http://127.0.0.1:{redirect.server_port}", "token": "private"})
            self.assertEqual(api.request("/")[0], 302)
            self.assertEqual(received, [])
        finally:
            for server, thread in zip(servers, threads):
                server.shutdown()
                server.server_close()
                thread.join()

    def test_blocked_checks_fail_junit_instead_of_skipping(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "results.json"
            suite = Suite(None, None, path)

            def blocked():
                raise Blocked("details failed")

            suite.check("reader", blocked)
            report = json.loads(path.read_text())
            self.assertEqual(report["blocked"], 1)
            junit = ET.parse(path.with_suffix(".xml")).getroot()
            self.assertEqual(junit.get("failures"), "1")
            self.assertIsNotNone(junit.find("testcase/failure"))

    def test_asset_requires_exact_bytes_not_just_http_success(self):
        api = API({"baseURL": "http://127.0.0.1:1", "token": "test"})
        api.request = lambda *_, **kw: (200, {"Content-Type": "image/png"}, b"wrong bytes")
        suite = Suite(api, None, None)
        with self.assertRaisesRegex(AssertionError, "bytes differ"):
            suite.asset("/page", png(255, 0, 0), "image/png")

    def test_origin_enforces_headers_ranges_and_offline_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "video.mp4").write_bytes(bytes(range(256)))
            website = Website(root)
            api = API({"baseURL": website.origin, "token": "test"})
            try:
                self.assertEqual(api.request("/video.mp4")[0], 403)
                headers = {"Referer": website.origin + "/", "Cookie":"acceptance_session=ready", "Range": "bytes=128-255"}
                status, response_headers, data = api.request("/video.mp4", headers=headers)
                self.assertEqual(status, 206)
                self.assertEqual(data, bytes(range(128, 256)))
                self.assertEqual(response_headers["Content-Range"], "bytes 128-255/256")
                website.offline = True
                self.assertEqual(api.request("/video.mp4", headers=headers)[0], 503)
            finally:
                website.close()


if __name__ == "__main__":
    unittest.main()
