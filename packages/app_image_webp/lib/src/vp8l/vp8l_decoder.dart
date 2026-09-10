import 'dart:typed_data';

import '../webp_image.dart';
import 'bit_reader.dart';
import 'color_cache.dart';
import 'huffman_table.dart';
import 'lossless_dsp.dart';

/// VP8L signature byte.
const vp8lMagicByte = 0x2f;

/// Number of literal codes (green channel values).
const numLiteralCodes = 256;

/// Number of length prefix codes.
const numLengthCodes = 24;

/// Number of distance prefix codes.
const numDistanceCodes = 40;

/// Number of code-length codes.
const codeLengthCodes = 19;

/// Maximum color cache bits.
const maxCacheBits = 11;

/// Order in which code-length code lengths are stored.
const codeLengthCodeOrder = [
  17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
];

const _codeLengthExtraBits = [2, 3, 7];
const _codeLengthRepeatOffsets = [3, 3, 11];

/// Distance code to (yoffset, xoffset) mapping table.
const _codeToPlane = [
  0x18, 0x07, 0x17, 0x19, 0x28, 0x06, 0x27, 0x29, 0x16, 0x1a, //
  0x26, 0x2a, 0x38, 0x05, 0x37, 0x39, 0x15, 0x1b, 0x36, 0x3a, //
  0x25, 0x2b, 0x48, 0x04, 0x47, 0x49, 0x14, 0x1c, 0x35, 0x3b, //
  0x46, 0x4a, 0x24, 0x2c, 0x58, 0x45, 0x4b, 0x34, 0x3c, 0x03, //
  0x57, 0x59, 0x13, 0x1d, 0x56, 0x5a, 0x23, 0x2d, 0x44, 0x4c, //
  0x55, 0x5b, 0x33, 0x3d, 0x68, 0x02, 0x67, 0x69, 0x12, 0x1e, //
  0x66, 0x6a, 0x22, 0x2e, 0x54, 0x5c, 0x43, 0x4d, 0x65, 0x6b, //
  0x32, 0x3e, 0x78, 0x01, 0x77, 0x79, 0x53, 0x5d, 0x11, 0x1f, //
  0x64, 0x6c, 0x42, 0x4e, 0x76, 0x7a, 0x21, 0x2f, 0x75, 0x7b, //
  0x31, 0x3f, 0x63, 0x6d, 0x52, 0x5e, 0x00, 0x74, 0x7c, 0x41, //
  0x4f, 0x10, 0x20, 0x62, 0x6e, 0x30, 0x73, 0x7d, 0x51, 0x5f, //
  0x40, 0x72, 0x7e, 0x61, 0x6f, 0x50, 0x71, 0x7f, 0x60, 0x70, //
];

/// Converts a distance code (1-based) into a pixel distance.
int planeCodeToDistance(int xsize, int planeCode) {
  if (planeCode > 120) {
    return planeCode - 120;
  }
  final distCode = _codeToPlane[planeCode - 1];
  final yoffset = distCode >> 4;
  final xoffset = 8 - (distCode & 0xf);
  final dist = yoffset * xsize + xoffset;
  return dist >= 1 ? dist : 1;
}

enum _TransformType { predictor, crossColor, subtractGreen, colorIndexing }

class _Transform {
  final _TransformType type;
  final int xsize; // width of the output of this transform
  final int ysize;
  int bits = 0;
  Uint32List? data;
  _Transform(this.type, this.xsize, this.ysize);
}

class _HTreeGroup {
  final List<HuffmanTable> htrees;
  bool isTrivialLiteral = false;
  int literalArb = 0;
  bool isTrivialCode = false;
  _HTreeGroup(this.htrees);
}

class _Metadata {
  int colorCacheSize = 0;
  ColorCache? colorCache;
  Uint32List? huffmanImage;
  int huffmanSubsampleBits = 0;
  int huffmanXsize = 0;
  int huffmanMask = 0;
  List<_HTreeGroup> htreeGroups = const [];
}

/// Decoder for the VP8L lossless bitstream.
class Vp8lDecoder {
  final Vp8lBitReader _br;

  /// Image width.
  int width = 0;

  /// Image height.
  int height = 0;

  /// Alpha hint from the header (informational only).
  bool hasAlpha = false;

  final List<_Transform> _transforms = [];
  int _transformsSeen = 0;
  _Metadata _hdr = _Metadata();
  int _depth = 0;

  Vp8lDecoder._(this._br);

  /// Creates a decoder for a full VP8L chunk payload (with 5-byte header).
  factory Vp8lDecoder(Uint8List data) {
    if (data.length < 5 || data[0] != vp8lMagicByte) {
      throw WebpFormatException('Bad VP8L signature');
    }
    final br = Vp8lBitReader(data, 1);
    final dec = Vp8lDecoder._(br);
    dec.width = br.readBits(14) + 1;
    dec.height = br.readBits(14) + 1;
    dec.hasAlpha = br.readBits(1) != 0;
    final version = br.readBits(3);
    if (version != 0) {
      throw WebpFormatException('Unsupported VP8L version $version');
    }
    return dec;
  }

  /// Creates a decoder for an alpha-plane stream (no header, size known).
  factory Vp8lDecoder.alpha(Uint8List data, int width, int height) {
    final dec = Vp8lDecoder._(Vp8lBitReader(data, 0));
    dec.width = width;
    dec.height = height;
    return dec;
  }

  /// Reads the header (width/height) of a VP8L payload without decoding.
  static WebpInfo readInfo(Uint8List data) {
    final dec = Vp8lDecoder(data);
    return WebpInfo(
      width: dec.width,
      height: dec.height,
      hasAlpha: dec.hasAlpha,
      format: WebpFormat.lossless,
    );
  }

  /// Decodes the whole image and returns ARGB pixels (`width * height`).
  Uint32List decode() {
    var transformWidth = _decodeImageStream(width, height, true);
    final numPixTrans = transformWidth * height;
    final pixels = Uint32List(numPixTrans);
    _decodeImageData(pixels, transformWidth, height);
    if (_br.eos) {
      throw WebpFormatException('Truncated VP8L data');
    }
    return _applyInverseTransforms(pixels);
  }

  /// Returns the current width after transforms; reads transforms (level 0)
  /// color cache info and Huffman codes.
  int _decodeImageStream(int xsize, int ysize, bool isLevel0) {
    var transformXsize = xsize;
    if (isLevel0) {
      while (_br.readBits(1) == 1) {
        transformXsize = _readTransform(transformXsize, ysize);
        if (_transforms.length > 4) {
          throw WebpFormatException('Too many transforms');
        }
      }
    }
    var colorCacheBits = 0;
    if (_br.readBits(1) == 1) {
      colorCacheBits = _br.readBits(4);
      if (colorCacheBits < 1 || colorCacheBits > maxCacheBits) {
        throw WebpFormatException('Invalid color cache bits $colorCacheBits');
      }
    }
    _readHuffmanCodes(transformXsize, ysize, colorCacheBits, isLevel0);
    if (colorCacheBits > 0) {
      _hdr.colorCacheSize = 1 << colorCacheBits;
      _hdr.colorCache = ColorCache(colorCacheBits);
    } else {
      _hdr.colorCacheSize = 0;
      _hdr.colorCache = null;
    }
    final numBits = _hdr.huffmanSubsampleBits;
    _hdr.huffmanXsize = subSampleSize(transformXsize, numBits);
    _hdr.huffmanMask = numBits == 0 ? -1 : (1 << numBits) - 1;
    if (_br.eos) {
      throw WebpFormatException('Truncated VP8L header');
    }
    return transformXsize;
  }

  Uint32List _decodeSubImage(int xsize, int ysize) {
    _depth++;
    if (_depth > 2) throw WebpFormatException('Invalid VP8L recursion');
    final saved = _hdr;
    _hdr = _Metadata();
    _decodeImageStream(xsize, ysize, false);
    final data = Uint32List(xsize * ysize);
    _decodeImageData(data, xsize, ysize);
    _hdr = saved;
    _depth--;
    return data;
  }

  int _readTransform(int xsize, int ysize) {
    final typeIndex = _br.readBits(2);
    if ((_transformsSeen & (1 << typeIndex)) != 0) {
      throw WebpFormatException('Duplicate VP8L transform');
    }
    _transformsSeen |= 1 << typeIndex;
    final type = _TransformType.values[typeIndex];
    final t = _Transform(type, xsize, ysize);
    _transforms.add(t);
    switch (type) {
      case _TransformType.predictor:
      case _TransformType.crossColor:
        t.bits = 2 + _br.readBits(3);
        t.data = _decodeSubImage(
          subSampleSize(xsize, t.bits),
          subSampleSize(ysize, t.bits),
        );
      case _TransformType.colorIndexing:
        final numColors = _br.readBits(8) + 1;
        final bits = numColors > 16
            ? 0
            : numColors > 4
            ? 1
            : numColors > 2
            ? 2
            : 3;
        t.bits = bits;
        final palette = _decodeSubImage(numColors, 1);
        t.data = _expandColorMap(numColors, bits, palette);
        xsize = subSampleSize(xsize, bits);
      case _TransformType.subtractGreen:
        break;
    }
    return xsize;
  }

  static Uint32List _expandColorMap(
    int numColors,
    int bits,
    Uint32List palette,
  ) {
    final finalNumColors = 1 << (8 >> bits);
    final newMap = Uint32List(finalNumColors);
    // Delta-decode per byte component.
    var prev = palette[0];
    newMap[0] = prev;
    for (var i = 1; i < numColors; i++) {
      prev = addPixels(palette[i], prev);
      newMap[i] = prev;
    }
    return newMap;
  }

  List<int> _readHuffmanCodeLengths(HuffmanTable clTable, int numSymbols) {
    final codeLengths = List<int>.filled(numSymbols, 0);
    var prevCodeLen = 8;
    var maxSymbol = numSymbols;
    if (_br.readBits(1) == 1) {
      final lengthNbits = 2 + 2 * _br.readBits(3);
      maxSymbol = 2 + _br.readBits(lengthNbits);
      if (maxSymbol > numSymbols) {
        throw WebpFormatException('Invalid Huffman max symbol');
      }
    }
    var symbol = 0;
    while (symbol < numSymbols) {
      if (maxSymbol-- == 0) break;
      final entry = clTable.table[_br.peekBits(lengthsTableBits)];
      _br.skipBits(entry >> 16);
      final codeLen = entry & 0xffff;
      if (codeLen < 16) {
        codeLengths[symbol++] = codeLen;
        if (codeLen != 0) prevCodeLen = codeLen;
      } else {
        final usePrev = codeLen == 16;
        final slot = codeLen - 16;
        final extraBits = _codeLengthExtraBits[slot];
        final repeatOffset = _codeLengthRepeatOffsets[slot];
        var repeat = _br.readBits(extraBits) + repeatOffset;
        if (symbol + repeat > numSymbols) {
          throw WebpFormatException('Invalid Huffman code lengths');
        }
        final length = usePrev ? prevCodeLen : 0;
        while (repeat-- > 0) {
          codeLengths[symbol++] = length;
        }
      }
    }
    if (_br.eos) throw WebpFormatException('Truncated Huffman code lengths');
    return codeLengths;
  }

  HuffmanTable _readHuffmanCode(int alphabetSize) {
    List<int> codeLengths;
    final simple = _br.readBits(1);
    if (simple == 1) {
      codeLengths = List<int>.filled(alphabetSize, 0);
      final numSymbols = _br.readBits(1) + 1;
      final firstSymbolLenCode = _br.readBits(1);
      final symbol = _br.readBits(firstSymbolLenCode == 0 ? 1 : 8);
      if (symbol >= alphabetSize) {
        throw WebpFormatException('Invalid Huffman symbol');
      }
      codeLengths[symbol] = 1;
      if (numSymbols == 2) {
        final symbol2 = _br.readBits(8);
        if (symbol2 >= alphabetSize) {
          throw WebpFormatException('Invalid Huffman symbol');
        }
        codeLengths[symbol2] = 1;
      }
    } else {
      final clCodeLengths = List<int>.filled(codeLengthCodes, 0);
      final numCodes = _br.readBits(4) + 4;
      for (var i = 0; i < numCodes; i++) {
        clCodeLengths[codeLengthCodeOrder[i]] = _br.readBits(3);
      }
      final clTable = HuffmanTable.build(clCodeLengths, lengthsTableBits);
      codeLengths = _readHuffmanCodeLengths(clTable, alphabetSize);
    }
    if (_br.eos) throw WebpFormatException('Truncated Huffman code');
    return HuffmanTable.build(codeLengths, huffmanTableBits);
  }

  void _readHuffmanCodes(
    int xsize,
    int ysize,
    int colorCacheBits,
    bool allowRecursion,
  ) {
    var numHtreeGroups = 1;
    var numHtreeGroupsMax = 1;
    Uint32List? huffmanImage;
    List<int>? mapping;
    if (allowRecursion && _br.readBits(1) == 1) {
      final huffmanPrecision = 2 + _br.readBits(3);
      final huffmanXsize = subSampleSize(xsize, huffmanPrecision);
      final huffmanYsize = subSampleSize(ysize, huffmanPrecision);
      final huffmanPixs = huffmanXsize * huffmanYsize;
      final sub = _decodeSubImage(huffmanXsize, huffmanYsize);
      _hdr.huffmanSubsampleBits = huffmanPrecision;
      for (var i = 0; i < huffmanPixs; i++) {
        final group = (sub[i] >>> 8) & 0xffff;
        sub[i] = group;
        if (group + 1 > numHtreeGroupsMax) numHtreeGroupsMax = group + 1;
      }
      if (numHtreeGroupsMax > 1000 || numHtreeGroupsMax > xsize * ysize) {
        mapping = List<int>.filled(numHtreeGroupsMax, -1);
        numHtreeGroups = 0;
        for (var i = 0; i < huffmanPixs; i++) {
          final g = sub[i];
          if (mapping[g] == -1) {
            mapping[g] = numHtreeGroups++;
          }
          sub[i] = mapping[g];
        }
      } else {
        numHtreeGroups = numHtreeGroupsMax;
      }
      huffmanImage = sub;
    }
    if (_br.eos) throw WebpFormatException('Truncated Huffman image');
    final groups = List<_HTreeGroup?>.filled(numHtreeGroups, null);
    final alphabetSizes = [
      numLiteralCodes +
          numLengthCodes +
          (colorCacheBits > 0 ? 1 << colorCacheBits : 0),
      numLiteralCodes,
      numLiteralCodes,
      numLiteralCodes,
      numDistanceCodes,
    ];
    for (var i = 0; i < numHtreeGroupsMax; i++) {
      final mapped = mapping == null ? i : mapping[i];
      if (mapped == -1) {
        for (var j = 0; j < 5; j++) {
          _readHuffmanCode(alphabetSizes[j]);
        }
        continue;
      }
      final htrees = <HuffmanTable>[];
      var isTrivialLiteral = true;
      var totalBits = 0;
      for (var j = 0; j < 5; j++) {
        final table = _readHuffmanCode(alphabetSizes[j]);
        htrees.add(table);
        if (j >= 1 && j <= 3 && isTrivialLiteral) {
          isTrivialLiteral = table.rootBitsOfEntry0 == 0;
        }
        totalBits += table.rootBitsOfEntry0;
      }
      final group = _HTreeGroup(htrees);
      group.isTrivialLiteral = isTrivialLiteral;
      if (isTrivialLiteral) {
        final red = htrees[1].valueOfEntry0;
        final blue = htrees[2].valueOfEntry0;
        final alpha = htrees[3].valueOfEntry0;
        group.literalArb = (alpha << 24) | (red << 16) | blue;
        if (totalBits == 0 && htrees[0].valueOfEntry0 < numLiteralCodes) {
          group.isTrivialCode = true;
          group.literalArb |= htrees[0].valueOfEntry0 << 8;
        }
      }
      groups[mapped] = group;
    }
    _hdr.htreeGroups = groups.cast<_HTreeGroup>();
    _hdr.huffmanImage = huffmanImage;
  }

  _HTreeGroup _getHtreeGroup(int x, int y) {
    final hdr = _hdr;
    if (hdr.huffmanSubsampleBits == 0 || hdr.huffmanImage == null) {
      return hdr.htreeGroups[0];
    }
    final idx =
        hdr.huffmanXsize * (y >> hdr.huffmanSubsampleBits) +
        (x >> hdr.huffmanSubsampleBits);
    return hdr.htreeGroups[hdr.huffmanImage![idx]];
  }

  int _readSymbol(HuffmanTable table) {
    final br = _br;
    var entry = table.table[br.peekBits(huffmanTableBits)];
    final nbits = (entry >> 16) - huffmanTableBits;
    if (nbits > 0) {
      br.skipBits(huffmanTableBits);
      final idx = (entry & 0xffff) + br.peekBits(nbits);
      entry = table.table[idx];
      br.skipBits(entry >> 16);
    } else {
      br.skipBits(entry >> 16);
    }
    return entry & 0xffff;
  }

  int _getCopyDistance(int symbol) {
    if (symbol < 4) return symbol + 1;
    final extraBits = (symbol - 2) >> 1;
    final offset = (2 + (symbol & 1)) << extraBits;
    return offset + _br.readBits(extraBits) + 1;
  }

  void _decodeImageData(Uint32List data, int width, int height) {
    final br = _br;
    final hdr = _hdr;
    const lenCodeLimit = numLiteralCodes + numLengthCodes;
    final colorCacheLimit = lenCodeLimit + hdr.colorCacheSize;
    final colorCache = hdr.colorCache;
    final mask = hdr.huffmanMask;
    final end = width * height;
    var pos = 0;
    var col = 0;
    var row = 0;
    var group = _getHtreeGroup(0, 0);
    while (pos < end) {
      if ((col & mask) == 0) {
        group = _getHtreeGroup(col, row);
      }
      if (group.isTrivialCode) {
        data[pos] = group.literalArb;
        colorCache?.insert(group.literalArb);
        pos++;
        col++;
        if (col >= width) {
          col = 0;
          row++;
        }
        continue;
      }
      final code = _readSymbol(group.htrees[0]);
      if (br.eos) break;
      if (code < numLiteralCodes) {
        int argb;
        if (group.isTrivialLiteral) {
          argb = group.literalArb | (code << 8);
        } else {
          final red = _readSymbol(group.htrees[1]);
          final blue = _readSymbol(group.htrees[2]);
          final alpha = _readSymbol(group.htrees[3]);
          if (br.eos) break;
          argb = (alpha << 24) | (red << 16) | (code << 8) | blue;
        }
        data[pos] = argb;
        colorCache?.insert(argb);
        pos++;
        col++;
        if (col >= width) {
          col = 0;
          row++;
        }
      } else if (code < lenCodeLimit) {
        final lengthSym = code - numLiteralCodes;
        final length = _getCopyDistance(lengthSym);
        final distSymbol = _readSymbol(group.htrees[4]);
        final distCode = _getCopyDistance(distSymbol);
        final dist = planeCodeToDistance(width, distCode);
        if (br.eos) break;
        if (pos < dist || end - pos < length) {
          throw WebpFormatException('Invalid VP8L backward reference');
        }
        for (var i = 0; i < length; i++) {
          final v = data[pos - dist + i];
          data[pos + i] = v;
        }
        if (colorCache != null) {
          for (var i = 0; i < length; i++) {
            colorCache.insert(data[pos + i]);
          }
        }
        pos += length;
        col += length;
        while (col >= width) {
          col -= width;
          row++;
        }
        if (pos < end && (col & mask) != 0) {
          group = _getHtreeGroup(col, row);
        }
      } else if (code < colorCacheLimit) {
        final key = code - lenCodeLimit;
        final argb = colorCache!.lookup(key);
        data[pos] = argb;
        pos++;
        col++;
        if (col >= width) {
          col = 0;
          row++;
        }
      } else {
        throw WebpFormatException('Invalid VP8L symbol');
      }
    }
    if (br.eos && pos < end) {
      throw WebpFormatException('Truncated VP8L image data');
    }
  }

  Uint32List _applyInverseTransforms(Uint32List pixels) {
    var current = pixels;
    for (var n = _transforms.length - 1; n >= 0; n--) {
      final t = _transforms[n];
      switch (t.type) {
        case _TransformType.subtractGreen:
          addGreenToBlueAndRed(current, 0, t.xsize * t.ysize);
        case _TransformType.predictor:
          _predictorInverse(t, current);
        case _TransformType.crossColor:
          _colorSpaceInverse(t, current);
        case _TransformType.colorIndexing:
          current = _colorIndexInverse(t, current);
      }
    }
    return current;
  }

  static void _predictorInverse(_Transform t, Uint32List data) {
    final width = t.xsize;
    final height = t.ysize;
    final bits = t.bits;
    final tilesPerRow = subSampleSize(width, bits);
    final modes = t.data!;
    // First row.
    data[0] = addPixels(data[0], argbBlack);
    for (var x = 1; x < width; x++) {
      data[x] = addPixels(data[x], data[x - 1]);
    }
    var rowStart = width;
    for (var y = 1; y < height; y++) {
      final upStart = rowStart - width;
      final modeRow = (y >> bits) * tilesPerRow;
      data[rowStart] = addPixels(data[rowStart], data[upStart]);
      var x = 1;
      while (x < width) {
        final mode = (modes[modeRow + (x >> bits)] >>> 8) & 0xf;
        var xEnd = ((x >> bits) + 1) << bits;
        if (xEnd > width) xEnd = width;
        switch (mode) {
          case 0:
            for (; x < xEnd; x++) {
              data[rowStart + x] = addPixels(data[rowStart + x], argbBlack);
            }
          case 1:
            for (; x < xEnd; x++) {
              data[rowStart + x] = addPixels(
                data[rowStart + x],
                data[rowStart + x - 1],
              );
            }
          case 2:
            for (; x < xEnd; x++) {
              data[rowStart + x] = addPixels(
                data[rowStart + x],
                data[upStart + x],
              );
            }
          default:
            for (; x < xEnd; x++) {
              // Top-right of the last pixel wraps to the first pixel of the
              // current row (already decoded), which lives at upStart + width.
              final pred = _predictAt(mode, data, rowStart, upStart, x);
              data[rowStart + x] = addPixels(data[rowStart + x], pred);
            }
        }
      }
      rowStart += width;
    }
  }

  static int _predictAt(
    int mode,
    Uint32List d,
    int rowStart,
    int upStart,
    int x,
  ) {
    final left = d[rowStart + x - 1];
    final top = d[upStart + x];
    final topLeft = d[upStart + x - 1];
    final topRight = d[upStart + x + 1]; // wraps to current row start
    switch (mode) {
      case 3:
        return topRight;
      case 4:
        return topLeft;
      case 5:
        return average3(left, top, topRight);
      case 6:
        return average2(left, topLeft);
      case 7:
        return average2(left, top);
      case 8:
        return average2(topLeft, top);
      case 9:
        return average2(top, topRight);
      case 10:
        return average4(left, topLeft, top, topRight);
      case 11:
        return selectPredictor(top, left, topLeft);
      case 12:
        return clampedAddSubtractFull(left, top, topLeft);
      case 13:
        return clampedAddSubtractHalf(left, top, topLeft);
      default:
        return argbBlack;
    }
  }

  static void _colorSpaceInverse(_Transform t, Uint32List data) {
    final width = t.xsize;
    final height = t.ysize;
    final bits = t.bits;
    final tilesPerRow = subSampleSize(width, bits);
    final tileWidth = 1 << bits;
    final codes = t.data!;
    var pos = 0;
    for (var y = 0; y < height; y++) {
      final codeRow = (y >> bits) * tilesPerRow;
      for (var x = 0; x < width; x += tileWidth) {
        final code = codes[codeRow + (x >> bits)];
        final g2r = code & 0xff;
        final g2b = (code >>> 8) & 0xff;
        final r2b = (code >>> 16) & 0xff;
        final xEnd = (x + tileWidth < width) ? x + tileWidth : width;
        for (var i = x; i < xEnd; i++) {
          data[pos + i] = transformColorInverse(g2r, g2b, r2b, data[pos + i]);
        }
      }
      pos += width;
    }
  }

  static Uint32List _colorIndexInverse(_Transform t, Uint32List src) {
    final width = t.xsize;
    final height = t.ysize;
    final bits = t.bits;
    final colorMap = t.data!;
    final bitsPerPixel = 8 >> bits;
    final dst = Uint32List(width * height);
    var si = 0;
    var di = 0;
    if (bitsPerPixel < 8) {
      final pixelsPerByte = 1 << bits;
      final countMask = pixelsPerByte - 1;
      final bitMask = (1 << bitsPerPixel) - 1;
      for (var y = 0; y < height; y++) {
        var packed = 0;
        for (var x = 0; x < width; x++) {
          if ((x & countMask) == 0) {
            packed = (src[si++] >>> 8) & 0xff;
          }
          dst[di++] = colorMap[packed & bitMask];
          packed >>= bitsPerPixel;
        }
      }
    } else {
      final n = width * height;
      for (var i = 0; i < n; i++) {
        dst[i] = colorMap[(src[i] >>> 8) & 0xff];
      }
    }
    return dst;
  }
}

/// Decodes a VP8L alpha stream (as stored in an `ALPH` chunk) into an
/// alpha plane of `width * height` bytes (the green channel of the image).
Uint8List decodeVp8lAlphaPlane(Uint8List data, int width, int height) {
  final dec = Vp8lDecoder.alpha(data, width, height);
  final argb = dec.decode();
  final out = Uint8List(width * height);
  for (var i = 0; i < out.length; i++) {
    out[i] = (argb[i] >>> 8) & 0xff;
  }
  return out;
}
