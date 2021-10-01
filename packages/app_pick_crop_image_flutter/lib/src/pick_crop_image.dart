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

/// Which camera to use when picking images/videos while source is `ImageSource.camera`.
///
/// Not every device supports both of the positions.
enum SourceCameraDevice {
  /// Use the rear camera.
  ///
  /// In most of the cases, it is the default configuration.
  rear,

  /// Use the front camera.
  ///
  /// Supported on all iPhones/iPads and some Android devices.
  front,
}

/// Pick from the camera.
class PickCropImageSourceCamera implements PickCropImageSource {
  final SourceCameraDevice preferredCameraDevice;

  const PickCropImageSourceCamera(
      {this.preferredCameraDevice = SourceCameraDevice.rear});

  @override
  String toString() => 'ImageSourceCamera($preferredCameraDevice)';
}

/// Pick from the camera.
class PickCropImageSourceMemory implements PickCropImageSource {
  final Uint8List bytes;

  const PickCropImageSourceMemory({required this.bytes});

  @override
  String toString() => 'ImageSourceMemory()';
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

  /// Round selection
  final bool ovalCropMask;

  PickCropImageOptions(
      {int? width,
      int? height,
      ImageEncoding encoding = const ImageEncodingPng(),
      double? aspectRatio,
      this.ovalCropMask = false,
      this.source = const PickCropImageSourceGallery()})
      : super(
            width: width,
            height: height,
            aspectRatio: aspectRatio,
            encoding: encoding);
}

/// Return the image selected on success.
///
/// On the web, you can only trigger this on a user action
/// And this might never returns if the user cancel during pick.
Future<ImageData?> pickCropImage(BuildContext context,
    {PickCropImageOptions? options}) async {
  options ??= PickCropImageOptions();
  var source = options.source;
  TkPickedFile? file;
  if (source is PickCropImageSourceCamera ||
      source is PickCropImageSourceGallery) {
    var camera = (source is PickCropImageSourceCamera
            ? source
            : const PickCropImageSourceCamera())
        .preferredCameraDevice;
    // On IOS we need to pick directly!
    file = await pickImage(
        source: source is PickCropImageSourceCamera
            ? ImageSource.camera
            : ImageSource.gallery,
        preferredCameraDevice: camera == SourceCameraDevice.front
            ? CameraDevice.front
            : CameraDevice.rear);
  }
  var result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) {
    return PickImageCropPage(
      file: file,
      options: options ?? PickCropImageOptions(),
    );
  }));
  if (result is ImageData) {
    return result;
  }
  return null;
}
