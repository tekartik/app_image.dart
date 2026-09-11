---
name: tekartik-app-image-webp-encode
description: Encode images to WebP in pure Dart with tekartik_app_image_webp (encodeWebp, WebpEncodeOptions, WebpPreset, encodeImageWebp bridge to package:image). Use when Dart or Flutter code must write .webp files, choose between lossy VP8 and lossless VP8L, tune quality, method, alpha or filter settings, or convert PNG/JPEG/package:image images to WebP without native libwebp.
license: BSD-2-Clause
metadata:
  package: tekartik_app_image_webp
  author: tekartik
---

# Encoding WebP with tekartik_app_image_webp

Pure Dart port of the libwebp encoder: lossy `VP8` (with lossless-compressed
alpha) and lossless `VP8L`. Output decodes with any WebP decoder; sizes and
quality match `cwebp` at the same settings within a few percent.

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

- Build a `WebpImage(width, height, rgba)` with straight (non-premultiplied)
  RGBA bytes, or start from `WebpImage.blank`, `fromRgb`, `fromArgb`.
- `encodeWebp(image, options: ...)` returns the complete file bytes
  (`Uint8List`, RIFF container). Default options are lossy, quality 75,
  method 4, lossless alpha, like `cwebp` defaults.
- Choose the mode:
  - photos and screenshots with many colors: lossy, `quality` 70..90;
  - graphics, icons, few colors, pixel-exact needs: `lossless: true`;
  - both modes keep transparency; lossy alpha is lossless unless
    `alphaQuality < 100`.
- `method` trades speed for size: 0 is fastest, 6 smallest; 4 is a good
  default. Encoding is CPU bound (about 0.3 to 0.7 s for a 1024x768 photo at
  method 4 on the VM); run it in an isolate in Flutter.
- Fully transparent pixels get their RGB discarded to improve compression.
  Set `exact: true` to preserve them (needed for pixel-exact lossless round
  trips of RGBA data).
- Use `WebpEncodeOptions.preset(WebpPreset.photo)` (or `picture`, `drawing`,
  `icon`, `text`) to get libwebp's tuned filter and noise-shaping settings,
  then `copyWith` to adjust.
- Input larger than 16383 in either dimension throws `ArgumentError`.
- For `package:image` inputs use `encodeImageWebp(img.Image, options: ...)`
  from `image_web.dart`; it converts any pixel format to 8-bit RGBA first.

## Examples

Lossy with tuned quality:

```dart
final bytes = encodeWebp(
  image,
  options: const WebpEncodeOptions(quality: 85, method: 5),
);
File('photo.webp').writeAsBytesSync(bytes);
```

Lossless, pixel exact including transparent areas:

```dart
final bytes = encodeWebp(
  image,
  options: const WebpEncodeOptions(lossless: true, exact: true),
);
assert(decodeWebp(bytes).rgba.length == image.rgba.length);
```

Preset plus overrides:

```dart
final options = WebpEncodeOptions.preset(WebpPreset.icon, quality: 90)
    .copyWith(method: 6, alphaQuality: 80);
final bytes = encodeWebp(image, options: options);
```

From a PNG via `package:image`:

```dart
import 'package:image/image.dart' as img;
import 'package:tekartik_app_image_webp/image_web.dart';

final png = img.decodePng(File('in.png').readAsBytesSync())!;
final webp = encodeImageWebp(png, options: const WebpEncodeOptions(quality: 80));
File('out.webp').writeAsBytesSync(webp);
```

Verify a result:

```dart
final info = webpInfo(bytes);
assert(info.format == WebpFormat.lossless);
assert(info.hasAlpha == image.hasAlpha);
```

## Edge cases

- Animated WebP cannot be produced.
- `WebpImage.hasAlpha` scans all pixels; an image whose alpha is 255
  everywhere is written without an `ALPH` chunk and without `VP8X`.
- Lossy encoding converts to YUV 4:2:0, so thin colored lines blur; use
  lossless for line art and text.

See [references/options.md](references/options.md) for every option and its
`cwebp` equivalent.
