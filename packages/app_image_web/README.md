# tekartik_app_image_web

Resize, crop and re-encode image bytes (jpg, png, webp), with the browser
canvas on the web and the pure Dart
[package:image](https://pub.dev/packages/image) composer of
[tekartik_app_image](../app_image) everywhere else (Dart VM, Flutter mobile
and desktop): the same call works on every platform.

## Getting started

Not on pub.dev, add it as a git dependency (with `tekartik_app_image` for the
encodings and results):

```yaml
dependencies:
  tekartik_app_image:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_image
  tekartik_app_image_web:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_image_web
```

```dart
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';

/// A 256 pixels wide jpeg thumbnail, the height from the image ratio.
Future<ImageData> thumbnail(Uint8List bytes) => resizeTo(
  bytes,
  options: ResizeOptions(
    width: 256,
    height: null,
    encoding: ImageEncodingJpg(quality: 80),
  ),
);
```

Runnable example (it builds its source image, `dart run example/main.dart`):
[example/main.dart](example/main.dart).

## Platforms

- Web (dart2js and dart2wasm, Flutter web included): an image element and a
  canvas; it needs a document (not a web worker). Webp is encoded by the
  browser, or by the pure Dart encoder of
  [tekartik_app_image_webp](../app_image_webp) when the browser cannot
  (Safari), loaded on demand.
- Dart VM, Flutter mobile and desktop: `package:image`, CPU bound on the
  calling isolate (run big images through Flutter's `compute`).

## What to use

- `package:tekartik_app_image_web/app_image_web.dart`:
  `resizeTo(bytes, options: ResizeOptions(width:, height:, cropRect:,
  encoding:))` returns an `ImageData` (`bytes`, `width`, `height`,
  `encoding`); `ResizeOptions`, `CropRect`; `appImageWebpEncoder` (webp
  encoder of the web canvas, see below).
- `package:tekartik_app_image_web/image_decoder.dart`:
  `getImageMetaFromBytes(bytes)` returns an `ImageMeta` (`width`, `height`,
  `encoding`) without decoding the pixels in Dart on the web.
- Output size: both `width` and `height` set, the exact size (stretched);
  one of them, the other from the ratio of `cropRect` (or of the image);
  none, the size of `cropRect` (or of the image). `cropRect` is in source
  pixels (`CropRect.fromLTWH(left, top, width, height)`).
- Encodings (`tekartik_app_image`): `ImageEncodingPng()` (the default),
  `ImageEncodingJpg(quality: 0..100)`, `ImageEncodingWebp(quality: 0..100)`.

## Webp on the web

The browser encodes webp (`ImageEncodingWebp`). When it cannot (Safari),
the pure Dart encoder of tekartik_app_image_webp does, on the main thread,
loaded on demand (a deferred library, not in `main.dart.js`).

`appImageWebpEncoder` replaces the browser: set it to the web worker of
tekartik_app_image_webp_web_worker when the browser cannot encode webp (off
the main thread, `webp_worker.js` loaded on demand), or to `encodeWebp`
itself (in `main.dart.js`). See the two mains of
`example/app_pick_crop_image_demo`.

## Common pitfalls

- An output with a zero width or height (a tiny width on a very wide
  image: the height rounds to 0) cannot be encoded: the web throws a
  `StateError` (it used to never complete), the VM a `package:image`
  `ImageException` (`Cannot encode an empty image`, image 4.12).
- A jpeg read by `getImageMetaFromBytes` has an unknown quality
  (`imageEncodingJpgQualityUnknown`): give an explicit quality to re-encode
  it.
- Bytes the browser cannot decode (a broken file with a valid header) fail
  with the DOM error event on the web, a `FormatException` on the VM; bytes
  that are neither jpg, png nor webp throw `UnsupportedError` everywhere.
- The whole source and result are in memory: fine for photos, not for huge
  scans.

Agent skill:
[tekartik-app-image-web-setup](skills/tekartik-app-image-web-setup/SKILL.md).
