import 'package:image/image.dart' as img;

import 'package:tekartik_app_image/app_image.dart';

import 'image_encode.dart';

/// Default to jpg 50
///
/// Throws an [UnsupportedError] for an encoding other than jpg, png or webp.
Future<ImageData> imageEncode(
  img.Image image, {
  ImageEncoding? encoding,
}) async {
  encoding ??= ImageEncodingJpg(quality: 50);
  return ImageData(
    bytes: imageEncodeBytes(image, encoding),
    encoding: encoding,
    width: image.width,
    height: image.height,
  );
}
