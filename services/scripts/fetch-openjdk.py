#!/usr/bin/env python3
"""Fetch the exact OpenJDK Mobile snapshot used by the native probe."""
import hashlib
import pathlib
import urllib.request
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent / '.build' / 'openjdk'
root.mkdir(parents=True, exist_ok=True)
artifacts = {
 'OpenJDK.xcframework': 'ae8e22142e45e5c1e9e8e3541829f3cc00584658eb21eeeb0d3612e3fbaf7c9f',
 'java.base-device': 'af099f41010c4ceffd21231ae7d40b7c292190ab44c19616077545ae609f8c8d',
 'java.base-simulator': '5b0e75dbd88dd4f35f3108b263969d311ed697c1397a3fd0a247505acf91e49a',
}
for name, expected in artifacts.items():
 archive = root / (name + '.zip')
 if not archive.exists():
  with urllib.request.urlopen('https://github.com/openjdk-mobile/ios-tools/releases/download/snapshot/' + archive.name, timeout=120) as response:
   archive.write_bytes(response.read())
 if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
  raise SystemExit(f'Checksum mismatch: {archive}; snapshot may have changed. Do not update hashes blindly.')
 with zipfile.ZipFile(archive) as source:
  destination = root / name
  for member in source.infolist():
   if not (destination / member.filename).resolve().is_relative_to(destination.resolve()):
    raise SystemExit('Unsafe archive path')
  source.extractall(destination)
 print(f'Verified {name}')
