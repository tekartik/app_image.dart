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

@Deprecated('Old')
Future<ImageData> imageResizeTo(
  Uint8List bytes, {
  required PickCropConvertImageOptions options,
}) async {
  var image = decodeImage(bytes)!;

  // Crop
  var cropRect = options.cropRect;
  if (cropRect != null) {
    image = copyCrop(image, cropRect.left.round(), cropRect.top.round(),
        cropRect.width.round(), cropRect.height.round());
  }
  var dstWidth = options.width ?? cropRect?.width.round() ?? image.width;
  var dstHeight = options.height ?? cropRect?.height.round() ?? image.height;

  // Resize the image
  image = copyResize(image, width: dstWidth, height: dstHeight);

  var encoding = options.encoding;
  late Uint8List imageBytes;
  if (encoding is ImageEncodingJpg) {
    imageBytes = asUint8List(encodeJpg(image, quality: encoding.quality));
  } else {
    imageBytes = asUint8List(encodePng(image));
  }
  return ImageData(
      bytes: imageBytes,
      encoding: encoding,
      width: dstWidth,
      height: dstHeight);
}
