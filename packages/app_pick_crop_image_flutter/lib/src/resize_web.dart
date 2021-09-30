// ignore_for_file: avoid_web_libraries_in_flutter, unsafe_html

import 'dart:typed_data';

import 'package:tekartik_app_image_web/app_image_web.dart' as web;
import 'package:tekartik_app_pick_crop_image_flutter/src/pick_crop_image.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/utils.dart';

import 'import.dart';

Future<Uint8List> webResizeTo(
  Uint8List bytes, {
  required PickCropConvertImageOptions options,
}) async {
  try {
    var resizeOptions = web.ResizeOptions(
        width: options.width,
        height: options.height,
        encoding: options.encoding);
    var resizedBytes = await web.resizeTo(bytes, options: resizeOptions);
    return resizedBytes;
  } catch (e) {
    print('Error web resize $e, trying standard resize');
    return imageResizeTo(bytes, options: options);
  }
}
