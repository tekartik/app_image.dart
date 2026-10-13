@TestOn('vm')
library;

import 'package:tekartik_app_image_webp/webp.dart';
import 'package:test/test.dart';

import 'test_common.dart';

/// Lossy options and the matching cwebp arguments.
const _lossyCases = <String, WebpEncodeOptions>{
  // cwebp -q 75 -m 0
  'q75 m0': WebpEncodeOptions(method: 0),
  // cwebp -q 75 -m 1
  'q75 m1': WebpEncodeOptions(method: 1),
  // cwebp -q 40 -sns 0 -m 2
  'q40 sns0 m2': WebpEncodeOptions(quality: 40, snsStrength: 0, method: 2),
  // cwebp -q 90 -m 2 -pass 3
  'q90 m2 pass3': WebpEncodeOptions(quality: 90, method: 2, pass: 3),
  // cwebp -q 75 -m 4
  'q75 m4': WebpEncodeOptions(),
  // cwebp -q 30 -m 5 -pass 3
  'q30 m5 pass3': WebpEncodeOptions(quality: 30, method: 5, pass: 3),
  // cwebp -q 90 -m 6
  'q90 m6': WebpEncodeOptions(quality: 90, method: 6),
};

/// CRC-32 of the RGBA pixels decoded by `dwebp -pam` from the `cwebp`
/// (libwebp 1.5.0) encoding of `data/<image>.png` with each case.
const _dwebpPixelsCrc = <(String, String), int>{
  ('mix_alpha_15x15', 'q75 m0'): 0x68b85a24,
  ('mix_alpha_15x15', 'q75 m1'): 0x399667d0,
  ('mix_alpha_15x15', 'q40 sns0 m2'): 0xe39fcc7b,
  ('mix_alpha_15x15', 'q90 m2 pass3'): 0x844eaf68,
  ('mix_alpha_15x15', 'q75 m4'): 0xdbb21f5a,
  ('mix_alpha_15x15', 'q30 m5 pass3'): 0x2e62fcc7,
  ('mix_alpha_15x15', 'q90 m6'): 0x9e9e54f4,
  ('mix_31x9', 'q75 m0'): 0xbdf711f3,
  ('mix_31x9', 'q75 m1'): 0x7d911619,
  ('mix_31x9', 'q40 sns0 m2'): 0xc51608f9,
  ('mix_31x9', 'q90 m2 pass3'): 0x4228d76f,
  ('mix_31x9', 'q75 m4'): 0xb40dc3f2,
  ('mix_31x9', 'q30 m5 pass3'): 0x2e845b71,
  ('mix_31x9', 'q90 m6'): 0xf6d7f98a,
};

void main() {
  group('libwebp reference', () {
    // The encoder takes the same decisions as libwebp: the decoded pixels
    // are identical (the bytes may differ in the entropy coding only).
    for (final MapEntry(key: (name, key), value: crc)
        in _dwebpPixelsCrc.entries) {
      test('lossy $name $key pixels', () {
        final image = readPng('$name.png');
        final bytes = encodeWebp(image, options: _lossyCases[key]!);
        expect(crc32(decodeWebp(bytes).rgba), crc);
      });
    }

    // More passes never make the file bigger (VP8EncTokenLoop).
    test('lossy pass sizes', () {
      final image = readPng('mix_31x9.png');
      for (final method in [4, 6]) {
        int size(int pass) => encodeWebp(
          image,
          options: WebpEncodeOptions(quality: 90, method: method, pass: pass),
        ).length;
        final size1 = size(1);
        expect(size(2), lessThanOrEqualTo(size1), reason: 'm$method pass 2');
        expect(size(6), lessThanOrEqualTo(size1), reason: 'm$method pass 6');
      }
    });

    // Same bytes as `cwebp -lossless -q 0 -m 0`: a palette image with
    // transparent pixels (sorted palette, transparent black last) and a
    // predictor image (no subsampling search at low effort).
    for (final name in ['gradient_alpha_15x15', 'gradient_17x33']) {
      test('lossless m0 $name bytes', () {
        final image = readPng('$name.png');
        final bytes = encodeWebp(
          image,
          options: const WebpEncodeOptions(
            lossless: true,
            quality: 0,
            method: 0,
          ),
        );
        expect(bytes, readData('${name}_lossless_m0.webp'));
      });
    }
  });
}
