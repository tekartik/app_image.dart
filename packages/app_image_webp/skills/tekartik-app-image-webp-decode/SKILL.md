---
name: tekartik-app-image-webp-decode
description: Decode WebP files and read WebP headers in pure Dart with tekartik_app_image_webp (decodeWebp, webpInfo, WebpImage, decodeImageWebp bridge to package:image). Use when Dart or Flutter code must read .webp bytes, inspect a WebP width/height/alpha/lossless flags, convert WebP to RGBA pixels or to a package:image Image, or handle WebpFormatException.
license: BSD-2-Clause
metadata:
  package: tekartik_app_image_webp
  author: tekartik
---

# Decoding WebP with tekartik_app_image_webp

Pure Dart decoder (no ffi, works on VM, Flutter and web) for still WebP
images: lossy `VP8`, lossless `VP8L`, alpha (`ALPH`) and the `VP8X`
container. Output is bit-exact with libwebp's `dwebp`. Animated files are
not supported.

## Setup

```yaml
dependencies:
  tekartik_app_image_webp:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_image_webp
      ref: dart3a
```

```dart
import 'package:tekartik_app_image_webp/webp.dart';
```

## Guidelines

- Pass the whole file (RIFF container) as a `Uint8List`; there is no
  streaming or partial decoding.
- Call `webpInfo(bytes)` when only the dimensions, format or alpha flag are
  needed: it parses headers only and is much cheaper than a full decode.
- `decodeWebp(bytes)` returns a `WebpImage`: `width`, `height` and `rgba`
  (`width * height * 4` bytes, RGBA order, straight/non-premultiplied alpha).
  Use `getPixel(x, y)` for a `0xAARRGGBB` value or read `rgba` directly.
- Every failure (truncated data, bad signature, unsupported feature such as
  animation) throws `WebpFormatException` (implements `FormatException`).
  Catch it; do not catch generic exceptions.
- Check `WebpInfo.hasAnimation` before decoding if animated input is
  possible; `decodeWebp` rejects animations.
- For `package:image` users, import `image_web.dart` and call
  `decodeImageWebp(bytes)`, which returns `img.Image?` (null on invalid or
  animated data, like the `image` package's own decoders).
- Decoding is synchronous and CPU bound (a few ms for small images, tens of
  ms for a 1024x768 photo on the VM). In Flutter, run large decodes in an
  isolate (`Isolate.run`).

## Examples

Header only:

```dart
final info = webpInfo(bytes);
print('${info.width}x${info.height} '
    'lossless=${info.isLossless} alpha=${info.hasAlpha} '
    'animated=${info.hasAnimation}');
```

Full decode with error handling:

```dart
import 'dart:io';
import 'package:tekartik_app_image_webp/webp.dart';

WebpImage? readWebp(String path) {
  final bytes = File(path).readAsBytesSync();
  try {
    return decodeWebp(bytes);
  } on WebpFormatException catch (e) {
    stderr.writeln('not a decodable WebP: ${e.message}');
    return null;
  }
}

final image = readWebp('photo.webp');
if (image != null) {
  final argb = image.getPixel(10, 10); // 0xAARRGGBB
  final alpha = image.rgba[(10 * image.width + 10) * 4 + 3];
}
```

To a `package:image` image (for further processing or PNG export):

```dart
import 'package:image/image.dart' as img;
import 'package:tekartik_app_image_webp/image_web.dart';

final img.Image? image = decodeImageWebp(bytes);
if (image != null) {
  File('out.png').writeAsBytesSync(img.encodePng(image));
}
```

To Flutter pixels: `WebpImage.rgba` matches `ui.PixelFormat.rgba8888`, so
`ui.decodeImageFromPixels(image.rgba, image.width, image.height,
ui.PixelFormat.rgba8888, callback)` displays it without any conversion.

## Edge cases

- 1x1 images and odd sizes are fine; the maximum size is 16383x16383.
- Files with `EXIF`, `XMP` or `ICCP` chunks decode normally; the flags are
  reported by `WebpInfo` but the metadata is not returned.
- A `VP8X` file whose canvas size differs from the bitstream size is decoded
  at the bitstream size.

See [references/api.md](references/api.md) for the complete decoding API.
