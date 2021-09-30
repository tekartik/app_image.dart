import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';
import 'package:tekartik_common_utils/byte_utils.dart';

import 'pick_crop_image.dart';

// Raw implementation
Uint8List resizeToPngSync(Uint8List bytes, int width, int height) {
  var image = decodeImage(bytes)!;

  // Resize the image to a 120x? thumbnail (maintaining the aspect ratio).
  image = copyResize(image, width: width, height: height);

  // Save the thumbnail as a PNG.
  return asUint8List(encodePng(image));
}

Future<Uint8List> imageResizeTo(
  Uint8List bytes, {
  required PickCropConvertImageOptions options,
}) async {
  var image = decodeImage(bytes)!;

  // Resize the image to a 120x? thumbnail (maintaining the aspect ratio).
  image = copyResize(image, width: options.width, height: options.height);

  var encoding = options.encoding;
  if (encoding is ImageEncodingJpg) {
    return asUint8List(encodeJpg(image, quality: encoding.quality));
  } else {
    return asUint8List(encodePng(image));
  }
}
