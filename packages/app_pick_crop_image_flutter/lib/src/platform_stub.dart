import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'pick_crop_image.dart';

Future<Uint8List> resizeTo(Uint8List bytes,
        {required PickCropConvertImageOptions options}) =>
    throw UnsupportedError('Web or io supported');

void saveImageFile(
        {required Uint8List bytes,
        required mimeType,
        required String filename}) =>
    throw UnsupportedError('Web or io supported');

Future<XFile?> pickImage({
  required ImageSource source,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) =>
    throw UnsupportedError('Web or io supported');
