// ignore_for_file: avoid_print

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:tekartik_app_image_webp/webp.dart';

/// Converts between WebP and PNG/JPEG files.
///
/// Usage:
/// ```
/// dart run example/webp_convert.dart input.png output.webp [-q 80] [-m 4] [-lossless]
/// dart run example/webp_convert.dart input.webp output.png
/// ```
///
/// The `image` package is only used here to read and write PNG/JPEG.
void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: webp_convert <input> <output> [-q quality] [-m method] [-lossless]',
    );
    exit(1);
  }
  final input = args[0];
  final output = args[1];
  var quality = 75.0;
  var method = 4;
  var lossless = false;
  for (var i = 2; i < args.length; i++) {
    switch (args[i]) {
      case '-q':
        quality = double.parse(args[++i]);
      case '-m':
        method = int.parse(args[++i]);
      case '-lossless':
        lossless = true;
    }
  }
  final inputBytes = File(input).readAsBytesSync();
  if (output.toLowerCase().endsWith('.webp')) {
    final decoded = input.toLowerCase().endsWith('.webp')
        ? decodeWebp(inputBytes)
        : _fromImage(img.decodeImage(inputBytes)!);
    final options = WebpEncodeOptions(
      quality: quality,
      method: method,
      lossless: lossless,
    );
    final bytes = encodeWebp(decoded, options: options);
    File(output).writeAsBytesSync(bytes);
    print('$output: ${bytes.length} bytes (${webpInfo(bytes)})');
  } else {
    final decoded = decodeWebp(inputBytes);
    final im = img.Image.fromBytes(
      width: decoded.width,
      height: decoded.height,
      bytes: decoded.rgba.buffer,
      numChannels: 4,
    );
    final bytes = output.toLowerCase().endsWith('.png')
        ? img.encodePng(im)
        : img.encodeJpg(im, quality: quality.round());
    File(output).writeAsBytesSync(bytes);
    print('$output: ${decoded.width}x${decoded.height}');
  }
}

WebpImage _fromImage(img.Image im) {
  final image = WebpImage.blank(im.width, im.height);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      image.setRgba(
        x,
        y,
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
        im.hasAlpha ? p.a.toInt() : 255,
      );
    }
  }
  return image;
}
