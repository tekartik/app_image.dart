import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  group('lossless round trip', () {
    for (final size in [
      [1, 1],
      [3, 5],
      [17, 9],
      [64, 48],
      [97, 61],
    ]) {
      for (final alpha in [false, true]) {
        for (final method in [0, 4, 6]) {
          test('${size[0]}x${size[1]} alpha=$alpha method=$method', () {
            final image = synthImage(size[0], size[1], alpha: alpha);
            final bytes = encodeWebp(
              image,
              options: WebpEncodeOptions(
                lossless: true,
                method: method,
                exact: true,
              ),
            );
            final info = webpInfo(bytes);
            expect(info.format, WebpFormat.lossless);
            expect(info.width, size[0]);
            expect(info.height, size[1]);
            final decoded = decodeWebp(bytes);
            expect(countDiffs(decoded, image), 0);
          });
        }
      }
    }
    test('palette image', () {
      for (final numColors in [1, 2, 3, 4, 7, 16, 17, 100, 256]) {
        final image = paletteImage(40, 30, numColors);
        final bytes = encodeWebp(
          image,
          options: const WebpEncodeOptions(lossless: true),
        );
        expect(
          countDiffs(decodeWebp(bytes), image),
          0,
          reason: '$numColors colors',
        );
      }
    });
    test('transparent pixels are cleaned up unless exact', () {
      final image = synthImage(32, 24, alpha: true);
      final bytes = encodeWebp(
        image,
        options: const WebpEncodeOptions(lossless: true),
      );
      final decoded = decodeWebp(bytes);
      for (var i = 0; i < image.rgba.length; i += 4) {
        expect(decoded.rgba[i + 3], image.rgba[i + 3]);
        if (image.rgba[i + 3] != 0) {
          expect(decoded.rgba[i], image.rgba[i]);
          expect(decoded.rgba[i + 1], image.rgba[i + 1]);
          expect(decoded.rgba[i + 2], image.rgba[i + 2]);
        }
      }
      final exact = encodeWebp(
        image,
        options: const WebpEncodeOptions(lossless: true, exact: true),
      );
      expect(countDiffs(decodeWebp(exact), image), 0);
    });
    test('higher methods compress better or equal', () {
      final image = synthImage(80, 60);
      final s0 = encodeWebp(
        image,
        options: const WebpEncodeOptions(lossless: true, method: 0),
      ).length;
      final s4 = encodeWebp(
        image,
        options: const WebpEncodeOptions(lossless: true, method: 4),
      ).length;
      expect(s4, lessThan(s0));
    });
  });

  group('lossy round trip', () {
    for (final size in [
      [1, 1],
      [3, 5],
      [16, 16],
      [33, 17],
      [97, 61],
    ]) {
      for (final method in [0, 2, 4, 6]) {
        test('${size[0]}x${size[1]} method=$method', () {
          final image = synthImage(size[0], size[1]);
          final bytes = encodeWebp(
            image,
            options: WebpEncodeOptions(quality: 80, method: method),
          );
          final info = webpInfo(bytes);
          expect(info.format, WebpFormat.lossy);
          expect(info.hasAlpha, isFalse);
          expect(info.width, size[0]);
          expect(info.height, size[1]);
          final decoded = decodeWebp(bytes);
          // Synthetic content is noisy; just check it is reasonable.
          expect(psnr(decoded, image), greaterThan(20));
        });
      }
    }
    test('smooth image at high quality', () {
      final image = WebpImage.blank(80, 60);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 80; x++) {
          image.setRgba(x, y, x * 3, y * 4, 128 + (x + y) ~/ 2);
        }
      }
      final bytes = encodeWebp(
        image,
        options: const WebpEncodeOptions(quality: 90),
      );
      expect(psnr(decodeWebp(bytes), image), greaterThan(38));
    });
    test('quality affects size and fidelity', () {
      final image = synthImage(96, 64);
      final low = encodeWebp(
        image,
        options: const WebpEncodeOptions(quality: 10),
      );
      final high = encodeWebp(
        image,
        options: const WebpEncodeOptions(quality: 95),
      );
      expect(low.length, lessThan(high.length));
      expect(
        psnr(decodeWebp(low), image),
        lessThan(psnr(decodeWebp(high), image)),
      );
    });
    test('with alpha', () {
      final image = synthImage(50, 40, alpha: true);
      final bytes = encodeWebp(
        image,
        options: const WebpEncodeOptions(quality: 80),
      );
      final info = webpInfo(bytes);
      expect(info.hasAlpha, isTrue);
      expect(info.isExtended, isTrue);
      final decoded = decodeWebp(bytes);
      // Alpha is lossless by default.
      for (var i = 3; i < image.rgba.length; i += 4) {
        expect(decoded.rgba[i], image.rgba[i]);
      }
      expect(
        psnr(decoded, image, includeAlpha: false, ignoreTransparent: true),
        greaterThan(20),
      );
    });
    test('with lossy alpha', () {
      final image = synthImage(50, 40, alpha: true);
      final bytes = encodeWebp(
        image,
        options: const WebpEncodeOptions(quality: 80, alphaQuality: 50),
      );
      final decoded = decodeWebp(bytes);
      expect(psnr(decoded, image, ignoreTransparent: true), greaterThan(20));
    });
    test('raw alpha', () {
      final image = synthImage(50, 40, alpha: true);
      final bytes = encodeWebp(
        image,
        options: const WebpEncodeOptions(alphaCompression: 0),
      );
      final decoded = decodeWebp(bytes);
      for (var i = 3; i < image.rgba.length; i += 4) {
        expect(decoded.rgba[i], image.rgba[i]);
      }
    });
    test('presets', () {
      final image = synthImage(40, 40);
      for (final preset in WebpPreset.values) {
        final bytes = encodeWebp(
          image,
          options: WebpEncodeOptions.preset(preset, quality: 70),
        );
        expect(
          psnr(decodeWebp(bytes), image),
          greaterThan(20),
          reason: preset.name,
        );
      }
    });
    test('filter and segment options', () {
      final image = synthImage(70, 50);
      for (final options in [
        const WebpEncodeOptions(filterStrength: 0),
        const WebpEncodeOptions(filterType: 0, filterSharpness: 5),
        const WebpEncodeOptions(segments: 1, snsStrength: 0),
        const WebpEncodeOptions(segments: 2, snsStrength: 100, pass: 3),
      ]) {
        final bytes = encodeWebp(image, options: options);
        expect(psnr(decodeWebp(bytes), image), greaterThan(20));
      }
    });
  });

  group('WebpImage', () {
    test('pixel accessors', () {
      final image = WebpImage.blank(2, 2);
      image.setPixel(1, 1, 0x80112233);
      expect(image.getPixel(1, 1), 0x80112233);
      expect(image.getPixel(0, 0), 0xff000000);
      expect(image.hasAlpha, isTrue);
      final argb = image.toArgb();
      expect(argb[3], 0x80112233);
      expect(countDiffs(WebpImage.fromArgb(2, 2, argb), image), 0);
      final rgb = WebpImage.fromRgb(1, 1, [1, 2, 3]);
      expect(rgb.rgba, [1, 2, 3, 255]);
      expect(() => WebpImage(2, 2, Uint8List(3)), throwsArgumentError);
    });
  });
}
