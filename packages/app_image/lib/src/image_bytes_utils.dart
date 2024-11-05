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

// WebP File Header
//
//  0                   1                   2                   3
//  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |      'R'      |      'I'      |      'F'      |      'F'      |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                           File Size                           |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |      'W'      |      'E'      |      'B'      |      'P'      |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// 'RIFF': 32 bits
// The ASCII characters 'R', 'I', 'F', 'F'.
// File Size: 32 bits (uint32)
// The size of the file in bytes, starting at offset 8. The maximum value of this field is 2^32 minus 10 bytes and thus the size of the whole file is at most 4 GiB minus 2 bytes.
// 'WEBP': 32 bits
// The ASCII characters 'W', 'E', 'B', 'P'.
/// Dirty check
bool isWebp(Uint8List bytes) =>
    _startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) &&
    bytes.length >= 12 &&
    bytes[8] == 0x57 &&
    bytes[9] == 0x45 &&
    bytes[10] == 0x42 &&
    bytes[11] == 0x50;
