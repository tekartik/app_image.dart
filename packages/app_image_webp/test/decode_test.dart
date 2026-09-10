@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  group('webpInfo', () {
    test('lossy', () {
      final info = webpInfo(readData('gradient_48x32_lossy.webp'));
      expect(info.width, 48);
      expect(info.height, 32);
      expect(info.format, WebpFormat.lossy);
      expect(info.isLossless, isFalse);
      expect(info.hasAlpha, isFalse);
      expect(info.hasAnimation, isFalse);
      expect(info.isExtended, isFalse);
    });
    test('lossless', () {
      final info = webpInfo(readData('gradient_48x32_lossless.webp'));
      expect(info.width, 48);
      expect(info.height, 32);
      expect(info.format, WebpFormat.lossless);
      expect(info.isLossless, isTrue);
      expect(info.hasAlpha, isFalse);
    });
    test('lossy with alpha (VP8X + ALPH)', () {
      final info = webpInfo(readData('gradient_alpha_48x32_lossy.webp'));
      expect(info.width, 48);
      expect(info.height, 32);
      expect(info.format, WebpFormat.lossy);
      expect(info.hasAlpha, isTrue);
      expect(info.isExtended, isTrue);
    });
    test('lossless with alpha', () {
      final info = webpInfo(readData('gradient_alpha_48x32_lossless.webp'));
      expect(info.format, WebpFormat.lossless);
      expect(info.hasAlpha, isTrue);
    });
    test('1x1', () {
      expect(webpInfo(readData('pixel_1x1_lossy.webp')).width, 1);
      expect(webpInfo(readData('pixel_1x1_lossless.webp')).height, 1);
    });
    test('invalid data', () {
      expect(() => webpInfo(Uint8List(0)), throwsA(isA<WebpFormatException>()));
      expect(
        () => webpInfo(Uint8List.fromList(List.filled(20, 0))),
        throwsA(isA<WebpFormatException>()),
      );
      expect(
        () => webpInfo(
          Uint8List.fromList('RIFF\x10\x00\x00\x00WEBPXXXX'.codeUnits),
        ),
        throwsA(isA<WebpFormatException>()),
      );
    });
  });

  group('decodeWebp matches dwebp output', () {
    // The `*_ref.png` files were produced by libwebp's `dwebp` from the
    // corresponding `.webp` files; decoding must be bit-exact.
    for (final name in [
      'gradient_48x32_lossy.webp',
      'gradient_48x32_lossless.webp',
      'gradient_alpha_48x32_lossy.webp',
      'gradient_alpha_48x32_lossy_aq50.webp',
      'gradient_alpha_48x32_lossy_rawalpha.webp',
      'gradient_alpha_48x32_lossless.webp',
      'gradient_alpha_48x32_lossless_meta.webp',
      'shapes_40x30_lossy.webp',
      'shapes_40x30_lossy_nofilter.webp',
      'shapes_40x30_lossy_simple.webp',
      'shapes_40x30_lossless.webp',
      'pixel_1x1_lossy.webp',
      'pixel_1x1_lossless.webp',
    ]) {
      test(name, () {
        final bytes = readData(name);
        final image = decodeWebp(bytes);
        final ref = readPng(name.replaceAll('.webp', '_ref.png'));
        expect(image.width, ref.width);
        expect(image.height, ref.height);
        expect(countDiffs(image, ref), 0, reason: 'pixels differ from dwebp');
      });
    }
  });

  group('decodeWebp lossless matches the image package', () {
    for (final name in [
      'gradient_48x32_lossless.webp',
      'gradient_alpha_48x32_lossless.webp',
      'shapes_40x30_lossless.webp',
    ]) {
      test(name, () {
        final bytes = readData(name);
        expect(countDiffs(decodeWebp(bytes), referenceDecode(bytes)), 0);
      });
    }
  });

  group('decodeWebp lossless is exact', () {
    test('gradient', () {
      final image = decodeWebp(readData('gradient_48x32_lossless.webp'));
      final png = readPng('gradient_48x32.png');
      expect(countDiffs(image, png), 0);
    });
    test('gradient with alpha', () {
      final image = decodeWebp(readData('gradient_alpha_48x32_lossless.webp'));
      final png = readPng('gradient_alpha_48x32.png');
      expect(countDiffs(image, png), 0);
    });
    test('shapes', () {
      final image = decodeWebp(readData('shapes_40x30_lossless.webp'));
      final png = readPng('shapes_40x30.png');
      expect(countDiffs(image, png), 0);
    });
  });

  group('decodeWebp lossy is close to the source', () {
    test('gradient', () {
      final image = decodeWebp(readData('gradient_48x32_lossy.webp'));
      expect(psnr(image, readPng('gradient_48x32.png')), greaterThan(30));
    });
    test('alpha plane is exact when alpha_q is 100', () {
      final image = decodeWebp(readData('gradient_alpha_48x32_lossy.webp'));
      final png = readPng('gradient_alpha_48x32.png');
      for (var i = 3; i < image.rgba.length; i += 4) {
        expect(image.rgba[i], png.rgba[i]);
      }
    });
  });

  group('errors', () {
    test('truncated lossy', () {
      final bytes = readData('gradient_48x32_lossy.webp');
      expect(
        () => decodeWebp(Uint8List.sublistView(bytes, 0, 40)),
        throwsA(isA<WebpFormatException>()),
      );
    });
    test('truncated lossless', () {
      final bytes = readData('gradient_48x32_lossless.webp');
      expect(
        () => decodeWebp(Uint8List.sublistView(bytes, 0, 60)),
        throwsA(isA<WebpFormatException>()),
      );
    });
    test('animated is rejected', () {
      // Minimal VP8X with the animation flag.
      final b = Uint8List.fromList([
        ...'RIFF'.codeUnits, 30, 0, 0, 0, ...'WEBP'.codeUnits, //
        ...'VP8X'.codeUnits, 10, 0, 0, 0, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
      ]);
      expect(webpInfo(b).hasAnimation, isTrue);
      expect(() => decodeWebp(b), throwsA(isA<WebpFormatException>()));
    });
  });
}
