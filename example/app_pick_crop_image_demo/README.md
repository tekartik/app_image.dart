# tekartik_pick_crop_image_demo

Pick crop image demo ([Online web demo](http://pickcropimage-demo.web.app/))

Work on Desktop, Mobile and Web.

## WebP encoding

Two entry points, the same app:

- `lib/main.dart`: `isWebpEncodingSupported()` (a canvas
  `toDataURL('image/webp')`); when it is, the browser encodes webp
  (tekartik_app_image_web), otherwise (Safari) the web worker does
  (`web/webp_worker.js`, built by `tool/dev_build_setup.dart`, loaded on the
  first encoding).
- `lib/main_webp_direct.dart`: always the pure Dart encoder, on the main
  thread (`flutter run -d chrome -t lib/main_webp_direct.dart`).

Measured on 2026-10-30 (`flutter build web`, release; a 4000x2250 crop in
headless Chrome, Safari simulated by a canvas returning png for webp):

| | `main.dart` | `main_webp_direct.dart` |
| --- | --- | --- |
| `main.dart.js` | 2,736,673 bytes (804,740 gzip) | 2,854,633 bytes (849,155 gzip) |
| loaded on demand | `webp_worker.js` 240,371 (80,632 gzip) in Safari; `main.dart.js_1.part.js` 121,504 (46,129 gzip) only if the worker is missing | - |
| longest main thread task while encoding | 205 ms (worker) | 4,356 ms |

The pure Dart encoder adds 118 KB (44 KB gzip) to `main.dart.js`.

## Setup

Project files are not checked so this must be performed once

```shell
flutter create .
flutter run
```