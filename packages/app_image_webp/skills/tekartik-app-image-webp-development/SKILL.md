---
name: tekartik-app-image-webp-development
description: Work on the internals of tekartik_app_image_webp, the pure Dart libwebp port (VP8/VP8L codec sources under lib/src, bit-exact verification against dwebp/cwebp, test data, dart2js integer pitfalls). Use when modifying, debugging or extending the WebP codec itself rather than merely using it, or when a WebP file decodes differently from libwebp.
license: BSD-2-Clause
compatibility: cwebp, dwebp and webpinfo (libwebp tools) are needed for the verification scripts; node is optional for dart2js parity checks.
metadata:
  package: tekartik_app_image_webp
  author: tekartik
---

# Developing the tekartik_app_image_webp codec

The package is a line-by-line port of libwebp (`src/dec`, `src/enc`,
`src/dsp`, `src/utils`). Keep the structure parallel to libwebp so that
fixes can be cross-checked against the C code.

## Layout

| Path | Port of |
| --- | --- |
| `lib/src/riff.dart` | RIFF container parse/build |
| `lib/src/decoder.dart`, `lib/src/encoder.dart` | public entry points |
| `lib/src/vp8/bool_reader.dart`, `bool_writer.dart` | boolean coder |
| `lib/src/vp8/tables.dart` | generated constant tables (probas, quant, costs) |
| `lib/src/vp8/dsp.dart`, `enc_dsp.dart` | transforms, predictions, filters |
| `lib/src/vp8/vp8_decoder.dart`, `vp8_encoder.dart` | lossy codec |
| `lib/src/vp8/yuv.dart`, `alpha.dart` | color conversion, `ALPH` chunk |
| `lib/src/vp8l/*` | lossless codec (bit I/O, Huffman, histograms, LZ77, transforms) |
| `lib/src/int_utils*.dart` | platform-dependent `sar()` (arithmetic shift) |

## Rules

- Decoding must stay bit-exact with `dwebp`. After any decoder change run
  the test suite (`dart test`), whose `data/*_ref.png` files were produced by
  `dwebp`, and spot-check new encoder settings with `cwebp` + `dwebp -pam`.
- Encoder output must decode with `dwebp` without error; compare size and
  PSNR against `cwebp` at the same `-q`/`-m`.
- Keep all integer code JavaScript safe:
  - never apply `>>` to a possibly negative value; use `sar(v, n)` from
    `int_utils.dart` (dart2js returns unsigned results for `>>`);
  - never `<<` into more than 32 bits; multiply instead (`log2Scale`);
  - keep literals below 2^53; use `mul32()` for 32-bit hash multiplications;
  - prefer `>>>` when extracting bits from values that may have bit 31 set.
- Do not add native dependencies; the package must run on VM, Flutter and web.
- Public members need `///` docs (`public_member_api_docs` lint is on).
- Run `dart run tool/run_ci.dart` (format, analyze, tests) before committing.

## Verification recipes

Decode parity with dwebp for a file:

```bash
dwebp in.webp -pam -o ref.pam   # RGBA after the ENDHDR line
dart run example/webp_convert.dart in.webp out.png
```

Encode and check with libwebp tools:

```bash
dart run example/webp_convert.dart in.png out.webp -q 75 -m 4
dwebp out.webp -o decoded.png && webpinfo out.webp
cwebp -q 75 -m 4 in.png -o ref.webp   # compare sizes
```

dart2js parity (VM vs node): compile a small script that encodes a synthetic
image and decodes the `data/` files, print CRCs, run it with `dart run` and
with `node` on the `dart compile js` output, and diff the outputs.

## Debugging tips

- Lossy mismatches usually come from context handling: the left non-zero
  context is a single shared slot (`_mbNz[0]`), top contexts are per column.
- Lossless mismatches: check transform order (inverse transforms run in
  reverse), color cache insertion (every decoded pixel is inserted) and
  `planeCodeToDistance`.
- Tables in `lib/src/vp8/tables.dart` are generated from libwebp sources;
  regenerate rather than hand-edit.
