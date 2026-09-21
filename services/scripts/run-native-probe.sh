#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
simulator="${1:?Pass a booted simulator UDID}"
shift
mode="${1:-catalog}"
xcrun simctl terminate "$simulator" org.moku.backendprobe >/dev/null 2>&1 || true
xcrun simctl install "$simulator" .build/native-simulator/MokuBackendProbe.app
container="$(xcrun simctl get_app_container "$simulator" org.moku.backendprobe data)"
# Only remove this test's previous report so a stale pass cannot satisfy the check.
rm -f "$container/Documents/probe.json"
xcrun simctl launch "$simulator" org.moku.backendprobe "$@"
python3 - "$container/Documents/probe.json" "$mode" <<'PY'
import hashlib, json, pathlib, sys, time, zipfile
path = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
for _ in range(300):
 if path.exists():
  report = json.loads(path.read_text())
  if "backendError" in report:
   raise SystemExit(report["backendError"])
  if mode == "--jvm" and "jvm" not in report:
   time.sleep(1); continue
  print(json.dumps(report, indent=2))
  if report.get('repository', {}).get('errors') or report.get('extensions', {}).get('errors'):
   raise SystemExit('GraphQL returned errors')
  items = report.get('extensions', {}).get('data', {}).get('extensions', {}).get('items', [])
  if not any(x['packageName'] == 'eu.kanade.tachiyomi.extension.all.mangadex' for x in items):
   raise SystemExit('MangaDex missing from live catalog')
  if mode == '--search':
   installation = report.get('installation', {})
   search = report.get('search', {})
   if installation.get('errors') or search.get('errors'):
    raise SystemExit('Installation/search returned GraphQL errors')
   if not installation.get('data', {}).get('installExtension', {}).get('installed'):
    raise SystemExit('MangaDex was not installed')
   results = search.get('data', {}).get('search', {}).get('results', [])
   if not any(x.get('title', '').lower() == 'rent-a-girlfriend' for x in results):
    raise SystemExit('Requested title missing from extension search')
   data_dir = (path.parent / report['dataDirectory']).resolve()
   if not data_dir.is_relative_to(path.parent.resolve()):
    raise SystemExit('Invalid probe data directory')
   packages = [p for p in (data_dir / 'jar-cache').glob('eu.kanade.tachiyomi.extension.all.mangadex-*') if p.suffix in ('.apk', '.jar')]
   if len(packages) != 1:
    raise SystemExit('Expected one downloaded MangaDex package')
   apk = packages[0]
   with zipfile.ZipFile(apk) as archive:
    names = archive.namelist()
    valid = any(n.endswith('.class') for n in names) if apk.suffix == '.jar' else {'AndroidManifest.xml', 'classes.dex'}.issubset(names)
    if not valid:
     raise SystemExit('Downloaded package is missing executable classes')
   report['download'] = {'file': apk.name, 'bytes': apk.stat().st_size,
                         'sha256': hashlib.sha256(apk.read_bytes()).hexdigest()}
   pathlib.Path('.build/last-search.json').write_text(json.dumps(report, indent=2))
   print(json.dumps(report['download'], indent=2))
   print('Native iOS → Go → embedded JVM → MangaDex install and title search: PASS')
  elif mode == '--jvm':
   if 'dynamic JAR class loading and reflection: PASS' not in report.get('jvm', ''):
    raise SystemExit('JVM probe failed')
   if 'app-owned NIO temp cache: PASS' not in report.get('jvm', ''):
    raise SystemExit('JVM app-owned temporary cache probe failed')
   print('Embedded JVM, dynamic JAR class loading, and app-owned NIO temp cache: PASS')
  else:
   print('Native iOS → Go → live MangaDex catalog: PASS')
  break
 time.sleep(1)
else:
 raise SystemExit('Timed out waiting for native catalog report')
PY
