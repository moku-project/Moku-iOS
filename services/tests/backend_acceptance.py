#!/usr/bin/env python3
"""Backend parity gate. Runs real Go + OpenJDK Zero in Simulator, with no UI.

No third-party Python packages. A failed prerequisite produces BLOCKED checks,
which fail the run too. Reports never contain backend credentials.
"""
from apk_fixture import manifest as apk_manifest

import argparse
import concurrent.futures
import hashlib
import http.server
import json
import os
from pathlib import Path
import statistics
import struct
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
import zlib

SERVICE = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SANDBOX = SERVICE.parent / "vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar"
PREFIX = "org.moku.acceptance."


def extension_id(kind):
    return "eu.kanade.tachiyomi.animeextension.en.acceptance" if kind == "anime" else PREFIX + kind


def require(condition, message):
    if not condition:
        raise AssertionError(message)


class Blocked(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class API:
    def __init__(self, connection):
        self.base = connection["baseURL"]
        self.token = connection["token"]
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def request(self, path, payload=None, headers=None, authenticated=True, method=None):
        url = urllib.parse.urljoin(self.base, path)
        require(urllib.parse.urlsplit(url).netloc == urllib.parse.urlsplit(self.base).netloc,
                "backend returned a non-local delivery URL")
        h = dict(headers or {})
        if authenticated:
            h["Authorization"] = "Bearer " + self.token
        if payload is not None:
            h.setdefault("Content-Type", "application/json")
        req = urllib.request.Request(url, data=payload, headers=h, method=method)
        try:
            response = self.opener.open(req, timeout=45)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read(16 * 1024 * 1024 + 1)
            require(len(body) <= 16 * 1024 * 1024, "response exceeded fixture size limit")
            return response.status, response.headers, body

    def gql(self, query, variables=None):
        status, _, body = self.request("/api/graphql", json.dumps({"query": query, "variables": variables or {}}).encode())
        require(status == 200, f"GraphQL HTTP {status}: {body[:300]!r}")
        result = json.loads(body)
        require(not result.get("errors"), json.dumps(result.get("errors")))
        require(isinstance(result.get("data"), dict), "GraphQL returned no data")
        return result["data"]


def png(red, green, blue):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes([0, red, green, blue]))) + chunk(b"IEND", b""))


def varint(value):
    data = bytearray()
    while value > 127:
        data.append((value & 127) | 128)
        value >>= 7
    data.append(value)
    return bytes(data)


def video_frames(path):
    """Compare decoded content: a valid download may remux the MP4 container."""
    decoded = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:v:0", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], timeout=30)
    require(len(decoded) == 160 * 90 * 3 * 20, "expected twenty complete fixture video frames")
    return hashlib.sha256(decoded).hexdigest()


def field(number, value):
    value = value.encode() if isinstance(value, str) else value
    return varint(number * 8 + 2) + varint(len(value)) + value


class Website:
    def __init__(self, root):
        self.root = root
        self.offline = False
        self.requests = []
        website = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                path = urllib.parse.urlsplit(self.path).path
                website.requests.append(path)
                if website.offline:
                    self.send_error(503, "fixture upstream offline")
                    return
                protected = path.endswith((".mpd", ".m4s")) or path.startswith("/page-") or path in ("/cover.png", "/video.mp4", "/master.m3u8", "/segment.ts", "/subtitles.vtt", "/novel-text.html")
                if protected and self.headers.get("Referer") != website.origin + "/":
                    self.send_error(403, "source Referer header missing")
                    return
                if protected and "acceptance_session=ready" not in self.headers.get("Cookie", ""):
                    self.send_error(403, "source session cookie missing")
                    return
                asset = website.root / path.lstrip("/")
                if asset.is_file() and asset.resolve().is_relative_to(website.root.resolve()):
                    data = asset.read_bytes()
                elif path in ("/manga/search", "/manga/series", "/manga/chapter-1", "/anime/search", "/anime/series", "/anime/episode-1"):
                    data = b'{"fixture":true}'
                else:
                    self.send_error(404)
                    return
                types = {".png": "image/png", ".mp4": "video/mp4", ".m3u8": "application/vnd.apple.mpegurl", ".ts": "video/mp2t", ".vtt": "text/vtt"}
                status, extra = 200, {}
                if "Range" in self.headers:
                    # Fixture uses exactly bounded ranges, including the seek test.
                    import re
                    match = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers["Range"])
                    if not match:
                        self.send_error(416)
                        return
                    start, end = int(match[1]), int(match[2] or len(data) - 1)
                    end = min(end, len(data) - 1)
                    if start > end:
                        self.send_error(416)
                        return
                    extra["Content-Range"] = f"bytes {start}-{end}/{len(data)}"
                    data, status = data[start:end + 1], 206
                self.send_response(status)
                if path in ("/manga/search", "/anime/search"):
                    self.send_header("Set-Cookie", "acceptance_session=ready; Path=/; Max-Age=600; HttpOnly")
                self.send_header("Content-Type", types.get(asset.suffix, "application/octet-stream"))
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Accept-Ranges", "bytes")
                for key, value in extra.items():
                    self.send_header(key, value)
                self.end_headers()
                self.wfile.write(data)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


def build_fixtures(root, origin):
    jdk = SERVICE / ".build/toolchains/jdk-21.0.12.1+1/Contents/Home/bin"
    sources = []
    classes = root / "classes"
    classes.mkdir()
    for source in FIXTURES.glob("*.java"):
        dest = root / source.name
        dest.write_text(source.read_text().replace("FIXTURE_ORIGIN", origin))
        sources.append(str(dest))
    subprocess.run([str(jdk / "javac"), "--release", "11", "-cp", str(SANDBOX), "-d", str(classes), *sources], check=True, timeout=60)
    extensions = b""
    for kind in ("manga", "anime"):
        name = kind.capitalize()
        manifest = f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{extension_id(kind)}"><application><meta-data android:name="tachiyomi.extension.class" android:value="org.moku.acceptance.{name}"/></application></manifest>'
        with zipfile.ZipFile(root / f"{kind}.jar", "w") as archive:
            archive.writestr("AndroidManifest.xml", manifest)
            archive.write(classes / f"org/moku/acceptance/{name}.class", f"org/moku/acceptance/{name}.class")
        ext = field(1, "Acceptance " + name) + field(2, extension_id(kind)) + field(3, field(501, origin + f"/{kind}.jar") + field(2, origin + "/icon.png")) + field(6, "1.0") + field(8, field(3, "en"))
        extensions += field(1, ext)
    alternate = "org.moku.acceptance.alternate"
    with zipfile.ZipFile(root/"alternate.jar","w") as archive:
        archive.writestr("AndroidManifest.xml", '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="'+alternate+'"><application><meta-data android:name="tachiyomi.extension.class" android:value="org.moku.acceptance.MangaAlt"/></application></manifest>')
        for name in ("Manga","MangaAlt"):
            archive.write(classes/f"org/moku/acceptance/{name}.class",f"org/moku/acceptance/{name}.class")
    alternate_entry=field(1,"Acceptance Alternate")+field(2,alternate)+field(3,field(501,origin+"/alternate.jar"))+field(6,"1.0")+field(8,field(3,"en"))
    extensions+=field(1,alternate_entry)
    apk_classes = root / "apk-classes"
    apk_classes.mkdir()
    subprocess.run([str(jdk / "javac"), "--release", "8", "-cp", str(SANDBOX), "-d", str(apk_classes), str(root / "Manga.java")], check=True, timeout=60)
    dex = root / "classes.dex"
    subprocess.run([str(jdk / "java"), "-cp", str(SANDBOX), "com.android.dx.command.Main", "--dex", "--output="+str(dex), str(apk_classes)], check=True, timeout=60)
    with zipfile.ZipFile(root / "manga.apk", "w") as archive:
        archive.writestr("AndroidManifest.xml", apk_manifest(extension_id("manga"), "org.moku.acceptance.Manga"))
        archive.write(dex, "classes.dex")
    (root / "index.pb").write_bytes(field(1, "Acceptance") + field(101, extensions))
    (root / "novel-text.html").write_text("<h1>Chapter 1</h1><p>Acceptance novel text.</p>")
    (root / "novel.js").write_text((FIXTURES / "novel.js").read_text().replace("FIXTURE_ORIGIN", origin))
    (root / "novels.json").write_text(json.dumps([{"id": PREFIX + "novel", "name": "Acceptance Novel", "site": origin, "lang": "en", "version": "1.0", "url": origin + "/novel.js"}]))
    for name, rgb in (("icon.png", (25, 25, 25)), ("cover.png", (0, 0, 255)), ("page-1.png", (255, 0, 0)), ("page-2.png", (0, 255, 0))):
        (root / name).write_bytes(png(*rgb))
    # Original two-second synthetic video, generated locally. No copyrighted media.
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=160x90:r=10", "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(root / "video.mp4")], check=True, timeout=30)
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(root / "video.mp4"), "-c", "copy", "-f", "mpegts", str(root / "segment.ts")], check=True, timeout=30)
    (root / "master.m3u8").write_text("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:2.0,\nsegment.ts\n#EXT-X-ENDLIST\n")
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(root/"video.mp4"), "-c", "copy", "-f", "dash", str(root/"video.mpd")], check=True, timeout=30)
    (root / "subtitles.vtt").write_text("WEBVTT\n\n00:00.000 --> 00:01.500\nAcceptance subtitle.\n")
    return jdk, classes


class Suite:
    def __init__(self, api, website, output, data_directory=None):
        self.api, self.website, self.output = api, website, output
        self.data_directory = data_directory
        self.results, self.media = [], {}
        self.complete = False

    def check(self, name, action):
        start = time.monotonic()
        row = {"name": name}
        try:
            detail = action()
            row.update(status="PASS", detail=detail)
        except Blocked as error:
            row.update(status="BLOCKED", detail=str(error))
        except Exception as error:
            row.update(status="FAIL", detail=str(error))
        row["seconds"] = round(time.monotonic() - start, 4)
        self.results.append(row)
        print(f'{row["status"]:7} {name} ({row["seconds"]:.3f}s) {row.get("detail") or ""}', flush=True)
        self.save()

    def save(self):
        self.output.parent.mkdir(parents=True, exist_ok=True)
        report = {"runtime": "iOS Simulator / embedded OpenJDK Zero + Go", "complete": self.complete, "results": self.results,
                  "passed": sum(r["status"] == "PASS" for r in self.results),
                  "failed": sum(r["status"] == "FAIL" for r in self.results),
                  "blocked": sum(r["status"] == "BLOCKED" for r in self.results)}
        self.output.write_text(json.dumps(report, indent=2) + "\n")
        tests = ET.Element("testsuite", name="embedded-backend-parity", tests=str(len(self.results)), failures=str(report["failed"] + report["blocked"]))
        for row in self.results:
            case = ET.SubElement(tests, "testcase", name=row["name"], time=str(row.get("seconds", 0)))
            if row["status"] != "PASS":
                ET.SubElement(case, "failure", type=row["status"]).text = row.get("detail", "")
        ET.ElementTree(tests).write(self.output.with_suffix(".xml"), encoding="unicode")

    def asset(self, path, expected, content_type, headers=None, status=200):
        actual_status, response_headers, body = self.api.request(path, headers=headers)
        require(actual_status == status, f"{path}: HTTP {actual_status}, {body[:160]!r}")
        require(response_headers.get("Content-Type", "").startswith(content_type), "incorrect content type")
        require(body == expected, "downloaded bytes differ from fixture")
        return {"bytes": len(body), "sha256": hashlib.sha256(body).hexdigest()}

    def install(self, kind):
        result = self.api.gql('mutation($pkg:String!){installExtension(packageName:$pkg){installed contentType}}', {"pkg": extension_id(kind)})["installExtension"]
        require(result["installed"], "extension was not installed")
        require(result["contentType"] == kind.upper(), f"wrong content type: {result}")

    def search(self, kind, page=1, query="acceptance"):
        result = self.api.gql('query($ext:ID!,$page:Int!,$q:String!){search(extensionId:$ext,query:$q,page:$page){results{id externalId title thumbnailUrl genres metadata{coverUrl}} hasNextPage}}', {"ext": extension_id(kind), "page": page, "q": query})["search"]
        if page == 1 and query != "missing":
            require(len(result["results"]) == 1, "expected one fixture search result")
            media = result["results"][0]
            require(media["title"] == "Acceptance " + kind.capitalize(), "wrong title")
            require(media["externalId"] == f"/{kind}/series", "source ID lost")
            if kind in self.media:
                require(media["id"] == self.media[kind]["id"], "repeated search created a duplicate media record")
            self.media[kind] = {**self.media.get(kind, {}), **media}
        else:
            require(result == {"results": [], "hasNextPage": False}, "empty/page-two semantics mismatch")
        return result

    def details(self, kind):
        media = self.api.gql('query($ext:ID!,$external:String!){resolveMedia(extensionId:$ext,externalId:$external,syncChapters:true){id title description author genres chapters{id externalId number}}}', {"ext": extension_id(kind), "external": f"/{kind}/series"})["resolveMedia"]
        require(media["description"] == "A deterministic source description.", "description missing")
        require(media["author"] == "Fixture Author" and "Adventure" in media["genres"], "metadata missing")
        require(len(media["chapters"]) == 1 and media["chapters"][0]["number"] == 1, "chapter/episode mapping failed")
        if kind in self.media:
            require(media["id"] == self.media[kind]["id"], "details did not reuse search record")
        self.media[kind] = media

    def chapter(self, kind):
        media = self.media.get(kind, {})
        if not media.get("chapters"):
            raise Blocked(f"{kind}.details_and_chapters must pass before testing content bytes")
        return media, media["chapters"][0]

    def pages(self):
        _, chapter = self.chapter("manga")
        pages = self.api.gql('query($id:ID!){chapter(id:$id){pages}}', {"id": chapter["id"]})["chapter"]["pages"]
        require(len(pages) == 2, "expected two reader page URLs")
        for index, path in enumerate(pages, 1):
            self.asset(path, (self.website.root / f"page-{index}.png").read_bytes(), "image/png")

    def stream(self):
        _, chapter = self.chapter("anime")
        stream = self.api.gql('query($id:ID!){chapter(id:$id){videoStream{url sources{label url} subtitles{lang url}}}}', {"id": chapter["id"]})["chapter"]["videoStream"]
        require(stream and len(stream["sources"]) == 3, "MP4/HLS/DASH sources missing")
        sources = {s["label"]: s["url"] for s in stream["sources"]}
        video = (self.website.root / "video.mp4").read_bytes()
        self.asset(sources["360p MP4"], video, "video/")
        self.asset(sources["360p MP4"], video[128:256], "video/", {"Range": "bytes=128-255"}, 206)
        status, _, playlist = self.api.request(sources["360p HLS"])
        require(status == 200 and playlist.startswith(b"#EXTM3U"), "HLS playlist not delivered")
        segments = [line for line in playlist.decode().splitlines() if line and not line.startswith("#")]
        require(len(segments) == 1, "unexpected fixture HLS playlist")
        self.asset(urllib.parse.urljoin(self.api.base + sources["360p HLS"], segments[0]), (self.website.root / "segment.ts").read_bytes(), "video/")
        status, _, manifest = self.api.request(sources["360p DASH"])
        require(status == 200, "DASH manifest not delivered")
        doc = ET.fromstring(manifest)
        base = next(node.text for node in doc.iter() if node.tag.endswith("BaseURL"))
        proxy_base = urllib.parse.urljoin(self.api.base+sources["360p DASH"], base)
        for asset in sorted(self.website.root.glob("*.m4s")):
            status, _, data = self.api.request(urllib.parse.urljoin(proxy_base, asset.name))
            require(status==200 and data==asset.read_bytes(), "DASH init/media bytes differ")
        require(stream["subtitles"], "subtitle URL missing")
        # Unlike the trusted in-sandbox HLS proxy, subtitle targets intentionally
        # reject private IPs. Do not weaken that protection for a local fixture.
        status, _, _ = self.api.request(stream["subtitles"][0]["url"])
        require(status == 400, "private subtitle target was not rejected")

    def novel(self):
        media, chapter = self.chapter("novel")
        status, _, body = self.api.request(f'/content/{media["id"]}/{chapter["id"]}/text')
        require(status == 200 and b"Acceptance novel text." in body, "novel body not delivered")

    def library_progress(self):
        media = self.media.get("manga")
        if not media:
            raise Blocked("manga.search failed")
        saved = self.api.gql('mutation($id:ID!){setInLibrary(mediaId:$id,inLibrary:true){id inLibrary}}', {"id": media["id"]})["setInLibrary"]
        require(saved["inLibrary"], "save was not persisted")
        rows = self.api.gql('{library{items{id}}}')["library"]["items"]
        require(any(m["id"] == media["id"] for m in rows), "saved title absent from library")
        _, chapter = self.chapter("manga")
        variables = {"m": media["id"], "c": chapter["id"]}
        self.api.gql('mutation($m:ID!,$c:ID!){updateReadingProgress(mediaId:$m,chapterId:$c,progress:0.5,completed:false){progress}}', variables)
        progress = self.api.gql('query($m:ID!){readingProgress(mediaId:$m){chapterId progress completed}}', {"m": media["id"]})["readingProgress"]
        require(any(p["chapterId"] == chapter["id"] and p["progress"] == 0.5 and not p["completed"] for p in progress), "reading progress not persisted")

    def download(self, kind, keep=False):
        # Probe the capability before checking dependent data so a disabled
        # downloader cannot disappear behind a details failure.
        self.api.gql('{downloadQueue{id status} downloaderStatus{isRunning queuedCount failedCount}}')
        media, chapter = self.chapter(kind)
        variables = {"m": media["id"], "c": [chapter["id"]]}
        rows = self.api.gql('mutation($m:ID!,$c:[ID!]!){enqueueDownload(mediaId:$m,chapterIds:$c){chapterId status}}', variables)["enqueueDownload"]
        require(len(rows) == 1 and rows[0]["chapterId"] == chapter["id"], "wrong chapter enqueued")
        self.api.gql('mutation{startDownloader}')
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            row = self.api.gql('query($m:ID!,$c:ID!){downloadStatus(mediaId:$m,chapterId:$c){status progress error}}', {"m": media["id"], "c": chapter["id"]})["downloadStatus"]
            require(row and row["status"] != "FAILED", f"download failed: {row}")
            if row["status"] == "DONE":
                break
            time.sleep(0.2)
        else:
            raise AssertionError("download never reached DONE within 45s")
        require(row["progress"] == 1, "DONE download is not at 100%")
        # Verify disk artifacts too: an in-memory image cache alone must not be
        # enough to pass the offline test. Support both loose pages and CBZ.
        require(self.data_directory is not None, "missing test data directory")
        persisted = []
        for path in (self.data_directory / "media").rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() in (".cbz", ".zip"):
                with zipfile.ZipFile(path) as archive:
                    persisted.extend(archive.read(name) for name in archive.namelist())
            else:
                persisted.append(path.read_bytes())
        if kind == "manga":
            require(all((self.website.root / f"page-{i}.png").read_bytes() in persisted for i in (1, 2)), "download did not persist both pages to disk")
        elif kind == "anime":
            videos = list((self.data_directory / "media").rglob("*.mp4"))
            require(len(videos) == 1, "expected one persisted episode")
            require(video_frames(videos[0]) == video_frames(self.website.root / "video.mp4"), "downloaded video content differs from original")
        else:
            require(any(b"Acceptance novel text." in data for data in persisted), "novel text was not persisted")
        # Take the origin offline; compare actual persisted bytes, not queue flags.
        self.website.offline = True
        try:
            prefix = f'/content/{media["id"]}/{chapter["id"]}'
            if kind == "manga":
                for i in (1, 2):
                    self.asset(prefix + f"/pages/{i}", (self.website.root / f"page-{i}.png").read_bytes(), "image/png")
            elif kind == "anime":
                self.asset(prefix + "/video", videos[0].read_bytes(), "video/")
            else:
                self.novel()
        finally:
            self.website.offline = False
        if keep:
            return
        self.api.gql('mutation($m:ID!,$c:[ID!]!){deleteDownload(mediaId:$m,chapterIds:$c)}', variables)
        row = self.api.gql('query($id:ID!){chapter(id:$id){downloaded}}', {"id": chapter["id"]})["chapter"]
        require(not row["downloaded"], "deletion left chapter marked downloaded")

    def administration(self):
        media, chapter = self.chapter("manga")
        folder = self.api.gql('mutation{createFolder(name:"Acceptance Folder"){id name}}')["createFolder"]
        self.api.gql('mutation($m:ID!,$f:ID!){addMediaToFolder(mediaId:$m,folderId:$f)}', {"m":media["id"],"f":folder["id"]})
        rows = self.api.gql('query($f:ID!){mediaInFolder(folderId:$f){id}}', {"f":folder["id"]})["mediaInFolder"]
        require(any(row["id"] == media["id"] for row in rows), "folder membership missing")
        self.api.gql('mutation($f:ID!){renameFolder(folderId:$f,name:"Renamed"){name} deleteFolder(folderId:$f)}', {"f":folder["id"]})
        backup = self.api.gql('mutation{createDatabaseBackup{name}}')["createDatabaseBackup"]
        require((self.data_directory / "backups" / backup["name"]).is_file(), "snapshot file missing")
        self.api.gql('mutation($name:String!){deleteDatabaseBackup(name:$name)}', {"name":backup["name"]})
        require(not (self.data_directory / "backups" / backup["name"]).exists(), "backup deletion failed")
        exported = self.api.gql('mutation{exportMihonBackup{name}}')["exportMihonBackup"]
        self.api.gql('mutation($name:String!){importMihonBackup(name:$name){__typename}}', {"name":exported["name"]})
        self.api.gql('{storageInfo{__typename} trackers{key isLoggedIn} contentFilterRules{__typename} serverSettings{key}}')
        status, _, body = self.api.request("/api/mobile/automation?mediaId=0", json.dumps({"downloadAhead":2,"deleteOnRead":False}).encode(), method="PUT")
        require(status == 204, f"policy save failed: {body!r}")
        status, _, body = self.api.request("/api/mobile/automation?mediaId=0")
        require(status == 200 and json.loads(body)["downloadAhead"] == 2, "policy was not persisted")
        status, _, body = self.api.request("/api/mobile/chapter-open", json.dumps({"mediaId":int(media["id"]),"chapterId":int(chapter["id"])}).encode())
        require(status == 204, f"chapter-open failed: {body!r}")

    def cbz(self):
        self.api.gql('mutation{updateServerSetting(key:"manga_download_format",value:"cbz"){__typename}}')
        try:
            self.download("manga")
        finally:
            self.api.gql('mutation{updateServerSetting(key:"manga_download_format",value:"loose"){__typename}}')

    def run(self, budget):
        self.check("http.authentication", lambda: require(self.api.request("/api/mobile/status", authenticated=False)[0] == 401, "unauthenticated API accepted"))
        self.check("catalog.fixture_repository", lambda: self.api.gql('mutation($url:String!){addRepository(indexUrl:$url){id}}', {"url": self.website.origin + "/index.pb"}))
        self.check("catalog.novel_repository", lambda: self.api.gql('mutation($url:String!){addRepository(indexUrl:$url){id}}', {"url": self.website.origin + "/novels.json"}))
        for kind in ("manga", "anime", "novel"):
            self.check(f"{kind}.install", lambda k=kind: self.install(k))
            self.check(f"{kind}.search", lambda k=kind: self.search(k))
            self.check(f"{kind}.details_and_chapters", lambda k=kind: self.details(k))
            self.check(f"{kind}.download_and_offline_bytes", lambda k=kind: self.download(k))
        def repository_update():
            index=self.website.root/"index.pb"
            index.write_bytes(index.read_bytes().replace(b"1.0",b"1.1"))
            self.api.gql('mutation{syncRepository(repositoryId:"1"){id}}')
            extension=self.api.gql('mutation{updateExtension(packageName:"org.moku.acceptance.manga"){installed version installedVersion needsUpdate}}')["updateExtension"]
            require(extension["installed"] and extension["installedVersion"]=="1.1" and not extension["needsUpdate"], "extension update did not finalize installation")
            self.search("manga")
        self.check("extensions.repository_sync_and_update",repository_update)
        def extension_icon():
            rows = self.api.gql('{installedExtensions{packageName iconUrl}}')["installedExtensions"]
            path = next(row["iconUrl"] for row in rows if row["packageName"]==extension_id("manga"))
            require(path is not None, "extension icon URL missing")
            self.asset(path, (self.website.root/"icon.png").read_bytes(), "image/png")
            self.website.offline=True
            try: self.asset(path, (self.website.root/"icon.png").read_bytes(), "image/png")
            finally: self.website.offline=False
        self.check("images.extension_icon_bytes_and_cache",extension_icon)
        def apk_conversion():
            self.api.gql('mutation{uninstallExtension(packageName:"org.moku.acceptance.manga"){installed}}')
            installed = self.api.gql('mutation($url:String!){installExternalExtension(url:$url){installed}}', {"url":self.website.origin+"/manga.apk"})["installExternalExtension"]
            require(installed["installed"], "converted APK was not installed")
            self.search("manga")
            self.details("manga")
        self.check("extensions.apk_conversion_and_execution", apk_conversion)
        self.check("manga.search_pagination", lambda: self.search("manga", page=2))
        self.check("manga.search_empty", lambda: self.search("manga", query="missing"))

        def latency():
            times = []
            for _ in range(5):
                start = time.monotonic()
                self.search("manga")
                times.append(time.monotonic() - start)
            require(max(times) <= budget, f"warm search budget {budget}s exceeded: {times}")
            return {"samples_seconds": times, "median_seconds": statistics.median(times), "max_seconds": max(times), "budget_seconds": budget}
        self.check("manga.warm_search_latency_and_identity", latency)

        def cover(kind="manga"):
            if kind not in self.media:
                raise Blocked("manga.search failed")
            path = "/proxy/cover/" + self.media[kind]["id"]
            expected = (self.website.root / "cover.png").read_bytes()
            self.asset(path, expected, "image/png")
            self.website.offline = True
            try:
                return self.asset(path, expected, "image/png")
            finally:
                self.website.offline = False
        for kind in ("manga", "anime", "novel"):
            self.check(f"{kind}.cover_bytes_and_cache", lambda k=kind: cover(k))
        def concurrent_images():
            path = "/proxy/cover/" + self.media["manga"]["id"]
            expected = (self.website.root / "cover.png").read_bytes()
            def request(_):
                start = time.monotonic()
                self.asset(path, expected, "image/png")
                return time.monotonic() - start
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                samples = list(pool.map(request, range(32)))
            return {"concurrency":8, "requests":32, "median_seconds":statistics.median(samples), "max_seconds":max(samples)}
        self.check("images.concurrent_cache_latency", concurrent_images)
        def cover_override():
            media = self.media["manga"]["id"]
            (self.website.root / "override.png").write_bytes(png(255,255,0))
            self.api.gql('mutation($id:ID!,$url:String){setMediaCover(mediaId:$id,url:$url){hasCoverOverride}}', {"id":media,"url":self.website.origin+"/override.png"})
            self.asset("/proxy/cover/"+media,png(255,255,0),"image/png")
            (self.website.root / "override.png").write_bytes(png(0,255,255))
            self.asset("/proxy/cover/"+media,png(255,255,0),"image/png")
            self.api.gql('mutation{clearImageCache}')
            self.asset("/proxy/cover/"+media,png(0,255,255),"image/png")
            self.api.gql('mutation($id:ID!){setMediaCover(mediaId:$id,url:null){hasCoverOverride}}', {"id":media})
            self.asset("/proxy/cover/"+media,(self.website.root/"cover.png").read_bytes(),"image/png")
        self.check("images.cover_override_and_invalidation", cover_override)
        self.check("manga.reader_page_bytes", self.pages)
        self.check("anime.mp4_seek_hls_segments_and_subtitle_guard", self.stream)
        self.check("novel.chapter_text", self.novel)
        self.check("manga.cbz_download_and_offline_bytes", self.cbz)
        self.check("administration.folders_backups_trackers_storage_policies", self.administration)
        self.check("discovery.popular", lambda: self.api.gql('query{popularManga(extensionId:"org.moku.acceptance.manga"){results{id title}}}'))
        self.check("discovery.latest", lambda: self.api.gql('query{latestUpdates(extensionId:"org.moku.acceptance.manga"){results{id title}}}'))
        self.check("discovery.filters", lambda: self.api.gql('query{filterOptions(extensionId:"org.moku.acceptance.manga"){__typename}}'))
        self.check("library.browse", lambda: self.api.gql('{library{total items{id}}}'))
        self.check("library.save_and_reading_progress", self.library_progress)
        def preferences():
            rows=self.api.gql('{sourcePreferences(extensionId:"org.moku.acceptance.manga"){key currentValue}}')["sourcePreferences"]
            require(rows==[{"key":"fixture_option","currentValue":"default"}],"preference default lost")
            rows=self.api.gql('mutation{setSourcePreference(extensionId:"org.moku.acceptance.manga",key:"fixture_option",value:"custom"){key currentValue}}')["setSourcePreference"]
            require(rows==[{"key":"fixture_option","currentValue":"custom"}],"preference write lost")
        self.check("source.preferences",preferences)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("simulator")
    parser.add_argument("--live", action="store_true", help="also verify live MangaDex install/search/cover")
    parser.add_argument("--search-budget", type=float, default=5.0, help="provisional warm local-source budget in seconds")
    args = parser.parse_args()
    require(args.search_budget > 0, "search budget must be positive")
    output = SERVICE / ".build/last-acceptance.json"
    for path in (output, output.with_suffix(".xml"), SERVICE / ".build/acceptance-runtime.log", SERVICE / ".build/acceptance-runtime-error.log"):
        path.unlink(missing_ok=True)
    subprocess.run(["xcrun", "simctl", "terminate", args.simulator, "org.moku.backendprobe"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "install", args.simulator, str(SERVICE / ".build/native-simulator/MokuBackendProbe.app")], check=True)
    container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", args.simulator, "org.moku.backendprobe", "data"], text=True).strip())
    documents = container / "Documents"
    documents.mkdir(exist_ok=True)
    connection_path, stop = documents / "acceptance-connection.json", documents / "acceptance-stop"
    for path in (connection_path, stop, documents / "probe.json"):
        path.unlink(missing_ok=True)
    suite = None
    try:
        with tempfile.TemporaryDirectory(prefix="moku-acceptance-") as directory:
            website = Website(Path(directory))
            try:
                jdk, classes = build_fixtures(website.root, website.origin)
                started = time.monotonic()
                subprocess.run(["xcrun", "simctl", "launch", "--stdout=" + str(SERVICE / ".build/acceptance-runtime.log"), "--stderr=" + str(SERVICE / ".build/acceptance-runtime-error.log"), args.simulator, "org.moku.backendprobe", "--acceptance"], check=True)
                while not connection_path.exists():
                    if (documents / "probe.json").exists():
                        raise RuntimeError((documents / "probe.json").read_text())
                    require(time.monotonic() - started < 120, "embedded backend startup timed out")
                    time.sleep(0.2)
                connection = json.loads(connection_path.read_text())
                data_directory = (documents / connection["dataDirectory"]).resolve()
                require(data_directory.is_relative_to(documents.resolve()), "invalid probe data directory")
                suite = Suite(API(connection), website, output, data_directory)
                suite.results.append({"name": "runtime.startup", "status": "PASS", "seconds": time.monotonic() - started})
                suite.run(args.search_budget)

                def jvm_contract():
                    report = website.root / "jvm-results.json"
                    subprocess.run([str(jdk / "java"), "-cp", os.pathsep.join([str(classes), str(SANDBOX)]), "JvmContract", str(connection_path), str(report)], check=True, timeout=180, stdout=subprocess.DEVNULL)
                    for row in json.loads(report.read_text()):
                        suite.results.append(row)
                        print(f'{row["status"]:7} {row["name"]} {row.get("detail", "")}', flush=True)
                suite.check("jvm.contract_runner", jvm_contract)

                def relaunch_offline():
                    for kind in ("manga", "anime", "novel"):
                        suite.download(kind, keep=True)
                    old_token = suite.api.token
                    stop.touch()
                    deadline = time.monotonic() + 10
                    while connection_path.exists() and time.monotonic() < deadline:
                        time.sleep(.1)
                    require(not connection_path.exists(), "service shutdown did not finish")
                    subprocess.run(["xcrun","simctl","terminate",args.simulator,"org.moku.backendprobe"], check=True)
                    stop.unlink(missing_ok=True)
                    website.offline = True
                    try:
                        launched = subprocess.check_output(["xcrun","simctl","launch",args.simulator,"org.moku.backendprobe","--acceptance","--resume-acceptance",connection["dataDirectory"]], text=True)
                        deadline = time.monotonic() + 120
                        while not connection_path.exists() and time.monotonic() < deadline:
                            time.sleep(.2)
                        require(connection_path.exists(), "relaunch timed out")
                        resumed = json.loads(connection_path.read_text())
                        suite.api = API(resumed)
                        require(suite.api.token != old_token, "restart reused bearer credential")
                        for kind in ("manga", "anime", "novel"):
                            media, chapter = suite.chapter(kind)
                            prefix = f'/content/{media["id"]}/{chapter["id"]}'
                            row = suite.api.gql('query($id:ID!){chapter(id:$id){downloaded}}', {"id":chapter["id"]})["chapter"]
                            require(row["downloaded"], "download flag lost after app restart")
                            if kind == "manga":
                                for i in (1,2):
                                    suite.asset(prefix+f"/pages/{i}",(website.root/f"page-{i}.png").read_bytes(),"image/png")
                            elif kind == "anime":
                                video = next((data_directory/"media").rglob("*.mp4"))
                                suite.asset(prefix+"/video",video.read_bytes(),"video/")
                            else:
                                suite.novel()
                        rows=suite.api.gql('{library{items{id}}}')["library"]["items"]
                        require(any(row["id"]==suite.media["manga"]["id"] for row in rows), "library lost on relaunch")
                        prefs=suite.api.gql('{sourcePreferences(extensionId:"org.moku.acceptance.manga"){key currentValue}}')["sourcePreferences"]
                        require(prefs==[{"key":"fixture_option","currentValue":"custom"}],"source preferences lost on relaunch")
                        status, _, body = suite.api.request("/api/mobile/automation?mediaId=0")
                        require(status==200 and json.loads(body)["downloadAhead"]==2, "policy lost on relaunch")
                        report = website.root / "restored-cookie-results.json"
                        subprocess.run([str(jdk / "java"),"-cp",os.pathsep.join([str(classes),str(SANDBOX)]),"JvmContract",str(connection_path),str(report),"cookies-restored"],check=True,timeout=30,stdout=subprocess.DEVNULL)
                        for row in json.loads(report.read_text()):
                            suite.results.append(row)
                            require(row["status"]=="PASS", row.get("detail","cookie persistence failed"))
                        pid = int(launched.strip().rsplit(":",1)[1])
                        rss = int(subprocess.check_output(["ps","-o","rss=","-p",str(pid)],text=True).strip())
                        return {"fresh_process":True,"origin_offline":True,"resident_kib":rss}
                    finally:
                        website.offline = False
                suite.check("lifecycle.app_restart_offline_content_library_policies", relaunch_offline)

                def migration():
                    api=suite.api
                    old=suite.media["manga"]["id"]
                    api.gql('mutation{installExtension(packageName:"org.moku.acceptance.alternate"){installed}}')
                    folder=api.gql('mutation{createFolder(name:"Migration"){id}}')["createFolder"]["id"]
                    api.gql('mutation($m:ID!,$f:ID!){addMediaToFolder(mediaId:$m,folderId:$f)}',{"m":old,"f":folder})
                    status,_,_=api.request("/api/mobile/automation?mediaId="+old,json.dumps({"downloadAhead":3}).encode(),method="PUT")
                    require(status==204,"source policy save failed")
                    before=api.gql('query($id:ID!){media(id:$id){downloadedCount}}',{"id":old})["media"]
                    require(before["downloadedCount"]==1,"downloaded count mismatch")
                    migrated=api.gql('mutation($id:ID!){migrateMedia(fromMediaId:$id,toExtensionId:"org.moku.acceptance.alternate",toExternalId:"/manga/series"){id inLibrary folders{id} readingProgress{progress} chapters{id}}}',{"id":old})["migrateMedia"]
                    require(migrated["id"]!=old and migrated["inLibrary"],"migration did not adopt target")
                    require(any(f["id"]==folder for f in migrated["folders"]),"migration lost folders")
                    require(any(p["progress"]==.5 for p in migrated["readingProgress"]),"migration lost progress")
                    status,_,body=api.request("/api/mobile/automation?mediaId="+migrated["id"])
                    require(status==200 and json.loads(body)["downloadAhead"]==3,"migration lost per-series policy")
                    rows=api.gql('{library(filter:{contentType:MANGA,query:"Acceptance"},sort:{by:TITLE,ascending:true}){items{id}}}')["library"]["items"]
                    require([row["id"] for row in rows]==[migrated["id"]],"library migration/filter result mismatch")
                suite.check("library.source_migration_progress_folders_policies_filters",migration)

                if args.live:
                    live_mangadex(suite, jdk, classes, connection_path)
                suite.complete = True
                suite.save()
            finally:
                website.close()
    finally:
        stop.touch()
        # A bounded wait permits Go to drain and close SQLite; terminate the test
        # host afterwards even on exceptions, and erase the credential handoff.
        deadline = time.monotonic() + 8
        while connection_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        subprocess.run(["xcrun", "simctl", "terminate", args.simulator, "org.moku.backendprobe"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        connection_path.unlink(missing_ok=True)
        stop.unlink(missing_ok=True)
    require(suite is not None, "suite did not start")
    failures = [r for r in suite.results if r["status"] != "PASS"]
    print(f"\n{len(suite.results) - len(failures)}/{len(suite.results)} passed. JSON: {output}; JUnit: {output.with_suffix('.xml')}")
    return bool(failures)


def live_mangadex(suite, jdk, classes, connection_path):
    api = suite.api
    package = "eu.kanade.tachiyomi.extension.all.mangadex"
    result = {}
    suite.check("live.mangadex.repository", lambda: api.gql('mutation{addRepository(indexUrl:"https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb"){id}}'))
    suite.check("live.mangadex.install", lambda: require(api.gql('mutation($p:String!){installExtension(packageName:$p){installed}}', {"p": package})["installExtension"]["installed"], "live extension not installed"))

    def search():
        rows = api.gql('query($e:ID!){search(extensionId:$e,query:"Rent a Girlfriend",page:1){results{id externalId title thumbnailUrl}}}', {"e": package})["search"]["results"]
        match = next((m for m in rows if m["title"].lower() == "rent-a-girlfriend"), None)
        require(match is not None, "exact live title not found")
        result.update(match)
        return {"result_count": len(rows)}
    suite.check("live.mangadex.search", search)

    def cover():
        if not result:
            raise Blocked("live search failed")
        status, headers, body = api.request("/proxy/cover/" + result["id"])
        require(status == 200 and headers.get("Content-Type", "").startswith("image/") and len(body) > 100, "live cover bytes not served")
        require(body.startswith((b"\xff\xd8\xff", b"\x89PNG", b"RIFF", b"GIF8")), "cover response is not an image")
        return {"bytes": len(body), "sha256": hashlib.sha256(body).hexdigest()}
    suite.check("live.mangadex.cover_bytes", cover)

    def metadata():
        if not result:
            raise Blocked("live search failed")
        report = suite.website.root / "live-jvm-results.json"
        subprocess.run([str(jdk / "java"), "-cp", os.pathsep.join([str(classes), str(SANDBOX)]), "JvmContract", str(connection_path), str(report), package, result["externalId"]], check=True, timeout=100, stdout=subprocess.DEVNULL)
        for row in json.loads(report.read_text()):
            suite.results.append(row)
            print(f'{row["status"]:7} {row["name"]} {row.get("detail", "")}', flush=True)
    suite.check("live.mangadex.metadata_runner", metadata)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        # Startup/compiler/transport crashes must produce a red report too,
        # instead of leaving yesterday's passing report behind.
        path = SERVICE / ".build/last-acceptance.json"
        suite = Suite(None, None, path)
        if path.exists():
            suite.results = json.loads(path.read_text())["results"]
        suite.results.append({"name": "runtime.runner", "status": "FAIL", "detail": str(error), "seconds": 0})
        suite.save()
        print(f"FAIL runtime.runner: {error}", flush=True)
        raise SystemExit(1)
