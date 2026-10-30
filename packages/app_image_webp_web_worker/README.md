# tekartik_app_image_webp_web_worker

WebP encoding off the main thread. On the web, the pure Dart encoder of
[tekartik_app_image_webp](../app_image_webp) runs in a web worker, the
`webp_worker.js` script that the setup step builds with dart2js. On io it
runs in an isolate.

The main user is Safari: it cannot encode WebP from a canvas, and the pure
Dart encoder takes ~0.2 s for 640x480 and ~1.3 s for 1920x1440 with dart2js,
which freezes the page when it runs on the main thread (4.4 s for a
4000x2250 crop in the demo, against a 0.2 s longest task with the worker).

The encoder is not in `main.dart.js`: `webp_worker.js` (240 KB, 81 KB gzip)
is loaded on the first encoding, and the main thread fallback (when the
script is missing) loads the encoder as a deferred library.

With `tekartik_app_image_web`, use the worker when the browser cannot encode
webp (see `example/app_pick_crop_image_demo/lib/main.dart`):

```dart
if (!browserEncodesWebp) {
  appImageWebpEncoder = (image, options) =>
      webpWorker.encode(image, options: options, transfer: true);
}
```

## Setup

```yaml
dependencies:
  tekartik_app_image_webp_web_worker:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_image_webp_web_worker
    version: '>=0.1.0'
```

Build `web/webp_worker.js` in the app (a Flutter or Dart web app):

```dart
// tool/dev_build_setup.dart: run_ci (dev_build >= 1.1.16) runs it after
// format and analyze, before the tests and the build.
import 'package:tekartik_app_image_webp_web_worker/setup.dart';

Future<void> main() => setupWebpWorker();
```

or `dart run tekartik_app_image_webp_web_worker:setup [--dir web] [--force]`.
Run it before `flutter build web` / `webdev build` in the deploy scripts too,
and git-ignore `web/webp_worker.js`.

The setup step uses
[tekartik_web_worker_build](https://github.com/tekartik/app_build.dart/tree/main/packages/web_worker_build).
It compiles in `.dart_tool/tekartik_app_image_webp_web_worker/webp_worker/`
with the package config of the app (`dart compile js -O2`). Its `meta.json`
records the Dart SDK and the version of every package of the worker (and a
hash of the sources of path packages). It compiles again only when one of
them changed (about 1.5 s); otherwise it only copies the script when it
differs.

## Usage

```dart
import 'package:tekartik_app_image_webp/webp.dart';
import 'package:tekartik_app_image_webp_web_worker/webp_worker.dart';

var bytes = await webpWorker.encode(
  WebpImage(width, height, rgba),
  options: const WebpEncodeOptions(quality: 80),
  // getImageData pixels used once: moved to the worker, not copied.
  transfer: true,
);
```

- `WebpWorker(url: 'webp_worker.js', fallback: true, startTimeout: 30 s)`
  starts the worker on the first `encode`. `url` is relative to the page
  (its `<base href>`).
- The worker answers a `ready` message with its protocol version. If the
  script is missing (404, or an html page served instead), does not start,
  or was built for another version, the images are encoded on the main
  thread with a console warning. With `fallback: false`, `encode` throws a
  `StateError` instead. `await worker.ready` tells which case applies.
- Encodings run one after the other in the worker, and several can be
  pending. An encoder error is a `WebpWorkerException`.
- The messages are plain JS objects (`type`, `id`, `width`, `height`,
  `rgba` as a Uint8Array, `options` as in `webpEncodeOptionsToMap`). Plain
  JavaScript can post them too.

Tested in Chrome (dart2js and dart2wasm pages) and on the VM.
