# Embedded media libraries

The native media adapter links FFmpeg 9.0.2 from
https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz.
SHA-256: `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`.

`./moku-ios backend ffmpeg --platform simulator` (or `--platform device`) verifies that archive and
builds static LGPL libraries with command-line programs, GPL and nonfree
components disabled. It uses Apple SDK SecureTransport, VideoToolbox and libxml2.
The source archive, complete source tree, libraries, headers,
`COPYING.LGPLv2.1`, and `LICENSE.md` are retained under `Services/.build`.

The CLI copies these notices into `ThirdPartyNotices/FFmpeg` in the app bundle.

`libtsmedia.a` is linked separately from the force-loaded Go/JVM archive. To
relink with modified compatible FFmpeg libraries, replace the built FFmpeg
libraries under `.build/ffmpeg/<platform>/lib`, remove the matching native build
cache, and run `./moku-ios backend native --platform <platform>` and the app build again.
Distributions must include the FFmpeg notices/license and the applicable source
and relinking materials; the local build cache is not itself a distribution.

The macOS `video-engine-probe` tests the same Objective-C processing adapter.
Host FFmpeg command-line tools are used only to generate and inspect test media;
they are never packaged or invoked by the iOS downloader.
