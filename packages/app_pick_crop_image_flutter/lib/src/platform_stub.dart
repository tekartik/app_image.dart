import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:tekartik_app_image/app_image.dart';

import 'pick_crop_image.dart';
import 'picked_file.dart';

Future<ImageData> resizeTo(Uint8List bytes,
        {required PickCropConvertImageOptions options}) =>
    throw UnsupportedError('Web or io supported');

/// This proposes a save as dialog on Desktop and download it on the Web...
Future<void> saveImageFile(
        {required Uint8List bytes,
        required mimeType,
        required String filename}) =>
    throw UnsupportedError('Web or io supported');

Future<TkPickedFile?> pickImage({
  required image_picker.ImageSource source,
  image_picker.CameraDevice preferredCameraDevice =
      image_picker.CameraDevice.rear,
}) =>
    throw UnsupportedError('Web or io supported');

/// Read a file.
Future<Uint8List> readFile(String path) => throw UnsupportedError('io only');

// ignore: prefer_const_declarations
final isCanvasKit = true;
