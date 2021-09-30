import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'pick_crop_image.dart';
import 'picked_file.dart';

Future<Uint8List> resizeTo(Uint8List bytes,
        {required PickCropConvertImageOptions options}) =>
    throw UnsupportedError('Web or io supported');

/// This proposes a save as dialog on Desktop and download it on the Web...
Future<void> saveImageFile(
        {required Uint8List bytes,
        required mimeType,
        required String filename}) =>
    throw UnsupportedError('Web or io supported');

Future<TkPickedFile?> pickImage({
  required ImageSource source,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) =>
    throw UnsupportedError('Web or io supported');

/// Read a file.
Future<Uint8List> readFile(String path) => throw UnsupportedError('io only');
