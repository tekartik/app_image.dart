/// Helpers bridging this WebP codec and the `image` package
/// (`package:image/image.dart`).
///
/// ```dart
/// import 'package:image/image.dart' as img;
/// import 'package:tekartik_app_image_webp/image_web.dart';
///
/// final img.Image? image = decodeImageWebp(bytes);
/// final webpBytes = encodeImageWebp(image!, options: WebpEncodeOptions(quality: 80));
/// ```
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'src/decoder.dart';
import 'src/encoder.dart';
import 'src/webp_image.dart';

export 'src/encoder.dart' show WebpEncodeOptions, WebpPreset;
export 'src/webp_image.dart' show WebpFormatException, WebpImage;

/// Converts an `image` package [image] to a [WebpImage].
///
/// Any pixel format (palette, 16-bit, float, 1 to 4 channels) is converted to
/// 8-bit RGBA; missing alpha becomes opaque. For animated images only the
/// current frame is used. The returned pixels are a copy.
WebpImage imageToWebpImage(img.Image image) {
  var src = image;
  if (src.format != img.Format.uint8 ||
      src.numChannels != 4 ||
      src.hasPalette) {
    src = src.convert(
      format: img.Format.uint8,
      numChannels: 4,
      noAnimation: true,
    );
  }
  final rgba = src.getBytes(order: img.ChannelOrder.rgba);
  // Copy so the result never shares memory with the source image.
  return WebpImage(image.width, image.height, Uint8List.fromList(rgba));
}

/// Converts a [WebpImage] to an `image` package image (8-bit RGBA).
///
/// The pixel buffer is copied so the two images do not share memory.
img.Image webpImageToImage(WebpImage image) {
  return img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: Uint8List.fromList(image.rgba).buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

/// Decodes WebP [bytes] into an `image` package image.
///
/// Returns null if [bytes] is not a valid still WebP file (animated files
/// are not supported), mirroring the `image` package decoders' behavior.
img.Image? decodeImageWebp(Uint8List bytes) {
  try {
    return webpImageToImage(decodeWebp(bytes));
  } on WebpFormatException {
    return null;
  }
}

/// Encodes an `image` package [image] as a WebP file.
///
/// [options] selects lossy (default) or lossless coding, quality, method and
/// alpha handling; see [WebpEncodeOptions].
Uint8List encodeImageWebp(
  img.Image image, {
  WebpEncodeOptions options = const WebpEncodeOptions(),
}) {
  return encodeWebp(imageToWebpImage(image), options: options);
}
