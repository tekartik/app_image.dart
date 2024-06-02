// ignore: implementation_imports
import 'package:flutter/foundation.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
// ignore: implementation_imports
import 'package:tekartik_app_image_web/src/resize.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';

export 'platform_stub.dart'
    if (dart.library.js_interop) 'platform_web.dart'
    if (dart.library.io) 'platform_io.dart';

ResizeOptions _resizeOptions(PickCropConvertImageOptions pickCropImageOptions) {
  return ResizeOptions(
      width: pickCropImageOptions.width,
      height: pickCropImageOptions.height,
      encoding: pickCropImageOptions.encoding,
      cropRect: pickCropImageOptions.cropRect);
}

class _In {
  final Uint8List bytes;

  final ResizeOptions options;

  _In(this.bytes, this.options);
}

Future<ImageData> _resizeTo(_In data) async {
  return universalResizeTo(data.bytes, options: data.options);
}

Future<ImageData> pickCropResizeTo(Uint8List bytes,
    {required PickCropConvertImageOptions options}) async {
  return compute<_In, ImageData>(
      _resizeTo, _In(bytes, _resizeOptions(options)));
}
