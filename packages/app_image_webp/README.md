# tekartik_app_image_webp

Pure Dart WebP encoder and decoder, ported from
[libwebp](https://github.com/webmproject/libwebp) (with
[deepteams/webp](https://github.com/deepteams/webp) as a secondary reference).
No native code, no `dart:ffi`; works on the VM, Flutter and the web.

## Features

Decoding (bit-exact with libwebp's `dwebp`):

- Lossy `VP8 ` bitstreams (all intra modes, segments, both loop filters,
  multiple token partitions, fancy chroma upsampling).
- Lossless `VP8L` bitstreams (all transforms, color cache, meta Huffman codes).
- Alpha planes (`ALPH` chunk, raw or lossless-compressed, all prediction
  filters, quantized levels) and the extended `VP8X` container.
- Header inspection without decoding (`webpInfo`).

Encoding:

- Lossy `VP8` encoder: segment analysis, rate-distortion mode decision,
  trellis quantization (methods 5 and 6), token probability optimization,
  loop-filter tuning, error diffusion, gamma-correct chroma subsampling,
  transparent area cleanup. Output sizes are within a few percent of `cwebp`
  at the same settings.
- Lossless `VP8L` encoder: palette / subtract-green / predictor / cross-color
  transforms, LZ77 backward references with color cache, histogram
  clustering, canonical Huffman codes.
- Alpha plane encoder (lossless by default, optional level quantization,
  prediction filters).

Not supported: animation (`ANIM`/`ANMF` files are detected and rejected).

## Getting started

In `pubspec.yaml`:

```yaml
dependencies:
  tekartik_app_image_webp:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_image_webp
      ref: dart3a
    version: '>=0.1.0'
```

## Usage

```dart
import 'dart:io';
import 'package:tekartik_app_image_webp/webp.dart';

void main() {
  final bytes = File('photo.webp').readAsBytesSync();

  // Header only.
  final info = webpInfo(bytes);
  print('${info.width}x${info.height} lossless=${info.isLossless} alpha=${info.hasAlpha}');

  // Full decode: RGBA bytes, 4 per pixel, straight alpha.
  final image = decodeWebp(bytes);
  final argb = image.getPixel(10, 10); // 0xAARRGGBB

  // Encode (lossy, quality 80).
  final lossy = encodeWebp(image, options: WebpEncodeOptions(quality: 80));

  // Encode (lossless, keep RGB of transparent pixels).
  final lossless = encodeWebp(
    image,
    options: WebpEncodeOptions(lossless: true, exact: true),
  );
  File('out.webp').writeAsBytesSync(lossless);
}
```

`WebpImage` is a simple container (`width`, `height`, `rgba`) with helpers
(`blank`, `fromRgb`, `fromArgb`, `toArgb`, `getPixel`, `setPixel`, `setRgba`).

`WebpEncodeOptions` mirrors the main `cwebp` settings: `quality`, `method`
(0 fast .. 6 best), `lossless`, `exact`, `alphaQuality`, `alphaCompression`,
`alphaFiltering`, `snsStrength`, `filterStrength`, `filterSharpness`,
`filterType`, `segments`, `pass`. `WebpEncodeOptions.preset(WebpPreset.photo)`
gives the libwebp presets.

### With the `image` package

`package:tekartik_app_image_webp/image_web.dart` bridges to
[`package:image`](https://pub.dev/packages/image) images:

```dart
import 'package:image/image.dart' as img;
import 'package:tekartik_app_image_webp/image_web.dart';

final img.Image? image = decodeImageWebp(bytes); // null if not a valid WebP
final Uint8List webp = encodeImageWebp(image!, options: WebpEncodeOptions(quality: 80));
// Lower level: imageToWebpImage(image) / webpImageToImage(webpImage).
```

See [example/webp_example.dart](example/webp_example.dart) and
[example/webp_convert.dart](example/webp_convert.dart) (a small PNG/JPEG
converter using the `image` package for the other formats).

## AI agent skills

The package ships [agent skills](https://dart.dev/tools/pub/package-skills)
in `skills/` (decoding, encoding, and codec development). In a project that
depends on this package, run `dart pub global activate skills` then
`dart pub global run skills get` to install them into `.agents/skills/`.

## Notes

- Decoding is verified bit-exact against `dwebp` on lossy, lossless and
  alpha files with various encoder settings.
- The encoder is a port of libwebp's algorithms; it does not aim at
  producing byte-identical files, but the compression ratio and quality are
  equivalent (identical at method 0..2, within ~1-3% at higher methods).
- Performance: roughly 5-10x slower than the native libwebp for encoding,
  2-3x for decoding (VM, JIT).
- All integer arithmetic is written to be safe when compiled to JavaScript
  (32-bit bit operations); the VM and dart2js produce identical files.

## License

The Dart code is released under the repository license. The algorithms and
constant tables are derived from libwebp (BSD-style license, Copyright Google
Inc.) and deepteams/webp (MIT).
