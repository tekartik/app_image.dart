---
name: tekartik-app-image-webp-web-worker
description: >-
  Use when Dart or Flutter web code must encode WebP without freezing the
  page (Safari has no canvas webp encoding) with
  package:tekartik_app_image_webp_web_worker: WebpWorker (encode in a web
  worker, isolate on io, main thread fallback, transfer, ready, close),
  webpWorker (the default one, plugged into tekartik_app_image_web with
  appImageWebpEncoder when the browser cannot), WebpWorkerException, and the setup step building
  web/webp_worker.js (setupWebpWorker in tool/dev_build_setup.dart, dart run
  tekartik_app_image_webp_web_worker:setup).
license: BSD-2-Clause
metadata:
  package: tekartik_app_image_webp_web_worker
  author: tekartik
---

# WebP encoding in a web worker

```dart
import 'package:tekartik_app_image_webp/webp.dart';
import 'package:tekartik_app_image_webp_web_worker/webp_worker.dart';

var bytes = await webpWorker.encode(
  WebpImage(width, height, rgba),
  options: const WebpEncodeOptions(quality: 80),
  transfer: true, // rgba used once (getImageData): moved, may be emptied
);
```

## The app must build the worker script

```dart
// tool/dev_build_setup.dart (run_ci runs it before tests and build)
import 'package:tekartik_app_image_webp_web_worker/setup.dart';

Future<void> main() => setupWebpWorker(); // writes web/webp_worker.js
```

- Or `dart run tekartik_app_image_webp_web_worker:setup [--dir web] [-f]`.
  Run it before `flutter build web` in deploy scripts, and git-ignore
  `web/webp_worker.js`.
- It is rebuilt only when the Dart SDK or a package of the worker changed
  (`.dart_tool/tekartik_app_image_webp_web_worker/webp_worker/meta.json`).
  It is built with tekartik_web_worker_build (app_build.dart).

## Behavior

- `WebpWorker({url = 'webp_worker.js', fallback = true, startTimeout})`
  starts on the first `encode`. `await ready` is true when encoding runs off
  the main thread.
- If the script is missing, fails to start or has the wrong protocol
  version, encoding falls back to the main thread (console warning). With
  `fallback: false`, `encode` throws a `StateError`.
- Encoder errors are a `WebpWorkerException` on the web (the original
  error on io). `close()` fails pending encodings, and later calls throw.
- On io, each encoding runs in an `Isolate.run`. `url` and `fallback` are
  ignored there.
- The encoder stays out of `main.dart.js`: `webp_worker.js` loads on the
  first encoding, and the main thread fallback loads the encoder through a
  deferred import.
- With tekartik_app_image_web, plug the worker in when the browser cannot
  encode webp (canvas `toDataURL('image/webp')` gives png in Safari):
  `appImageWebpEncoder = (image, options) => webpWorker.encode(image,
  options: options, transfer: true);`. Without it, app_image_web encodes
  on the main thread (deferred encoder).
- Browser tests: `setupWebpWorker(dir: 'test')` in the tool and in a VM
  test. `WebpWorker()` then loads `test/webp_worker.js` relative to the test
  page. The package needs `build_web_compilers` as a dev dependency for
  run_ci to run the browser tests.
