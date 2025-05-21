import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_common_utils/size/size.dart' show Rect;

/// Crop rectangle
typedef CropRect = Rect<double>;

/// Resize options.
class ResizeOptions {
  /// Width
  final int? width;

  /// Height
  final int? height;

  /// Crop rectangle
  final CropRect? cropRect;

  /// Encoding
  final ImageEncoding encoding;

  /// Resize options
  ResizeOptions({
    required this.width,
    required this.height,
    this.cropRect,
    this.encoding = const ImageEncodingPng(),
  });

  @override
  String toString() {
    return {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (cropRect != null) 'cropRect': cropRect,
      'encoding': encoding,
    }.toString();
  }
}
