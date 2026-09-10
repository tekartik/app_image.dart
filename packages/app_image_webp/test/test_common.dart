import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tekartik_app_image_webp/webp.dart';

/// Directory of the test data files.
String get dataDir => p.join(Directory.current.path, 'data');

/// Reads a test data file.
Uint8List readData(String name) =>
    File(p.join(dataDir, name)).readAsBytesSync();

/// Decodes a PNG data file into a [WebpImage] using the `image` package.
WebpImage readPng(String name) {
  final im = img.decodePng(readData(name))!;
  return imageToWebpImage(im);
}

/// Converts an `image` package image to a [WebpImage].
WebpImage imageToWebpImage(img.Image im) {
  final w = im.width;
  final h = im.height;
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = im.getPixel(x, y);
      final i = (y * w + x) * 4;
      rgba[i] = px.r.toInt();
      rgba[i + 1] = px.g.toInt();
      rgba[i + 2] = px.b.toInt();
      rgba[i + 3] = im.hasAlpha ? px.a.toInt() : 255;
    }
  }
  return WebpImage(w, h, rgba);
}

/// Decodes WebP [bytes] with the `image` package (reference decoder).
WebpImage referenceDecode(Uint8List bytes) =>
    imageToWebpImage(img.decodeWebP(bytes)!);

/// PSNR in dB between two RGBA images (99 when identical).
///
/// With [ignoreTransparent], the color channels of pixels that are fully
/// transparent in [b] are skipped (encoders may discard them).
double psnr(
  WebpImage a,
  WebpImage b, {
  bool includeAlpha = true,
  bool ignoreTransparent = false,
}) {
  var sse = 0;
  var n = 0;
  for (var i = 0; i < a.rgba.length; i++) {
    if (!includeAlpha && i % 4 == 3) continue;
    if (ignoreTransparent && i % 4 != 3 && b.rgba[i - i % 4 + 3] == 0) {
      continue;
    }
    final d = a.rgba[i] - b.rgba[i];
    sse += d * d;
    n++;
  }
  if (sse == 0) return 99;
  return 10 * math.log(255.0 * 255.0 * n / sse) / math.ln10;
}

/// Number of differing bytes between two images.
int countDiffs(WebpImage a, WebpImage b) {
  var n = 0;
  for (var i = 0; i < a.rgba.length; i++) {
    if (a.rgba[i] != b.rgba[i]) n++;
  }
  return n;
}

/// Deterministic pseudo-random generator (JavaScript safe).
class TestRandom {
  int _s;

  /// Creates a generator with [seed].
  TestRandom(int seed) : _s = seed & 0xffff;

  /// Next value in [0, max).
  int next(int max) {
    _s = (_s * 75 + 74) % 65537;
    return _s % max;
  }
}

/// Builds a synthetic image: smooth gradients, noise, shapes and optional
/// transparency, deterministic for the given [seed].
WebpImage synthImage(
  int width,
  int height, {
  int seed = 1,
  bool alpha = false,
}) {
  final image = WebpImage.blank(width, height);
  final rnd = TestRandom(seed);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var r = (x * 255 ~/ math.max(1, width - 1) + rnd.next(16)) & 0xff;
      var g = (y * 255 ~/ math.max(1, height - 1)) & 0xff;
      var b = ((x * y) >> 3) & 0xff;
      if ((x ~/ 8 + y ~/ 8) % 3 == 0) {
        r = 200;
        g = 30;
        b = 30;
      }
      final a = !alpha
          ? 255
          : (x < width ~/ 3)
          ? 0
          : (x < 2 * width ~/ 3)
          ? 128
          : 255;
      image.setRgba(x, y, r, g, b, a);
    }
  }
  return image;
}

/// Builds an image with few colors (palette-like content).
WebpImage paletteImage(int width, int height, int numColors, {int seed = 3}) {
  final image = WebpImage.blank(width, height);
  final rnd = TestRandom(seed);
  final colors = List.generate(
    numColors,
    (i) => [rnd.next(256), rnd.next(256), rnd.next(256), 255],
  );
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final c = colors[((x ~/ 5) + (y ~/ 7)) % numColors];
      image.setRgba(x, y, c[0], c[1], c[2], c[3]);
    }
  }
  return image;
}
