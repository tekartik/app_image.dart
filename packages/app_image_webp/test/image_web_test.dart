@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tekartik_app_image_webp/image_web.dart';
import 'package:tekartik_app_image_webp/webp.dart' show webpInfo, WebpFormat;
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  group('conversion', () {
    test('imageToWebpImage / webpImageToImage round trip', () {
      final source = synthImage(23, 11, alpha: true);
      final image = webpImageToImage(source);
      expect(image.width, 23);
      expect(image.height, 11);
      expect(image.numChannels, 4);
      final back = imageToWebpImage(image);
      expect(countDiffs(back, source), 0);
      // Buffers are not shared.
      image.setPixelRgba(0, 0, 1, 2, 3, 4);
      expect(back.rgba.sublist(0, 4), isNot([1, 2, 3, 4]));
    });
    test('rgb image (3 channels) becomes opaque', () {
      final image = img.Image(width: 5, height: 4);
      image.setPixelRgb(1, 2, 10, 20, 30);
      final webp = imageToWebpImage(image);
      expect(webp.hasAlpha, isFalse);
      expect(webp.getPixel(1, 2), 0xff0a141e);
    });
    test('palette and 16-bit images are converted', () {
      final image = img.Image(
        width: 4,
        height: 4,
        numChannels: 3,
        format: img.Format.uint16,
      );
      image.setPixelRgb(3, 3, 65535, 0, 32768);
      final webp = imageToWebpImage(image);
      expect(webp.getPixel(3, 3) & 0xffffff, 0xff0080);
      final paletted = img.Image(
        width: 3,
        height: 2,
        withPalette: true,
        numChannels: 3,
      );
      paletted.palette!.setRgb(1, 200, 100, 50);
      paletted.setPixelIndex(2, 1, 1);
      final webp2 = imageToWebpImage(paletted);
      expect(webp2.getPixel(2, 1), 0xffc86432);
    });
  });

  group('encodeImageWebp is decodable by the image package', () {
    for (final lossless in [true, false]) {
      for (final alpha in [false, true]) {
        test('lossless=$lossless alpha=$alpha', () {
          final source = webpImageToImage(synthImage(50, 37, alpha: alpha));
          final bytes = encodeImageWebp(
            source,
            options: WebpEncodeOptions(
              lossless: lossless,
              quality: 85,
              exact: true,
            ),
          );
          expect(
            webpInfo(bytes).format,
            lossless ? WebpFormat.lossless : WebpFormat.lossy,
          );
          final decoded = img.decodeWebP(bytes);
          expect(decoded, isNotNull);
          expect(decoded!.width, 50);
          expect(decoded.height, 37);
          final a = imageToWebpImage(source);
          final b = imageToWebpImage(decoded);
          if (lossless) {
            expect(countDiffs(a, b), 0);
          } else {
            expect(psnr(b, a), greaterThan(20));
          }
        });
      }
    }
    test('image package generic decoder detects the format', () {
      final bytes = encodeImageWebp(
        webpImageToImage(paletteImage(30, 20, 5)),
        options: const WebpEncodeOptions(lossless: true),
      );
      final decoded = img.decodeImage(bytes);
      expect(decoded, isNotNull);
      expect(img.findDecoderForData(bytes), isA<img.WebPDecoder>());
      expect(
        countDiffs(imageToWebpImage(decoded!), paletteImage(30, 20, 5)),
        0,
      );
    });
  });

  group('decodeImageWebp', () {
    test('decodes data files like the image package does', () {
      for (final name in [
        'gradient_alpha_48x32_lossless.webp',
        'shapes_40x30_lossless.webp',
      ]) {
        final bytes = readData(name);
        final image = decodeImageWebp(bytes)!;
        expect(image.width, webpInfo(bytes).width);
        expect(countDiffs(imageToWebpImage(image), referenceDecode(bytes)), 0);
      }
    });
    test('matches dwebp for lossy files', () {
      final bytes = readData('gradient_alpha_48x32_lossy.webp');
      final image = decodeImageWebp(bytes)!;
      expect(
        countDiffs(
          imageToWebpImage(image),
          readPng('gradient_alpha_48x32_lossy_ref.png'),
        ),
        0,
      );
    });
    test('returns null on invalid data', () {
      expect(decodeImageWebp(Uint8List(0)), isNull);
      expect(
        decodeImageWebp(
          Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]),
        ),
        isNull,
      );
    });
  });
}
