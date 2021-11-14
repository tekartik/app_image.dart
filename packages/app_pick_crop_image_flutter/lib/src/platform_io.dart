import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/utils.dart';
import 'package:tekartik_app_platform/app_platform.dart';

import 'pick_crop_image.dart';
import 'picked_file.dart';

class _In {
  final Uint8List bytes;

  final PickCropConvertImageOptions options;

  _In(this.bytes, this.options);
}

Future<ImageData> _resizeTo(_In data) async {
  return imageResizeTo(data.bytes, options: data.options);
}

Future<ImageData> resizeTo(Uint8List bytes,
    {required PickCropConvertImageOptions options}) async {
  return compute<_In, ImageData>(_resizeTo, _In(bytes, options));
}

final _picker = image_picker.ImagePicker();

Future<TkPickedFile?> pickImage({
  required image_picker.ImageSource source,
  image_picker.CameraDevice preferredCameraDevice =
      image_picker.CameraDevice.rear,
}) async {
  // Tested on linux only
  if ((platformContext.io?.isLinux ?? false) ||
      (platformContext.io?.isWindows ?? false) ||
      (platformContext.io?.isMacOS ?? false)) {
    var ffpResult = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,

      //allowedExtensions: ['.jpg', '.JPG', '.png', '.PNG']
    );
    if (ffpResult != null && ffpResult.count >= 1) {
      return TkPickedFilePlatform(ffpResult.files.first);
    }
  } else {
    var file = await _picker.pickImage(
        source: source, preferredCameraDevice: preferredCameraDevice);
    if (file == null) {
      return null;
    }
    return TkPickedFileImage(file);
  }
}

Future<void> saveImageFile(
    {required Uint8List bytes,
    required mimeType,
    required String filename}) async {
  var path = await FilePicker.platform.saveFile(fileName: filename);
  if (path != null) {
    await File(path).writeAsBytes(bytes);
  }
}

Future<Uint8List> readFile(String path) => File(path).readAsBytes();

// ignore: prefer_const_declarations
final isCanvasKit = true;
