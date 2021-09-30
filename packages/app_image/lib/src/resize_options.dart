import 'package:tekartik_app_image/app_image.dart';

/// Crop rectangle
class CropRect {
  final num top;
  final num left;
  final num width;
  final num height;

  CropRect.fromLTWH(this.left, this.top, this.width, this.height);

  @override
  String toString() => 'Rect.LTWH($left,$top,$width,$height)';
}

/// Resize options.
class ResizeOptions {
  final int? width;
  final int? height;
  final CropRect? cropRect;
  final ImageEncoding encoding;

  ResizeOptions(
      {required this.width,
      required this.height,
      this.cropRect,
      this.encoding = const ImageEncodingPng()});

  @override
  String toString() {
    return {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (cropRect != null) 'cropRect': cropRect,
      'encoding': encoding
    }.toString();
  }
}
