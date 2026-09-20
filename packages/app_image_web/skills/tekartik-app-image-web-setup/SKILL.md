---
name: tekartik-app-image-web-setup
description: >-
  Use when resizing, cropping or re-encoding image bytes in a Dart web or
  Flutter app with tekartik_app_image_web: resizeTo with ResizeOptions and
  CropRect from package:tekartik_app_image_web/app_image_web.dart, and
  getImageMetaFromBytes from package:tekartik_app_image_web/image_decoder.dart,
  which use the browser canvas on the web and package:image elsewhere and
  return an ImageData (bytes, width, height, encoding).
---

# Resizing and decoding images on the web (tekartik_app_image_web)

`tekartik_app_image_web` is the web implementation of the `tekartik_app_image`
model: it resizes, crops and re-encodes image bytes with the browser canvas
when compiled for the web, and transparently falls back to the pure Dart
`package:image` composer on the VM (and on Flutter mobile/desktop), so the same
call site works everywhere.

## Guidelines

* It is not on pub.dev, depend on it from git (it pulls `tekartik_app_image`
  in as well):

  ```yaml
  dependencies:
    tekartik_app_image_web:
      git:
        url: https://github.com/tekartik/app_image.dart
        path: packages/app_image_web
      version: '>=0.1.0'
  ```

* There are exactly two public entry points; never import
  `package:tekartik_app_image_web/src/...` (it is implementation only and the
  conditional imports there are already handled for you):
  * `package:tekartik_app_image_web/app_image_web.dart` — `resizeTo`, plus
    `ResizeOptions` and `CropRect` re-exported from `tekartik_app_image`.
  * `package:tekartik_app_image_web/image_decoder.dart` —
    `getImageMetaFromBytes`.
  Encodings (`ImageEncodingJpg`, `ImageEncodingPng`), `ImageData` and
  `ImageMeta` come from `package:tekartik_app_image/app_image.dart`.
* `resizeTo(Uint8List bytes, {required ResizeOptions options})` returns a
  `Future<ImageData>`: bytes plus the final `width`, `height` and `encoding`.
  It always re-encodes, even when nothing is resized.
* `ResizeOptions(width:, height:, cropRect:, encoding:)`: `width` and `height`
  are required named but nullable, and drive the output size:
  * both set — exact size (the source is stretched to it);
  * only one set — the other is computed from the aspect ratio of `cropRect`
    when there is one, else of the source image;
  * both `null` — the crop size, else the source size.
* `cropRect` is a `CropRect` (`Rect<double>`, i.e.
  `CropRect.fromLTWH(left, top, width, height)`) describing the region of the
  source to take. Give it the rectangle produced by your crop UI (that is what
  `tekartik_app_pick_crop_image_flutter` does).
* `encoding` defaults to `const ImageEncodingPng()`. Use
  `ImageEncodingJpg(quality: 0..100)` for photos. Do **not** pass
  `ImageEncodingWebp`: the canvas path throws `UnsupportedError` and the VM
  fallback silently returns png bytes. Encode webp with the
  `tekartik_app_image_webp` package instead.
* `getImageMetaFromBytes(bytes)` returns a `Future<ImageMeta>` (width, height,
  encoding). On the web it loads the bytes into an image element (no pixel
  decoding in Dart, so it is fast and supports whatever the browser supports);
  on the VM it decodes with `package:image`. It throws `UnsupportedError` when
  the header is neither jpg, png nor webp.
* Both APIs are `async` and must be awaited: the canvas implementation goes
  through `HTMLImageElement.onLoad` and `canvas.toBlob`, so it needs a real
  browser document — it does not work in a plain web worker, and on the VM
  it is CPU bound instead.
* In a Flutter app, run big resizes through `compute()` so the UI thread stays
  free (`compute` is a no-op hop on the web, and a real isolate on
  mobile/desktop where the `package:image` fallback is used).
* Testing: `dart test` exercises the `package:image` fallback and
  `dart test -p chrome` the canvas implementation; write the test once against
  `resizeTo` and run both, as the package's own `test/image_resize_test.dart`
  does. Keep fixture bytes in a Dart file (`Uint8List.fromList([...])`) rather
  than reading files, so the same test compiles for the browser.

## Examples

Make a jpeg thumbnail, height computed from the source ratio:

```dart
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';

Future<ImageData> thumbnail(Uint8List bytes) async {
  var data = await resizeTo(
    bytes,
    options: ResizeOptions(
      width: 256,
      height: null, // computed from the ratio
      encoding: ImageEncodingJpg(quality: 80),
    ),
  );
  print('${data.width}x${data.height} ${data.encoding} ${data.bytes.length}');
  return data;
}
```

Crop then resize, e.g. from a crop UI rectangle:

```dart
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';

/// [cropRect] is in source pixels.
Future<ImageData> squareAvatar(Uint8List bytes, CropRect cropRect) async {
  return await resizeTo(
    bytes,
    options: ResizeOptions(
      width: 512,
      height: 512,
      cropRect: cropRect,
      encoding: const ImageEncodingPng(),
    ),
  );
}

Future<void> main() async {
  var bytes = Uint8List.fromList([137, 80, 78, 71]);
  await squareAvatar(bytes, CropRect.fromLTWH(100, 100, 400, 400));
}
```

Read the size first and only re-encode when the image is too big:

```dart
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:tekartik_app_image_web/image_decoder.dart';

Future<Uint8List> boundedImage(Uint8List bytes, {int maxWidth = 1024}) async {
  ImageMeta meta;
  try {
    meta = await getImageMetaFromBytes(bytes);
  } on UnsupportedError catch (_) {
    // Not a jpg/png/webp.
    rethrow;
  }
  if (meta.width <= maxWidth) {
    return bytes; // Nothing to do, keep the original bytes.
  }
  var data = await resizeTo(
    bytes,
    options: ResizeOptions(
      width: maxWidth,
      height: null,
      encoding: meta.encoding is ImageEncodingJpg
          ? ImageEncodingJpg(quality: 85)
          : const ImageEncodingPng(),
    ),
  );
  return data.bytes;
}
```

Test that runs on the VM (`dart test`) and in a browser
(`dart test -p chrome`):

```dart
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:test/test.dart';

/// Inline fixture so the test also compiles for the browser.
final jpgBytes = Uint8List.fromList([255, 216, 255, 224]);

void main() {
  test('resize keeps the ratio', () async {
    var result = await resizeTo(
      jpgBytes,
      options: ResizeOptions(width: 48, height: null),
    );
    expect(result.width, 48);
    expect(result.encoding, isA<ImageEncodingPng>());
  });
}
```
