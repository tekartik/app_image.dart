import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';

/// Image meta
class ImageMeta {
  /// The image width
  final int width;

  /// The image height
  final int height;

  /// The image encoding
  final ImageEncoding encoding;

  /// Image meta
  ImageMeta(
      {required this.encoding, required this.width, required this.height});

  /// Debug map
  Map toDebugMap() {
    return {'width': width, 'height': height, 'encoding': encoding};
  }

  @override
  String toString() {
    return toDebugMap().toString();
  }
}

/// Result.
class ImageData extends ImageMeta {
  /// The image data
  final Uint8List bytes;

  /// Image data
  ImageData(
      {required this.bytes,
      required super.encoding,
      required super.width,
      required super.height});

  @override
  Map toDebugMap() {
    return super.toDebugMap()..['sizeInBytes'] = bytes.length;
  }
}
