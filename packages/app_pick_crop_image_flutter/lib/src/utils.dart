import 'dart:typed_data';

import 'package:image/image.dart' as impl;
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';

import 'import.dart';

// Raw implementation
Uint8List resizeToPngSync(Uint8List bytes, int width, int height) {
  var image = impl.decodeImage(bytes)!;

  // Resize the image to a 120x? thumbnail (maintaining the aspect ratio).
  image = impl.copyResize(image, width: width, height: height);

  // Save the thumbnail as a PNG.
  return asUint8List(impl.encodePng(image));
}

@Deprecated('Old')
Future<ImageData> imageResizeTo(
  Uint8List bytes, {
  required PickCropConvertImageOptions options,
}) async {
  var image = impl.decodeImage(bytes)!;

  // Crop
  var cropRect = options.cropRect;
  if (cropRect != null) {
    image = impl.copyCrop(
      image,
      x: cropRect.left.round(),
      y: cropRect.top.round(),
      width: cropRect.width.round(),
      height: cropRect.height.round(),
    );
  }
  var dstWidth = options.width ?? cropRect?.width.round() ?? image.width;
  var dstHeight = options.height ?? cropRect?.height.round() ?? image.height;

  // Resize the image
  image = impl.copyResize(image, width: dstWidth, height: dstHeight);

  var encoding = options.encoding;
  late Uint8List imageBytes;
  if (encoding is ImageEncodingJpg) {
    imageBytes = asUint8List(impl.encodeJpg(image, quality: encoding.quality));
  } else {
    imageBytes = asUint8List(impl.encodePng(image));
  }
  return ImageData(
    bytes: imageBytes,
    encoding: encoding,
    width: dstWidth,
    height: dstHeight,
  );
}
