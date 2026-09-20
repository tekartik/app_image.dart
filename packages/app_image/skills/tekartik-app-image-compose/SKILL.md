---
name: tekartik-app-image-compose
description: >-
  Use when producing image bytes with tekartik_app_image: composing, cropping,
  resizing or watermarking with composeImage, ImageComposerData and
  ImageLayerData, generating a solid colour placeholder with
  generatePlaceholderImage and argbToColorUint32, or converting/resizing a file
  to WebP on the VM with fileCopyToWebp, WebpOptions, webpOptionsLossless,
  webpOptionsQuality50 and webpOptionsQuality75 (cwebp command line).
---

# Composing, generating and converting images (tekartik_app_image)

Besides the shared image model (see the sibling skill
[../tekartik-app-image-model/SKILL.md](../tekartik-app-image-model/SKILL.md)),
`tekartik_app_image` ships three small producers: a layer composer built on
`package:image`, a placeholder generator, and a `dart:io` helper that shells
out to `cwebp`. All of them return or write jpg/png/webp bytes described by an
`ImageData`.

## Guidelines

* Git dependency (not on pub.dev):

  ```yaml
  dependencies:
    tekartik_app_image:
      git:
        url: https://github.com/tekartik/app_image.dart
        path: packages/app_image
      version: '>=0.1.0'
  ```

### Composing (crop, resize, overlay)

* Import `package:tekartik_app_image/image_composer/image_composer.dart` for
  `composeImage`, `ImageComposerData`, `ImageLayerData`, plus
  `package:tekartik_app_image/app_image.dart` for the encodings and sources.
* `composeImage(ImageComposerData(layers:, width:, height:, encoding:))`
  returns a `Future<ImageData>`. The 4 parameters are required;
  `width`/`height` are nullable:
  * both set: exact output size;
  * one set: the other is computed from the ratio of the first layer's
    `sourceCropRect` (or of the decoded first layer);
  * both `null`: the size of the first layer's crop, else the first layer's
    own size. With no layer at all it throws `ArgumentError`.
* Each `ImageLayerData(source:, sourceCropRect:, destination:)` is drawn in
  order on a transparent 4 channel canvas. `source` **must** implement
  `ImageSourceAsyncData` (`ImageSource.bytes(bytes)` does); anything else
  fails an assert. `sourceCropRect` is the region taken from that layer and
  `destination` the region it is drawn to, both `Rect<double>` from
  `package:tekartik_common_utils/size/size.dart`
  (`Rect<double>.fromLTWH(left, top, width, height)`); `destination` defaults
  to the whole output image.
* Only `ImageEncodingJpg` (honours `quality`) and `ImageEncodingPng` are
  really encoded — any other encoding, including `ImageEncodingWebp`, silently
  produces png bytes labelled with the encoding you passed. Do not ask this
  composer for webp; use `fileCopyToWebp` below or the
  `tekartik_app_image_webp` package.
* This implementation is pure Dart (`package:image`) and therefore CPU bound:
  fine for small images and for the VM, slow for big photos. On the web (and
  in Flutter web), prefer the canvas based `composeImage`/`resizeTo` of
  `tekartik_app_image_web`, which take the same `ImageComposerData`.
* A simple resize/crop is just a one layer composition; there is no `resize()`
  function in this package.

### Placeholders

* Import `package:tekartik_app_image/app_image_placeholder.dart` (it
  re-exports `app_image.dart`) and optionally
  `package:tekartik_app_image/app_color.dart`.
* `generatePlaceholderImage({encoding, width, height, color})` is async and
  returns `ImageData`. Defaults: 256x256, `ImageEncodingJpg(quality: 50)`,
  and no fill (a zero filled, i.e. black, image) when `color` is `null`.
* `color` is an `int` read as `0xAARRGGBB`. Note that
  `argbToColorUint32(a, r, g, b)` builds the opposite byte order
  (`0xAABBGGRR`), so it swaps red and blue here: pass `0xFFFF0000` for an
  opaque red placeholder.
* Use it for tests and for missing-image fallbacks; it never touches the
  filesystem, it just returns bytes.

### WebP conversion (VM only)

* Import `package:tekartik_app_image/webp_io.dart`. It uses `dart:io` and
  **runs the external `cwebp` binary** (libwebp): it only works on the VM with
  `cwebp` in the `PATH`, never in Flutter apps or on the web. For a pure Dart
  encoder, use the `tekartik_app_image_webp` package instead.
* `fileCopyToWebp(src, dst, {cropRect, resizeWidth, options, ifNotExists})`
  decodes `src` with `package:image`, optionally crops (`cropRect` is the
  **int** `Rect` of `package:tekartik_common_utils/size/int_size.dart`,
  `Rect.fromLTWH(...)`), optionally resizes to `resizeWidth` keeping the ratio,
  writes a temporary png and converts it. It creates the parent directory of
  `dst`. With `ifNotExists: true` it returns immediately if `dst` exists,
  which makes build scripts idempotent.
* `WebpOptions({lossless, quality, alphaQuality})` defaults to
  `quality: 50, alphaQuality: 100`. Use the ready made
  `webpOptionsQuality50`, `webpOptionsQuality75` or `webpOptionsLossless`
  (lossless ignores the quality values).

## Examples

Crop and resize an image with a one layer composition:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/image_composer/image_composer.dart';
import 'package:tekartik_common_utils/size/size.dart';

/// Take a 400x400 region at (100, 50) and export it as a 256x256 jpeg.
Future<ImageData> cropSquare(Uint8List bytes) async {
  return await composeImage(
    ImageComposerData(
      layers: [
        ImageLayerData(
          source: ImageSource.bytes(bytes),
          sourceCropRect: Rect<double>.fromLTWH(100, 50, 400, 400),
        ),
      ],
      width: 256,
      height: 256,
      encoding: ImageEncodingJpg(quality: 80),
    ),
  );
}

Future<void> main() async {
  var data = await cropSquare(await File('photo.jpg').readAsBytes());
  await File('thumb${data.encoding.extension}').writeAsBytes(data.bytes);
  print('${data.width}x${data.height} ${data.bytes.length} bytes');
}
```

Overlay a watermark, keeping the ratio of the background:

```dart
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/image_composer/image_composer.dart';
import 'package:tekartik_common_utils/size/size.dart';

/// 1024 pixels wide, height derived from the background ratio.
Future<ImageData> watermark(Uint8List photo, Uint8List logo) async {
  return await composeImage(
    ImageComposerData(
      layers: [
        // First layer: drawn full size, gives the output ratio.
        ImageLayerData(source: ImageSource.bytes(photo)),
        // Second layer: 128x128 logo in the top left corner.
        ImageLayerData(
          source: ImageSource.bytes(logo),
          destination: Rect<double>.fromLTWH(16, 16, 128, 128),
        ),
      ],
      width: 1024,
      height: null,
      encoding: const ImageEncodingPng(),
    ),
  );
}
```

Generate a placeholder:

```dart
import 'dart:io';

import 'package:tekartik_app_image/app_image_placeholder.dart';

Future<void> main() async {
  // Default: 256x256 jpeg quality 50, black.
  var black = await generatePlaceholderImage();

  // Opaque red 64x64 png (color is read as 0xAARRGGBB).
  var red = await generatePlaceholderImage(
    width: 64,
    height: 64,
    color: 0xFFFF0000,
    encoding: const ImageEncodingPng(),
  );

  await File('placeholder${red.encoding.extension}').writeAsBytes(red.bytes);
  print('${black.width}x${black.height} ${black.encoding}');
}
```

Convert a picture to WebP on the VM (requires `cwebp` in the `PATH`):

```dart
import 'package:tekartik_app_image/webp_io.dart';
import 'package:tekartik_common_utils/size/int_size.dart';

Future<void> main() async {
  // Full size, quality 75.
  await fileCopyToWebp(
    'assets/photo.jpg',
    'build/photo.webp',
    options: webpOptionsQuality75,
  );

  // Cropped square, resized to 512 pixels wide, lossless, skipped if present.
  await fileCopyToWebp(
    'assets/photo.jpg',
    'build/photo_512.webp',
    cropRect: Rect.fromLTWH(0, 0, 1000, 1000),
    resizeWidth: 512,
    options: webpOptionsLossless,
    ifNotExists: true,
  );
}
```
