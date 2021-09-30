import 'package:tekartik_app_image/app_image.dart';

/// Abstract image encoding information.
abstract class ImageEncoding {
  String get mimeType;
  String get extension;
}

/// Jpeg encoding
class ImageEncodingJpg implements ImageEncoding {
  /// From 0 to 100
  final int quality;

  ImageEncodingJpg({required this.quality}) {
    if (quality < 0 || quality > 100) {
      throw ArgumentError(
          'Invalid quality $quality value. Must be between 0 and 100');
    }
  }

  @override
  String get extension => extensionJpg;

  @override
  String get mimeType => mimeTypeJpg;
}

/// Png encoding
class ImageEncodingPng implements ImageEncoding {
  const ImageEncodingPng();

  @override
  String get extension => extensionPng;

  @override
  String get mimeType => mimeTypePng;
}
