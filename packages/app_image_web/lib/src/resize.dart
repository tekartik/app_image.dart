import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/app_image_resize.dart';
import 'package:tekartik_app_image_web/src/image_composer/image_composer.dart';

/// Universal resize to.
Future<ImageData> universalResizeTo(
  Uint8List bytes, {
  required ResizeOptions options,
}) async {
  var data = ImageComposerData(
    width: options.width,
    height: options.height,
    encoding: options.encoding,
    layers: [
      ImageLayerData(
        source: ImageSource.bytes(bytes),
        sourceCropRect: options.cropRect,
      ),
    ],
  );
  var result = await composeImage(data);
  return result;
}

/// Resize to.
Future<ImageData> resizeTo(Uint8List bytes, {required ResizeOptions options}) =>
    universalResizeTo(bytes, options: options);
