import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/utils.dart';

import 'pick_crop_image.dart';

class _In {
  final Uint8List bytes;

  final PickCropConvertImageOptions options;

  _In(this.bytes, this.options);
}

Future<Uint8List> _resizeTo(_In data) async {
  return imageResizeTo(data.bytes, options: data.options);
}

Future<Uint8List> resizeTo(Uint8List bytes,
    {required PickCropConvertImageOptions options}) async {
  return compute<_In, Uint8List>(_resizeTo, _In(bytes, options));
}

final _picker = ImagePicker();

Future<XFile?> pickImage({
  required ImageSource source,
  CameraDevice preferredCameraDevice = CameraDevice.rear,
}) =>
    _picker.pickImage(
        source: source, preferredCameraDevice: preferredCameraDevice);
