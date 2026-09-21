# moku-ios

The repository's Swift development tool. Run `./moku-ios` from the app checkout;
the launcher builds the tool with SwiftPM before executing it. No global install,
Rust toolchain, saved checkout configuration, or separate repository is needed.

```sh
./moku-ios doctor
./moku-ios dev
./moku-ios run --simulator SIMULATOR_UDID
./moku-ios build --platform device
./moku-ios backend jvm
./moku-ios test unit
./moku-ios test ui
./moku-ios test cli
./moku-ios help
```

`dev` watches source changes, reuses unchanged backend outputs, and rebuilds and
relaunches the app. App data persists; process state resets. `run` performs one
build and launch. Use `backend` to force all native components to rebuild, or
select `go`, `jvm`, `sandbox`, or `native`. The default platform is Simulator.

`test` defaults to app unit tests. Other suites are `ui`, `live-ui`, `backend`,
`acceptance`, `acceptance-live`, `search`, `jvm`, `cli`, and `all`. Live suites
need network access; `all` includes live source checks. Use `--simulator UDID`
when multiple simulators are booted.

`generate` runs XcodeGen. `format` checks app Swift formatting; add `--fix` to
apply formatting. `simulators` lists available devices.

The launcher selects its own checkout. `--repo PATH` overrides `MOKU_IOS_DIR`.
The compiled executable can also discover the checkout from its current directory.
Xcode's resource build phase uses the in-repo launcher, or the running binary via
`MOKU_IOS_TOOL` when invoked by this tool. `embed-backend` is internal and requires
Xcode's platform and resource destination environment.

Tool development:

```sh
swift test --package-path Tools/MokuIOS
```
