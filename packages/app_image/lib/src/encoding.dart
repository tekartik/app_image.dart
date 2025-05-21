import 'package:tekartik_app_image/app_image.dart';

/// Abstract image encoding information.
abstract class ImageEncoding {
  /// Mime type
  String get mimeType;

  /// Extension
  String get extension;
}

/// Jpeg quality
const imageEncodingJpgQualityUnknown = -1;

/// Jpeg encoding
class ImageEncodingJpg implements ImageEncoding {
  /// From 0 to 100
  final int quality;

  /// Jpeg encoding
  ImageEncodingJpg({required this.quality}) {
    if (quality < -1 || quality > 100) {
      throw ArgumentError(
        'Invalid quality $quality value. Must be between 0 and 100',
      );
    }
  }

  @override
  String get extension => extensionJpg;

  @override
  String get mimeType => mimeTypeJpg;

  @override
  String toString() =>
      'Jpg${quality == imageEncodingJpgQualityUnknown ? '' : '($quality)'}';
}

/// Png encoding
class ImageEncodingPng implements ImageEncoding {
  /// Png encoding
  const ImageEncodingPng();

  @override
  String get extension => extensionPng;

  @override
  String get mimeType => mimeTypePng;

  @override
  String toString() => 'Png';
}

/// Webp encoding
class ImageEncodingWebp implements ImageEncoding {
  /// Webp encoding
  const ImageEncodingWebp();

  @override
  String get extension => extensionWebp;

  @override
  String get mimeType => mimeTypeWebp;

  @override
  String toString() => 'Webp';
}
