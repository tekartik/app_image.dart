import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' as image_picker;
import 'package:tekartik_app_pick_crop_image_flutter/src/platform.dart';

import 'import.dart';
import 'import_image.dart';
import 'pick_crop_image_page.dart';
import 'picked_file.dart';

const mimeTypePng = 'image/png';
const mimeTypeJpg = 'image/jpeg';

/// Image source.
abstract class PickCropImageSource implements ImageSource {}

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

  const PickCropImageSourceCamera({
    this.preferredCameraDevice = SourceCameraDevice.rear,
  });

  @override
  String toString() => 'ImageSourceCamera($preferredCameraDevice)';
}

/// Memory source.
class PickCropImageSourceMemory
    implements PickCropImageSource, ImageSourceAsyncData, ImageSourceData {
  @override
  final Uint8List bytes;

  const PickCropImageSourceMemory({required this.bytes});

  @override
  String toString() => 'ImageSourceMemory()';

  @override
  Future<Uint8List> getBytes() async => bytes;
}

/// Asset source.
class ImageSourceAsset implements PickCropImageSource, ImageSourceAsyncData {
  final String name;

  ImageSourceAsset({required this.name});

  @override
  String toString() => 'ImageSourceAsset($name)';

  Uint8List? _bytes;
  @override
  Future<Uint8List> getBytes() async =>
      _bytes ??= byteDataToUint8List(await rootBundle.load(name));
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

  PickCropBaseImageOptions({
    this.encoding = const ImageEncodingPng(),
    this.width,
    this.height,
    num? aspectRatio,
  }) {
    if (width != null && height != null) {
      _aspectRatio = width! / height!;
    }
    _aspectRatio ??= aspectRatio;
  }
}

/// Pick crop image options.
class PickCropConvertImageOptions extends PickCropBaseImageOptions {
  PickCropConvertImageOptions({
    this.cropRect,
    super.width,
    super.height,
    super.encoding,
    super.aspectRatio,
  });

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

  /// Auto crop the image (fit, center)
  final bool autoCrop;

  PickCropImageOptions({
    super.width,
    super.height,
    super.encoding,
    double? super.aspectRatio,
    this.ovalCropMask = false,
    this.autoCrop = false,
    this.source = const PickCropImageSourceGallery(),
  });
}

/// Return the image selected on success.
///
/// On the web, you can only trigger this on a user action
/// And this might never returns if the user cancel during pick.
Future<ImageData?> pickCropImage(
  BuildContext context, {
  PickCropImageOptions? options,
}) => pickCropImageInternal(context, options: options);

/// Return the image selected on success.
///
/// On the web, you can only trigger this on a user action
/// And this might never returns if the user cancel during pick.
Future<ImageData?> pickCropImageInternal(
  BuildContext context, {
  PickCropImageOptions? options,
  ConvertPickCropResultCallback? callback,
}) async {
  options ??= PickCropImageOptions();
  var source = options.source;
  TkPickedFile? file;
  if (source is PickCropImageSourceCamera ||
      source is PickCropImageSourceGallery) {
    var camera =
        (source is PickCropImageSourceCamera
                ? source
                : const PickCropImageSourceCamera())
            .preferredCameraDevice;
    // On IOS we need to pick directly!
    file = await pickImage(
      source: source is PickCropImageSourceCamera
          ? image_picker.ImageSource.camera
          : image_picker.ImageSource.gallery,
      preferredCameraDevice: camera == SourceCameraDevice.front
          ? image_picker.CameraDevice.front
          : image_picker.CameraDevice.rear,
    );
  }
  /*
  var result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) {
    return PickImageCropPage(
      file: file,
      options: options ?? PickCropImageOptions(),
    );
  }));

   */
  // Remove the animation
  // ignore: use_build_context_synchronously
  var result = await Navigator.of(context).push<Object?>(
    PageRouteBuilder(
      pageBuilder: (context, animation1, animation2) => PickImageCropPage(
        callback: callback,
        file: file,
        options: options ?? PickCropImageOptions(),
      ),
      transitionDuration: Duration.zero,
    ),
  );

  if (result is ImageData) {
    return result;
  }
  return null;
}
