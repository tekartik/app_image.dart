import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/src/image_bytes_utils.dart';
import 'package:tekartik_app_image_webp/image_web.dart';
import 'package:tekartik_common_utils/byte_utils.dart';

/// Encodes [image] with [encoding] (jpg, png or webp).
///
/// Throws an [UnsupportedError] for any other encoding, the bytes always
/// match the encoding mime type.
Uint8List imageEncodeBytes(img.Image image, ImageEncoding encoding) {
  if (encoding is ImageEncodingJpg) {
    return asUint8List(img.encodeJpg(image, quality: encoding.quality));
  } else if (encoding is ImageEncodingPng) {
    return asUint8List(img.encodePng(image));
  } else if (encoding is ImageEncodingWebp) {
    var quality = encoding.quality == imageEncodingWebpQualityUnknown
        ? imageEncodingWebpQualityDefault
        : encoding.quality;
    return encodeImageWebp(
      image,
      options: WebpEncodeOptions(quality: quality.toDouble()),
    );
  }
  throw UnsupportedError('Unsupported image encoding $encoding');
}

/// Decodes image file [bytes]: WebP with the `tekartik_app_image_webp`
/// decoder, anything else (png, jpg, gif...) with `package:image`.
///
/// Throws a [FormatException] when [bytes] is not a supported image.
img.Image imageDecodeBytes(Uint8List bytes) {
  img.Image? image;
  try {
    image = isWebp(bytes) ? decodeImageWebp(bytes) : img.decodeImage(bytes);
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('invalid image ($e)');
  }
  if (image == null) {
    throw const FormatException('unsupported image format');
  }
  return image;
}
