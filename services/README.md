# Embedded backend service

Tsunagu's Go backend and OpenJDK Zero run inside the iOS app process. Swift and
Objective-C call the Go bindings; Go talks to the embedded Kotlin sandbox over
an authenticated, dynamically allocated loopback gRPC port. No Java or Go child
process is launched. The SwiftUI frontend links this runtime for search, extension management, and source preferences.

## Verified on 2026-09-20

The backend-only simulator acceptance gate passes source metadata and images,
JAR/APK extension execution, actual Graal novel chapter fetching, public content,
MP4 seeking/HLS delivery, downloads, library/admin operations, and offline content
after a complete app/JVM relaunch. Native media fixtures additionally cover finite
DASH, HLS variants, AES-128, conversion, cancellation and invalid inputs. Physical
iPhone checks cover embedded MP4 handling and VideoToolbox/AAC conversion.

See [the recorded baseline](tests/BASELINE.md) for exact results and outstanding
validation, and [the service contracts](SERVICES.md) for native lifecycle, manual
browser verification, imports, capabilities and automation policies. Product UI
integration is outside this work. Fixture success is not a guarantee of third-party
source availability or universal extension compatibility.

## Reproduce

Requires Apple Silicon macOS, full Xcode, Go, Python 3.12+, and a JDK 25 boot
compiler. Set `MOKU_BOOT_JDK` if it is not `/opt/homebrew/opt/openjdk@25`.
Run native builds sequentially; generation replaces output directories. The in-repo Swift tool
is the public entry point; scripts under `services/scripts` are internal build recipes.

```sh
./moku-ios backend                     # Build all simulator backend components
./moku-ios test backend                # Go race/vet and Swift bridge checks
./moku-ios test acceptance             # Core media parity gate on embedded JVM
./moku-ios test acceptance-live        # Same plus live MangaDex/search/cover
./moku-ios test search                 # Fresh MangaDex install and title search
./moku-ios test jvm                    # Separate-JAR loading and reflection
./moku-ios backend --platform device   # Device libraries; no deployment
./moku-ios dev                         # Full app in Simulator, watching changes
```

The runner fails on startup, GraphQL, installation, download validation, or a
missing exact `Rent-A-Girlfriend` title. Each search creates a new test directory
so previously installed extensions cannot satisfy the test. It leaves the data
and `Documents/probe.json` for inspection. Live repository/search tests require
internet and depend on the current catalog and website.

The broader [backend acceptance gate](tests/README.md) now checks actual source
metadata, image bytes, anime stream extraction, content delivery and offline
downloads with synthetic sources, plus optional live MangaDex checks. It reports
all missing capabilities as failures and writes JSON/JUnit results. The earlier
search proof and Go regression tests passing do **not** establish media parity.

The OpenJDK source revision is pinned to
`dfd62e275c0970f75595f8bfe91eff34923fa896`. Build inputs (JDK 21 for Kotlin, Gradle
8.14.4, and iOS libffi archives) have pinned download SHA-256 hashes in
`scripts/fetch-build-inputs.py`. Go mobile tools are pinned in go.mod/go.sum.
Sources and generated outputs stay under ignored `.build/` directories.

## JVM fixes

The earlier prebuilt OpenJDK snapshot could link but could not execute this flow.
The local source build applies `patches/0002-openjdk-ios.patch`:

- Zero's code-cache allocation requests read/write memory, without executable
  permission, on iOS. Its interpreter uses that allocation for metadata.
- The JDK operating-system enum recognizes iOS, and its ephemeral-port defaults
  follow the Darwin range. Process-launch support is not added.

Packaging includes the required Java modules, generated security configuration,
CA certificates, and timezone data. `java.home` points to the bundled exploded
runtime. Native JNI entry points must survive static linking **and** be exported:
use the `-force_load` and `-export_dynamic` flags from the native build script.
The packaged static libraries include `libverify`, required by legacy bytecode
verification during APK conversion.
Novel plugins use the Graal fallback interpreter with `java.home` explicitly
provided for the exploded runtime. TLS uses the bundled JDK providers; the embedded entry point does not load desktop
Conscrypt binaries. Netty uses Java NIO instead of native transports.

References: [OpenJDK Mobile](https://github.com/openjdk/mobile),
[upstream iOS example](https://github.com/openjdk-mobile/ios-tools/blob/main/docs/helloworld.md).
The older `fetch-openjdk.py` remains for reproducing the original snapshot; it is
not the working runtime. `MOKU_LOCAL_JDK=0` selects that historical build input.

## App integration and lifecycle

### Media delivery performance

The embedded content proxy forwards HLS/DASH segment bytes as they arrive and
flushes each chunk to the player. Its 24 MiB object limit applies only to caching;
larger segments are forwarded in full. Incomplete transfers are aborted and never
cached. `backend/internal/api/rest/segment_stream_test.go` tests delivery before
upstream completion, oversized segments, range responses, and failed transfers.

For manga sources that resolve image URLs separately from page lists, the sandbox
resolves up to three URLs concurrently while retaining chapter order. Sources
that already supply image URLs incur no extra requests. `PageResolutionTest`
checks concurrency, ordering, and cancellation after a source failure.

These changes remove avoidable waits inside the app. They do not establish a
latency guarantee for third-party source extraction or upstream bandwidth.

### Startup

Start `TSJavaRuntime` once per app process, off the main thread. Pass the bundled
runtime home, Sandbox.jar path, an app-owned data directory, and a fresh random
credential (at least 32 characters). `startSandboxWithRuntimeHome:...` returns the
loopback port. The JVM and Kotlin sandbox live for the app process; they are not
recreated when the Go service stops. Startup errors can still abort OpenJDK, so
this remains a feasibility implementation, not a production lifecycle guarantee.

Then call `BackendController.start(dataDirectory:sandbox:)` with its
`EmbeddedSandbox(address:token:)`, or the generated Objective-C
`BackendService.startWithSandbox:address:token:error:`. Without sandbox settings,
`start(dataDirectory:)` starts offline library, local-content and administration services.

The Swift connection provides `statusRequest()` and `graphqlRequest(query:)`.
Use a URLSession that rejects redirects when sending its bearer credential.
Stopping Go drains HTTP and service workers before closing gRPC and SQLite, and never kills the app's JVM.
No background execution guarantee is implied.

Outputs are `.build/Tsunagu.xcframework`, `.build/native-{simulator,device}/libtsunagu.a`,
`libtsmedia.a`, and `MokuBackendProbe.app`. The combined archive contains Go, the JNI wrapper,
OpenJDK, and libffi native code. Java classes/JARs/configuration are separate app
resources. Link the archive **or** the Go framework, not both; keep the generated
framework headers available. The script records the required Apple/system libraries.

## API scope

All Go endpoints bind `127.0.0.1` on an allocated port and require a fresh per-start
bearer token. JVM gRPC requires a separate in-memory credential and also binds only
numeric loopback. Credentials are never logged. An unavailable embedded JVM never
triggers desktop process spawning.

GraphQL and content contracts are preserved; source-dependent fields are checked
against initialized capabilities. Metadata, images, downloads, library, discovery,
trackers, backups, local scanning and foreground scheduling are composed at startup.
See [service interfaces and platform limitations](SERVICES.md).

## Upstream changes

`vendor/Tsunagu` remains a pinned submodule. Its intentionally dirty changes are
preserved in `patches/0001-embedded-core.patch`: mobile API, embedded Go client,
Kotlin entry point, installation failure handling, and tests. `prepare.sh` applies
it idempotently and fails on conflicting edits without resetting them. Do not
point the parent repository at an unpublished submodule commit. Builds do not
pull arbitrary new upstream revisions.

The generated Objective-C bindings emit an initializer nullability warning;
compilation succeeds. The native test host in `tests/NativeProbe.m` is backend
verification infrastructure, not the product app/frontend.

### Embedded gRPC keepalive

The embedded Netty server must allow idle client pings every 20 seconds, matching
Go's sandbox client. Its minimum accepted interval is 15 seconds and idle pings
are permitted, matching the desktop server. Netty defaults instead reject these
pings and eventually close the channel with `ENHANCE_YOUR_CALM / too_many_pings`.
`EmbeddedKeepaliveTest` holds a real loopback connection idle for 75 seconds and
checks that it remains usable without a disconnect or reconnect. This policy and
test are included in `0001-embedded-core.patch` for reproducible sandbox builds.


### Independent core and source startup

The app starts `BackendController.start(dataDirectory:deferSandbox: true)` for
local SQLite/HTTP access, then calls `attachSandbox` when the app-hosted JVM is
ready. The Go binding exposes `StartDeferredSandbox` and `AttachSandbox`.
Attachment preserves the listener, credential, resolver graph, and database.
Local catalog queries work while Java is pending or after Java startup fails;
source capabilities stay unavailable until attachment. Download workers start
only after attachment and scheduled source refresh skips the pending runtime.
All native calls run on the controller's serial utility queue. Swift API session
initialization, decoding and cache work run on their service actors, not during
main-thread view creation. Source calls still use the single process-wide JVM.
