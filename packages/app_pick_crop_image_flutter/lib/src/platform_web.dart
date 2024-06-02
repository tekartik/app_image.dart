// ignore_for_file: unsafe_html, avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/pick_image_web.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/picked_file.dart';
import 'package:web/web.dart' as web;

Future<void> saveImageFile(
    {required Uint8List bytes,
    required mimeType,
    required String filename}) async {
// prepare
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = filename;
  web.document.body!.children.add(anchor);

// download
  anchor.click();

// cleanup
  anchor.remove();

  web.URL.revokeObjectURL(url);
}

final _picker = ImagePicker();

Future<TkPickedFile?> pickImage({
  required ImageSource source,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) async {
  var file = await _picker.pickImage(
      source: source, preferredCameraDevice: preferredCameraDevice);

  if (file == null) {
    return null;
  }
  return TkPickedFileImage(file);
}

Future<XFile?> pickImageExp({
  required ImageSource source,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) =>
    pickImageWeb(source: source, preferredCameraDevice: preferredCameraDevice);

/// Read a file.
Future<Uint8List> readFile(String path) => throw UnsupportedError('io only');

final isCanvasKit = globalContext.has('flutterCanvasKit');
