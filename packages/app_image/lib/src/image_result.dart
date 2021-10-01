import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';

/// Result.
class ImageData {
  /// The image data
  final Uint8List bytes;
  final int width;
  final int height;
  final ImageEncoding encoding;

  ImageData(
      {required this.bytes,
      required this.encoding,
      required this.width,
      required this.height});

  @override
  String toString() {
    return {
      'width': width,
      'height': height,
      'size': bytes.length,
      'encoding': encoding
    }.toString();
  }
}
