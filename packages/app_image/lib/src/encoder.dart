import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'package:tekartik_app_image/app_image.dart';

final _defaultEncoding = ImageEncodingJpg(quality: 50);

/// Default to jpg 50
Future<ImageData> imageEncode(
  img.Image image, {
  ImageEncoding? encoding,
}) async {
  encoding ??= ImageEncodingJpg(quality: 50);
  late Uint8List imageBytes;

  Future<void> decodeJpg(ImageEncodingJpg encoding) async {
    imageBytes = Uint8List.fromList(
      img.encodeJpg(image, quality: encoding.quality),
    );
  }

  if (encoding is ImageEncodingJpg) {
    await decodeJpg(encoding);
  } else if (encoding is ImageEncodingPng) {
    imageBytes = Uint8List.fromList(img.encodePng(image));
  } else {
    encoding = _defaultEncoding;
    await decodeJpg(_defaultEncoding);
  }
  return ImageData(
    bytes: imageBytes,
    encoding: encoding,
    width: image.width,
    height: image.height,
  );
}
