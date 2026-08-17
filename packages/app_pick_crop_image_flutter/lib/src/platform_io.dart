import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';
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
    /// The file picker handles the linux (file_selector/gtk) fallback and
    /// remembers the last directory.
    var pickedFile = await (tekalyFilePickerOrNull ?? tekalyFilePickerFlutter)
        .pickImageFile();
    if (pickedFile != null) {
      return TkPickedFilePlatform(pickedFile);
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

/// Read file.
Future<Uint8List> readFile(String path) => File(path).readAsBytes();

/// True if canvas kit.
const isCanvasKit = true;
