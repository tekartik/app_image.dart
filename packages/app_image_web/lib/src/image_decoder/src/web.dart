import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/image_decoder/image_decoder.dart' as common;
import 'package:tekartik_app_image_web/src/import.dart';
import 'package:tekartik_app_image_web/src/offscreen_canvas/src/offscreen_canvas.dart';

var debugDecodeImage = false; // devWarning(true);
Future<ImageMeta> getImageMetaFromBytes(Uint8List bytes) async {
  var encoding = common.getImageEncodingFromBytes(bytes);
  var canvas = await OffscreenCanvas.fromBytes(bytes);
  var width = canvas.width;
  var height = canvas.height;
  return ImageMeta(encoding: encoding, width: width, height: height);
}
