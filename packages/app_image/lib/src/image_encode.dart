import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tekartik_app_image/app_image.dart';
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
