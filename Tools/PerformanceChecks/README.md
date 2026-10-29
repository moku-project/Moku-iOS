# Core performance regressions

Run from the repository root:

```sh
python3 Tools/PerformanceChecks/run.py
```

Requires macOS and Xcode's Swift toolchain. The runner links selected production core files and regression tests into a temporary Swift package and runs them on macOS. It does not launch Simulator, the iOS app, or the embedded backend. Build products are reused under `.build/performance-core-build`.

UIKit/SwiftUI interaction tests remain in the iOS test target. Compiling those tests with `build-for-testing` does not execute them. See [the audit](../../docs/UI_PERFORMANCE_AUDIT.md) for coverage and device verification.
