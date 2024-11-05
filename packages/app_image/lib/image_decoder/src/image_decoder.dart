import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/src/image_bytes_utils.dart';

/// Get image encoding from bytes
ImageEncoding getImageEncodingFromBytes(Uint8List bytes) {
  late ImageEncoding encoding;
  if (isJpg(bytes)) {
    encoding = ImageEncodingJpg(quality: imageEncodingJpgQualityUnknown);
  } else if (isPng(bytes)) {
    encoding = const ImageEncodingPng();
  } else if (isWebp(bytes)) {
    encoding = const ImageEncodingWebp();
  } else {
    throw UnsupportedError('Unsupported image type');
  }
  return encoding;
}

/// Get image meta from bytes
Future<ImageMeta> getImageMetaFromBytes(Uint8List bytes) async {
  var encoding = getImageEncodingFromBytes(bytes);
  var image = decodeImage(bytes)!;
  var width = image.width;
  var height = image.height;
  return ImageMeta(encoding: encoding, width: width, height: height);
}
