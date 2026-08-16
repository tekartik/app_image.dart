import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:tekartik_app_platform/app_platform.dart';

import 'picked_file.dart';

final _picker = image_picker.ImagePicker();

/// Pick image.
Future<TkPickedFile?> pickImage({
  required image_picker.ImageSource source,
  image_picker.CameraDevice preferredCameraDevice =
      image_picker.CameraDevice.rear,
}) async {
  // Tested on linux only
  if ((platformContext.io?.isLinux ?? false) ||
      (platformContext.io?.isWindows ?? false) ||
      (platformContext.io?.isMacOS ?? false)) {
    var ffpFile = await FilePicker.pickFile(
      type: FileType.image,

      //allowedExtensions: ['.jpg', '.JPG', '.png', '.PNG']
    );
    if (ffpFile != null) {
      return TkPickedFilePlatform(ffpFile);
    }
  } else {
    var file = await _picker.pickImage(
      source: source,
      preferredCameraDevice: preferredCameraDevice,
    );
    if (file == null) {
      return null;
    }
    return TkPickedFileImage(file);
  }
  return null;
}

/// Save image file.
Future<void> saveImageFile({
  required Uint8List bytes,
  required String mimeType,
  required String filename,
}) async {
  await FilePicker.saveFile(
    fileName: filename,
    bytes: bytes,
    mimeType: mimeType,
  );
}

/// Read file.
Future<Uint8List> readFile(String path) => File(path).readAsBytes();

/// True if canvas kit.
const isCanvasKit = true;
