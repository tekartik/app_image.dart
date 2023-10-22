import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';

/// Image meta
class ImageMeta {
  /// The image meta
  final int width;
  final int height;
  final ImageEncoding encoding;

  ImageMeta(
      {required this.encoding, required this.width, required this.height});

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
