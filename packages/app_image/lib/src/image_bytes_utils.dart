import 'dart:typed_data';

import 'package:collection/collection.dart';

// https://www.sparkhound.com/blog/detect-image-file-types-through-byte-arrays
// var bmp = Encoding.ASCII.GetBytes("BM"); // BMP
// var gif = Encoding.ASCII.GetBytes("GIF"); // GIF
// var png = new byte[] { 137, 80, 78, 71 }; // PNG
// var tiff = new byte[] { 73, 73, 42 }; // TIFF
// var tiff2 = new byte[] { 77, 77, 42 }; // TIFF
// var jpeg = new byte[] { 255, 216, 255, 224 }; // jpeg
// var jpeg2 = new byte[] { 255, 216, 255, 225 }; // jpeg canon

bool _startsWith(Uint8List bytes, List<int> start) {
  return bytes.length >= start.length &&
      const ListEquality<int>().equals(bytes.sublist(0, start.length), start);
}

/// Dirty check
bool isJpg(Uint8List bytes) => _startsWith(bytes, [255, 216, 255]);

/// Dirty check
bool isPng(Uint8List bytes) => _startsWith(bytes, [137, 80, 78]);
