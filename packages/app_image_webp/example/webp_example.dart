// ignore_for_file: avoid_print

import 'dart:io';

import 'package:tekartik_app_image_webp/webp.dart';

/// Creates a small synthetic image, encodes it as lossy and lossless WebP,
/// decodes the results and prints some statistics.
void main() {
  // Build a 64x48 image with a gradient and a transparent band.
  final image = WebpImage.blank(64, 48);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final alpha = x < 16 ? 0 : 255;
      image.setRgba(x, y, x * 4, y * 5, 128, alpha);
    }
  }

  // Lossy (VP8) with the default quality (75) and method (4).
  final lossy = encodeWebp(image);
  final decodedLossy = decodeWebp(lossy);
  print('lossy: ${lossy.length} bytes, ${webpInfo(lossy)}');
  print(
    '  decoded ${decodedLossy.width}x${decodedLossy.height}, '
    'pixel(20,10)=0x${decodedLossy.getPixel(20, 10).toRadixString(16)}',
  );

  // Lossless (VP8L): the decoded pixels are identical to the source.
  final lossless = encodeWebp(
    image,
    options: const WebpEncodeOptions(lossless: true, exact: true),
  );
  final decodedLossless = decodeWebp(lossless);
  var identical = true;
  for (var i = 0; i < image.rgba.length; i++) {
    if (image.rgba[i] != decodedLossless.rgba[i]) {
      identical = false;
      break;
    }
  }
  print(
    'lossless: ${lossless.length} bytes, ${webpInfo(lossless)}, '
    'identical=$identical',
  );

  // Tuned lossy encoding: better quality, slower method, lossy alpha.
  final tuned = encodeWebp(
    image,
    options: const WebpEncodeOptions(quality: 90, method: 6, alphaQuality: 80),
  );
  print('tuned lossy: ${tuned.length} bytes');

  // Write the files next to this script when run from the package root.
  File('example_lossy.webp').writeAsBytesSync(lossy);
  File('example_lossless.webp').writeAsBytesSync(lossless);
  print('written example_lossy.webp and example_lossless.webp');
}
