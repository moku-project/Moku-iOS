#!/usr/bin/env python3
"""Run core regression tests on macOS, without building or launching a simulator.

Production files are symlinked into a disposable Swift package: no alternate
implementation or backend stub is substituted. UIKit behavior needs device QA.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
sources = [
    "App/Navigation/AppTab.swift",
    "Shared/Cache/ResourceCache.swift", "Shared/Cache/ConcurrentMap.swift",
    "Shared/Media/Domain/MediaEntry.swift", "Shared/Media/Domain/ContentMode.swift",
    "Shared/Media/Domain/Chapter.swift", "Shared/Library/LibraryFolder.swift",
    "Shared/Activity/HomeEntry.swift", "Shared/Activity/HomeStatistics.swift",
    "Shared/Activity/HomeStore.swift", "Shared/Activity/HomeDisk.swift",
    "Features/Library/Domain/LibraryItem.swift", "Features/Library/LibraryViewModel.swift",
    "Features/Reader/Domain/ReaderSettings.swift", "Features/Reader/Data/ReaderPreferences.swift",
    "Features/Recent/Domain/RecentHistory.swift", "Features/Recent/Domain/RecentUpdate.swift",
]
tests = [
    "Tests/Shared/Activity/HomeStoreTests.swift",
    "Tests/Shared/Cache/CacheTests.swift",
    "Tools/PerformanceChecks/CorePerformanceTests.swift",
]
(root / ".build").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="performance-core-", dir=root / ".build") as path:
    package = Path(path)
    (package / "Sources/Moku").mkdir(parents=True)
    (package / "Tests/MokuTests").mkdir(parents=True)
    for source in sources:
        (package / "Sources/Moku" / Path(source).name).symlink_to(root / "Moku" / source)
    for test in tests:
        (package / "Tests/MokuTests" / Path(test).name).symlink_to(root / test)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PerformanceCore", platforms: [.macOS(.v14)], targets: [
    .target(name: "Moku"), .testTarget(name: "MokuTests", dependencies: ["Moku"])
])
''')
    subprocess.run(["swift", "test", "--package-path", str(package),
                    "--scratch-path", str(root / ".build/performance-core-build")], check=True)
