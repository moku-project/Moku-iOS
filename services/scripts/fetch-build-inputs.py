#!/usr/bin/env python3
"""Fetch checksum-pinned tools for the embedded JVM build, into ignored storage."""
import hashlib
import pathlib
import tarfile
import urllib.request
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent / '.build'
cache = root / 'toolchains'
cache.mkdir(parents=True, exist_ok=True)
assets = [
 ('jdk21.tar.gz', 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_aarch64_mac_hotspot_21.0.12.1_1.tar.gz', '3623232f33a9c3baadf304480b2535f9a3cba8a58d42ecbb438ba267315d9998', cache),
 ('gradle-8.14.4-bin.zip', 'https://services.gradle.org/distributions/gradle-8.14.4-bin.zip', 'f1771298a70f6db5a29daf62378c4e18a17fc33c9ba6b14362e0cdf40610380d', cache),
 ('libffi-ios-sim.zip', 'https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios-sim.zip', '701b522e3eff0263f18d4a9e487f0a7ac30050fb2af20e86b6849daa14f5781f', root / 'libffi-sim'),
 ('libffi-ios.zip', 'https://github.com/openjdk-mobile/ios-tools/releases/download/libffi-build/libffi-ios.zip', '4f39fd1d53fbd69d1bdbd915413077d130daa3f6792d1b3a03a690a9cbd4dea3', root / 'libffi-device'),
]
for name, url, digest, destination in assets:
    path = cache / name
    if not path.exists():
        temp = path.with_suffix(path.suffix + '.part')
        with urllib.request.urlopen(url, timeout=120) as response, temp.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        temp.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Checksum mismatch: {path}')
    marker = cache / (name + '.extracted')
    if destination and not marker.exists():
        if name.endswith('.tar.gz'):
            with tarfile.open(path) as archive:
                archive.extractall(destination, filter='data')
        else:
            with zipfile.ZipFile(path) as archive:
                for entry in archive.infolist():
                    if not (destination / entry.filename).resolve().is_relative_to(destination.resolve()):
                        raise SystemExit('Unsafe archive path')
                archive.extractall(destination)
            if name.startswith('gradle-'):
                (cache / 'gradle-8.14.4/bin/gradle').chmod(0o755)
        marker.touch()
    print(f'Verified {name}', flush=True)
