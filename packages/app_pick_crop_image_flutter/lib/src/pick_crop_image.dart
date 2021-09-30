import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/app_image_resize.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/platform.dart';

import 'pick_crop_image_page.dart';
import 'picked_file.dart';

const mimeTypePng = 'image/png';
const mimeTypeJpg = 'image/jpeg';

/// Image source.
abstract class PickCropImageSource {}

/// Pick from the gallery.
class PickCropImageSourceGallery implements PickCropImageSource {
  const PickCropImageSourceGallery();

  @override
  String toString() => 'ImageSourceGallery()';
}

/// Pick from the camera.
class PickCropImageSourceCamera implements PickCropImageSource {
  final CameraDevice preferredCameraDevice;

  const PickCropImageSourceCamera(
      {this.preferredCameraDevice = CameraDevice.rear});

  @override
  String toString() => 'ImageSourceCamera($preferredCameraDevice)';
}

/// Pick from the camera.
class PickCropImageSourceMemory implements PickCropImageSource {
  final Uint8List bytes;

  const PickCropImageSourceMemory({required this.bytes});
}

/// Pick crop image options.
class PickCropBaseImageOptions {
  /// Wanted output width.
  final int? width;

  /// Wanted output height.
  final int? height;

  /// Wanted encoding
  final ImageEncoding encoding;

  /// Aspect ratio (width and height wins)
  num? get aspectRatio => _aspectRatio;
  num? _aspectRatio;

  PickCropBaseImageOptions(
      {this.encoding = const ImageEncodingPng(),
      this.width,
      this.height,
      num? aspectRatio}) {
    if (width != null && height != null) {
      _aspectRatio = width! / height!;
    }
    _aspectRatio ??= aspectRatio;
  }
}

/// Pick crop image options.
class PickCropConvertImageOptions extends PickCropBaseImageOptions {
  PickCropConvertImageOptions(
      {this.cropRect,
      int? width,
      int? height,
      ImageEncoding encoding = const ImageEncodingPng(),
      num? aspectRatio})
      : super(
            width: width,
            height: height,
            aspectRatio: aspectRatio,
            encoding: encoding);

  /// Crop rectangle on original image
  final CropRect? cropRect;
}

/// Pick crop image options.
class PickCropImageOptions extends PickCropBaseImageOptions {
  /// Or just aspectRatio (only if width and height is not defined
  /// Image source (default to gallery)
  final PickCropImageSource source;

  PickCropImageOptions(
      {int? width,
      int? height,
      ImageEncoding encoding = const ImageEncodingPng(),
      double? aspectRatio,
      this.source = const PickCropImageSourceGallery()})
      : super(
            width: width,
            height: height,
            aspectRatio: aspectRatio,
            encoding: encoding);
}

/// Result.
class PickCropImageResult {
  /// The image data
  final Uint8List bytes;
  final ImageEncoding encoding;

  PickCropImageResult({required this.bytes, required this.encoding});

  @override
  String toString() {
    return {'size': bytes.length}.toString();
  }
}

/// Return the image selected on success.
///
/// On the web, you can only trigger this on a user action
/// And this might never returns if the user cancel during pick.
Future<PickCropImageResult?> pickCropImage(BuildContext context,
    {PickCropImageOptions? options}) async {
  options ??= PickCropImageOptions();
  var source = options.source;
  TkPickedFile? file;
  if (source is PickCropImageSourceCamera ||
      source is PickCropImageSourceGallery) {
    // On IOS we need to pick directly!
    file = await pickImage(
        source: source is PickCropImageSourceCamera
            ? ImageSource.camera
            : ImageSource.gallery,
        preferredCameraDevice: (source is PickCropImageSourceCamera
                ? source
                : const PickCropImageSourceCamera())
            .preferredCameraDevice);
  }
  var result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) {
    return PickImageCropPage(
      file: file,
      options: options ?? PickCropImageOptions(),
    );
  }));
  if (result is PickCropImageResult) {
    return result;
  }
  return null;
}
