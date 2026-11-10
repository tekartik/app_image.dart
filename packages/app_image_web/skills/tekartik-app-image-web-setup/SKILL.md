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

* It is not on pub.dev, depend on it from git, with `tekartik_app_image`
  (the encodings and results you import):

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
      version: '>=0.1.0'
  ```

* There are exactly two public entry points; never import
  `package:tekartik_app_image_web/src/...` (it is implementation only and the
  conditional imports there are already handled for you):
  * `package:tekartik_app_image_web/app_image_web.dart` — `resizeTo`, plus
    `ResizeOptions` and `CropRect` re-exported from `tekartik_app_image`, and
    `appImageWebpEncoder` (the webp encoder of the web canvas, see the
    README).
  * `package:tekartik_app_image_web/image_decoder.dart` —
    `getImageMetaFromBytes`.
  Encodings (`ImageEncodingJpg`, `ImageEncodingPng`, `ImageEncodingWebp`),
  `ImageData` and `ImageMeta` come from
  `package:tekartik_app_image/app_image.dart`.
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
  `ImageEncodingJpg(quality: 0..100)` for photos.
  `ImageEncodingWebp(quality: 0..100)` (default 75) is encoded by the browser
  canvas when it can (Chrome, Firefox); otherwise (Safari) the canvas pixels
  go through the pure Dart encoder of `tekartik_app_image_webp` (lossy, same
  quality scale, both are libwebp), which is synchronous: about
  0.2 s for 640x480, 1.3 s for 1920x1440 in Chrome. The VM uses the same pure
  Dart encoder. The bytes always match the encoding.
* `getImageMetaFromBytes(bytes)` returns a `Future<ImageMeta>` (width, height,
  encoding). On the web it loads the bytes into an image element (no pixel
  decoding in Dart, so it is fast and supports whatever the browser supports);
  on the VM it decodes with `package:image`. It throws `UnsupportedError` when
  the header is neither jpg, png nor webp. Bytes with a valid header that the
  browser cannot decode fail with the DOM error `Event` on the web (a
  `FormatException` on the VM): catch everything, not only
  `FormatException`. A jpeg is reported with an unknown quality
  (`imageEncodingJpgQualityUnknown`): give an explicit quality to re-encode.
* An output with a zero width or height (a small width on a very wide
  image or crop: the computed height rounds to 0) cannot be encoded: the web
  throws a `StateError` (before 2026-11-10 it never completed), the VM the
  `package:image` `ImageException` (`Cannot encode an empty image`, image
  4.12). Keep the requested size at least the image ratio.
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
  does. Keep fixture bytes in a Dart file (`Uint8List.fromList([...])`, a
  real image file dumped as bytes) or build them with
  `generatePlaceholderImage` of
  `package:tekartik_app_image/app_image_placeholder.dart` (pure Dart) rather
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

import 'package:tekartik_app_image/app_image_placeholder.dart';
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
  // An 800x600 source (any jpg, png or webp bytes).
  var source = await generatePlaceholderImage(
    width: 800,
    height: 600,
    color: 0xFF2060A0,
    encoding: const ImageEncodingPng(),
  );
  var avatar = await squareAvatar(
    source.bytes,
    CropRect.fromLTWH(100, 100, 400, 400),
  );
  print('${avatar.width}x${avatar.height}'); // 512x512
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
import 'package:tekartik_app_image/app_image_placeholder.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:test/test.dart';

void main() {
  test('resize keeps the ratio', () async {
    // A 64x32 jpeg built in Dart, so the test also runs in the browser.
    var source = await generatePlaceholderImage(
      width: 64,
      height: 32,
      encoding: ImageEncodingJpg(quality: 80),
    );
    var result = await resizeTo(
      source.bytes,
      options: ResizeOptions(width: 48, height: null),
    );
    expect([result.width, result.height], [48, 24]);
    expect(result.encoding, isA<ImageEncodingPng>());
  });
}
```
