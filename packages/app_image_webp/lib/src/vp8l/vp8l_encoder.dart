/// VP8L (lossless) encoder.
library;

import 'dart:typed_data';

import 'backward_refs.dart';
import 'bit_writer.dart';
import 'entropy.dart';
import 'histogram.dart';
import 'huffman_encode.dart';
import 'lossless_dsp.dart';
import 'predictor_enc.dart';
import 'vp8l_decoder.dart' show codeLengthCodeOrder, vp8lMagicByte;

const _maxPaletteSize = 256;
const _maxHuffImageSize = 2600;
const _minHuffmanBits = 2;
const _maxHuffmanBits = _minHuffmanBits + (1 << 3) - 1;
const _minTransformBits = 2;
const _maxPredictorImageSize = 1 << 14;
const _numLengthCodes = 24;
const _numDistanceCodes = 40;
const _codeLengthCodes = 19;

/// Entropy modes evaluated by the analysis.
enum _EntropyIx { direct, spatial, subGreen, spatialSubGreen, palette }

/// Options of the lossless encoder.
class Vp8lEncoderOptions {
  /// Compression effort, 0 (fast) to 6 (slow).
  final int method;

  /// Quality (0..100), affects the search effort.
  final int quality;

  /// Preserve RGB values of fully transparent pixels.
  final bool exact;

  /// Creates options.
  const Vp8lEncoderOptions({
    this.method = 4,
    this.quality = 75,
    this.exact = false,
  });
}

int _hashPix8(int pix) {
  // ((pix + (pix >> 19)) * 0x39c5fba7) >> 24, in 32-bit arithmetic.
  final v = (pix + (pix >>> 19)) & 0xffffffff;
  return mul32(v, 0x39c5fba7) >>> 24;
}

class _Analysis {
  _EntropyIx entropyIx = _EntropyIx.direct;
  bool redAndBlueAlwaysZero = false;
}

_Analysis _analyzeEntropy(
  Uint32List argb,
  int width,
  int height,
  bool usePalette,
  int paletteSize,
  int transformBits,
) {
  final res = _Analysis();
  if (usePalette && paletteSize <= 16) {
    res.entropyIx = _EntropyIx.palette;
    res.redAndBlueAlwaysZero = true;
    return res;
  }
  const kHistoAlpha = 0,
      kHistoAlphaPred = 1,
      kHistoGreen = 2,
      kHistoGreenPred = 3,
      kHistoRed = 4,
      kHistoRedPred = 5,
      kHistoBlue = 6,
      kHistoBluePred = 7,
      kHistoRedSubGreen = 8,
      kHistoRedPredSubGreen = 9,
      kHistoBlueSubGreen = 10,
      kHistoBluePredSubGreen = 11,
      kHistoPalette = 12,
      kHistoTotal = 13;
  final histo = Uint32List(kHistoTotal * 256);
  void addSingle(int p, int a, int r, int g, int b) {
    histo[a * 256 + ((p >>> 24) & 0xff)]++;
    histo[r * 256 + ((p >>> 16) & 0xff)]++;
    histo[g * 256 + ((p >>> 8) & 0xff)]++;
    histo[b * 256 + (p & 0xff)]++;
  }

  void addSingleSubGreen(int p, int r, int b) {
    final green = (p >>> 8) & 0xff;
    histo[r * 256 + ((((p >>> 16) & 0xff) - green) & 0xff)]++;
    histo[b * 256 + (((p & 0xff) - green) & 0xff)]++;
  }

  var pixPrev = argb[0];
  var prevRow = -1;
  var currRow = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pix = argb[currRow + x];
      final pixDiff = subPixels(pix, pixPrev);
      pixPrev = pix;
      if (pixDiff == 0 || (prevRow >= 0 && pix == argb[prevRow + x])) continue;
      addSingle(pix, kHistoAlpha, kHistoRed, kHistoGreen, kHistoBlue);
      addSingle(
        pixDiff,
        kHistoAlphaPred,
        kHistoRedPred,
        kHistoGreenPred,
        kHistoBluePred,
      );
      addSingleSubGreen(pix, kHistoRedSubGreen, kHistoBlueSubGreen);
      addSingleSubGreen(pixDiff, kHistoRedPredSubGreen, kHistoBluePredSubGreen);
      histo[kHistoPalette * 256 + _hashPix8(pix)]++;
    }
    prevRow = currRow;
    currRow += width;
  }
  final lastModeToAnalyze = usePalette
      ? _EntropyIx.palette
      : _EntropyIx.spatialSubGreen;
  histo[kHistoRedPredSubGreen * 256]++;
  histo[kHistoBluePredSubGreen * 256]++;
  histo[kHistoRedPred * 256]++;
  histo[kHistoGreenPred * 256]++;
  histo[kHistoBluePred * 256]++;
  histo[kHistoAlphaPred * 256]++;
  final entropyComp = List<int>.filled(kHistoTotal, 0);
  for (var j = 0; j < kHistoTotal; j++) {
    entropyComp[j] = bitsEntropy(histo, j * 256, 256);
  }
  final entropy = List<int>.filled(5, 0);
  entropy[0] =
      entropyComp[kHistoAlpha] +
      entropyComp[kHistoRed] +
      entropyComp[kHistoGreen] +
      entropyComp[kHistoBlue];
  entropy[1] =
      entropyComp[kHistoAlphaPred] +
      entropyComp[kHistoRedPred] +
      entropyComp[kHistoGreenPred] +
      entropyComp[kHistoBluePred];
  entropy[2] =
      entropyComp[kHistoAlpha] +
      entropyComp[kHistoRedSubGreen] +
      entropyComp[kHistoGreen] +
      entropyComp[kHistoBlueSubGreen];
  entropy[3] =
      entropyComp[kHistoAlphaPred] +
      entropyComp[kHistoRedPredSubGreen] +
      entropyComp[kHistoGreenPred] +
      entropyComp[kHistoBluePredSubGreen];
  entropy[4] = entropyComp[kHistoPalette];
  final tiles =
      subSampleSize(width, transformBits) *
      subSampleSize(height, transformBits);
  entropy[1] += tiles * fastLog2(14);
  entropy[3] += tiles * fastLog2(24);
  entropy[4] += (paletteSize * 8) * log2Scale;
  var minIx = 0;
  for (var k = 1; k <= lastModeToAnalyze.index; k++) {
    if (entropy[minIx] > entropy[k]) minIx = k;
  }
  res.entropyIx = _EntropyIx.values[minIx];
  const kHistoPairs = [
    [kHistoRed, kHistoBlue],
    [kHistoRedPred, kHistoBluePred],
    [kHistoRedSubGreen, kHistoBlueSubGreen],
    [kHistoRedPredSubGreen, kHistoBluePredSubGreen],
    [kHistoRed, kHistoBlue],
  ];
  res.redAndBlueAlwaysZero = true;
  final redOff = kHistoPairs[minIx][0] * 256;
  final blueOff = kHistoPairs[minIx][1] * 256;
  for (var i = 1; i < 256; i++) {
    if ((histo[redOff + i] | histo[blueOff + i]) != 0) {
      res.redAndBlueAlwaysZero = false;
      break;
    }
  }
  return res;
}

int _clampBits(
  int width,
  int height,
  int bits,
  int minBits,
  int maxBits,
  int imageSizeMax,
) {
  bits = bits < minBits ? minBits : (bits > maxBits ? maxBits : bits);
  var imageSize = subSampleSize(width, bits) * subSampleSize(height, bits);
  while (bits < maxBits && imageSize > imageSizeMax) {
    bits++;
    imageSize = subSampleSize(width, bits) * subSampleSize(height, bits);
  }
  while (bits > minBits && imageSize == 1) {
    imageSize =
        subSampleSize(width, bits - 1) * subSampleSize(height, bits - 1);
    if (imageSize != 1) break;
    bits--;
  }
  return bits;
}

int _getHistoBits(int method, bool usePalette, int width, int height) {
  final histoBits = (usePalette ? 9 : 7) - method;
  return _clampBits(
    width,
    height,
    histoBits,
    _minHuffmanBits,
    _maxHuffmanBits,
    _maxHuffImageSize,
  );
}

int _getTransformBits(int method, int histoBits) {
  final maxTransformBits = method < 4 ? 6 : (method > 4 ? 4 : 5);
  return histoBits > maxTransformBits ? maxTransformBits : histoBits;
}

//------------------------------------------------------------------------------
// Palette

/// Returns the sorted palette of [argb], or null if more than 256 colors.
Uint32List? getColorPalette(Uint32List argb) {
  const colorHashSize = _maxPaletteSize * 4;
  const colorHashRightShift = 22;
  final inUse = Uint8List(colorHashSize);
  final colors = Uint32List(colorHashSize);
  var numColors = 0;
  var lastPix = argb[0] ^ 0xffffffff;
  for (var i = 0; i < argb.length; i++) {
    final pix = argb[i];
    if (pix == lastPix) continue;
    lastPix = pix;
    var key = hashPix(pix, colorHashRightShift);
    while (true) {
      if (inUse[key] == 0) {
        colors[key] = pix;
        inUse[key] = 1;
        numColors++;
        if (numColors > _maxPaletteSize) return null;
        break;
      } else if (colors[key] == pix) {
        break;
      } else {
        key = (key + 1) & (colorHashSize - 1);
      }
    }
  }
  final palette = <int>[];
  for (var i = 0; i < colorHashSize; i++) {
    if (inUse[i] != 0) palette.add(colors[i]);
  }
  palette.sort();
  return Uint32List.fromList(palette);
}

int _paletteComponentDistance(int v) => v <= 128 ? v : 256 - v;

int _paletteColorDistance(int col1, int col2) {
  final diff = subPixels(col1, col2);
  const kMoreWeightForRgbThanForAlpha = 9;
  var score = _paletteComponentDistance(diff & 0xff);
  score += _paletteComponentDistance((diff >>> 8) & 0xff);
  score += _paletteComponentDistance((diff >>> 16) & 0xff);
  score *= kMoreWeightForRgbThanForAlpha;
  score += _paletteComponentDistance((diff >>> 24) & 0xff);
  return score;
}

bool _paletteHasNonMonotonousDeltas(Uint32List palette, int numColors) {
  var predict = 0;
  var signFound = 0;
  for (var i = 0; i < numColors; i++) {
    final diff = subPixels(palette[i], predict);
    final rd = (diff >>> 16) & 0xff;
    final gd = (diff >>> 8) & 0xff;
    final bd = diff & 0xff;
    if (rd != 0) signFound |= rd < 0x80 ? 1 : 2;
    if (gd != 0) signFound |= gd < 0x80 ? 8 : 16;
    if (bd != 0) signFound |= bd < 0x80 ? 64 : 128;
    predict = palette[i];
  }
  return (signFound & (signFound << 1)) != 0;
}

/// Reorders [paletteSorted] to minimize deltas between consecutive entries.
Uint32List paletteSortMinimizeDeltas(Uint32List paletteSorted) {
  var numColors = paletteSorted.length;
  final palette = Uint32List.fromList(paletteSorted);
  if (!_paletteHasNonMonotonousDeltas(paletteSorted, numColors)) return palette;
  var predict = 0;
  if (numColors > 17) {
    if (palette[0] == 0) {
      numColors--;
      final tmp = palette[numColors];
      palette[numColors] = palette[0];
      palette[0] = tmp;
    }
  }
  for (var i = 0; i < numColors; i++) {
    var bestIx = i;
    var bestScore = 0xffffffff;
    for (var k = i; k < numColors; k++) {
      final curScore = _paletteColorDistance(palette[k], predict);
      if (bestScore > curScore) {
        bestScore = curScore;
        bestIx = k;
      }
    }
    final tmp = palette[bestIx];
    palette[bestIx] = palette[i];
    palette[i] = tmp;
    predict = palette[i];
  }
  return palette;
}

/// Bundles palette indices of a row into packed pixels.
void bundleColorMap(
  Uint8List row,
  int width,
  int xbits,
  Uint32List dst,
  int dstOff,
) {
  if (xbits > 0) {
    final bitDepth = 1 << (3 - xbits);
    final mask = (1 << xbits) - 1;
    var code = 0xff000000;
    for (var x = 0; x < width; x++) {
      final xsub = x & mask;
      if (xsub == 0) code = 0xff000000;
      code |= row[x] << (8 + bitDepth * xsub);
      dst[dstOff + (x >> xbits)] = code;
    }
  } else {
    for (var x = 0; x < width; x++) {
      dst[dstOff + x] = 0xff000000 | (row[x] << 8);
    }
  }
}

/// Maps [src] pixels to packed palette indices in a new buffer.
Uint32List applyPalette(
  Uint32List src,
  int width,
  int height,
  Uint32List palette,
  int xbits,
) {
  final packedWidth = subSampleSize(width, xbits);
  final dst = Uint32List(packedWidth * height);
  final tmpRow = Uint8List(width);
  final map = <int, int>{};
  for (var i = 0; i < palette.length; i++) {
    map[palette[i]] = i;
  }
  var prevPix = palette[0];
  var prevIdx = 0;
  for (var y = 0; y < height; y++) {
    final so = y * width;
    for (var x = 0; x < width; x++) {
      final pix = src[so + x];
      if (pix != prevPix) {
        prevIdx = map[pix]!;
        prevPix = pix;
      }
      tmpRow[x] = prevIdx;
    }
    bundleColorMap(tmpRow, width, xbits, dst, y * packedWidth);
  }
  return dst;
}

//------------------------------------------------------------------------------
// Huffman code storage

void _storeHuffmanTreeOfHuffmanTreeToBitMask(
  Vp8lBitWriter bw,
  Uint8List codeLengthBitdepth,
) {
  var codesToStore = _codeLengthCodes;
  for (; codesToStore > 4; codesToStore--) {
    if (codeLengthBitdepth[codeLengthCodeOrder[codesToStore - 1]] != 0) break;
  }
  bw.putBits(codesToStore - 4, 4);
  for (var i = 0; i < codesToStore; i++) {
    bw.putBits(codeLengthBitdepth[codeLengthCodeOrder[i]], 3);
  }
}

void _clearHuffmanTreeIfOnlyOneSymbol(HuffmanTreeCode huffmanCode) {
  var count = 0;
  for (var k = 0; k < huffmanCode.numSymbols; k++) {
    if (huffmanCode.codeLengths[k] != 0) {
      count++;
      if (count > 1) return;
    }
  }
  for (var k = 0; k < huffmanCode.numSymbols; k++) {
    huffmanCode.codeLengths[k] = 0;
    huffmanCode.codes[k] = 0;
  }
}

void _storeHuffmanTreeToBitMask(
  Vp8lBitWriter bw,
  List<HuffmanTreeToken> tokens,
  int numTokens,
  HuffmanTreeCode huffmanCode,
) {
  for (var i = 0; i < numTokens; i++) {
    final ix = tokens[i].code;
    final extraBits = tokens[i].extraBits;
    bw.putBits(huffmanCode.codes[ix], huffmanCode.codeLengths[ix]);
    switch (ix) {
      case 16:
        bw.putBits(extraBits, 2);
      case 17:
        bw.putBits(extraBits, 3);
      case 18:
        bw.putBits(extraBits, 7);
    }
  }
}

void _storeFullHuffmanCode(Vp8lBitWriter bw, HuffmanTreeCode tree) {
  final huffmanCode = HuffmanTreeCode(_codeLengthCodes);
  bw.putBits(0, 1);
  final tokens = createCompressedHuffmanTree(tree);
  final numTokens = tokens.length;
  {
    final histogram = Uint32List(_codeLengthCodes);
    for (var i = 0; i < numTokens; i++) {
      histogram[tokens[i].code]++;
    }
    createHuffmanTree(histogram, 7, huffmanCode);
  }
  _storeHuffmanTreeOfHuffmanTreeToBitMask(bw, huffmanCode.codeLengths);
  _clearHuffmanTreeIfOnlyOneSymbol(huffmanCode);
  {
    var trailingZeroBits = 0;
    var trimmedLength = numTokens;
    var i = numTokens;
    while (i-- > 0) {
      final ix = tokens[i].code;
      if (ix == 0 || ix == 17 || ix == 18) {
        trimmedLength--;
        trailingZeroBits += huffmanCode.codeLengths[ix];
        if (ix == 17) {
          trailingZeroBits += 3;
        } else if (ix == 18) {
          trailingZeroBits += 7;
        }
      } else {
        break;
      }
    }
    final writeTrimmedLength = trimmedLength > 1 && trailingZeroBits > 12;
    final length = writeTrimmedLength ? trimmedLength : numTokens;
    bw.putBits(writeTrimmedLength ? 1 : 0, 1);
    if (writeTrimmedLength) {
      if (trimmedLength == 2) {
        bw.putBits(0, 3 + 2);
      } else {
        final nbits = bitsLog2Floor(trimmedLength - 2);
        final nbitpairs = nbits ~/ 2 + 1;
        bw.putBits(nbitpairs - 1, 3);
        bw.putBits(trimmedLength - 2, nbitpairs * 2);
      }
    }
    _storeHuffmanTreeToBitMask(bw, tokens, length, huffmanCode);
  }
}

void _storeHuffmanCode(Vp8lBitWriter bw, HuffmanTreeCode huffmanCode) {
  var count = 0;
  final symbols = [0, 0];
  const kMaxBits = 8;
  const kMaxSymbol = 1 << kMaxBits;
  for (var i = 0; i < huffmanCode.numSymbols && count < 3; i++) {
    if (huffmanCode.codeLengths[i] != 0) {
      if (count < 2) symbols[count] = i;
      count++;
    }
  }
  if (count == 0) {
    bw.putBits(0x01, 4);
  } else if (count <= 2 && symbols[0] < kMaxSymbol && symbols[1] < kMaxSymbol) {
    bw.putBits(1, 1);
    bw.putBits(count - 1, 1);
    if (symbols[0] <= 1) {
      bw.putBits(0, 1);
      bw.putBits(symbols[0], 1);
    } else {
      bw.putBits(1, 1);
      bw.putBits(symbols[0], 8);
    }
    if (count == 2) bw.putBits(symbols[1], 8);
  } else {
    _storeFullHuffmanCode(bw, huffmanCode);
  }
}

List<HuffmanTreeCode> _getHuffBitLengthsAndCodes(
  List<Vp8lHistogram> histogramImage,
) {
  final codes = <HuffmanTreeCode>[];
  for (final histo in histogramImage) {
    final c0 = HuffmanTreeCode(histogramNumCodes(histo.paletteCodeBits));
    final c1 = HuffmanTreeCode(256);
    final c2 = HuffmanTreeCode(256);
    final c3 = HuffmanTreeCode(256);
    final c4 = HuffmanTreeCode(_numDistanceCodes);
    createHuffmanTree(histo.literal, 15, c0);
    createHuffmanTree(histo.red, 15, c1);
    createHuffmanTree(histo.blue, 15, c2);
    createHuffmanTree(histo.alpha, 15, c3);
    createHuffmanTree(histo.distance, 15, c4);
    codes.addAll([c0, c1, c2, c3, c4]);
  }
  return codes;
}

void _storeImageToBitMask(
  Vp8lBitWriter bw,
  int width,
  int histoBits,
  BackwardRefs refs,
  Uint32List histogramSymbols,
  List<HuffmanTreeCode> huffmanCodes,
) {
  final histoXsize = histoBits != 0 ? subSampleSize(width, histoBits) : 1;
  final tileMask = histoBits == 0 ? 0 : -(1 << histoBits);
  var x = 0;
  var y = 0;
  var tileX = x & tileMask;
  var tileY = y & tileMask;
  var histogramIx = histogramSymbols[0];
  var codesOff = 5 * histogramIx;
  final prefix = [0, 0, 0];
  for (var i = 0; i < refs.length; i++) {
    if (tileX != (x & tileMask) || tileY != (y & tileMask)) {
      tileX = x & tileMask;
      tileY = y & tileMask;
      histogramIx =
          histogramSymbols[(y >> histoBits) * histoXsize + (x >> histoBits)];
      codesOff = 5 * histogramIx;
    }
    final mode = refs.mode(i);
    if (mode == modeLiteral) {
      final v = refs.arg(i);
      final g = (v >>> 8) & 0xff;
      final r = (v >>> 16) & 0xff;
      final b = v & 0xff;
      final a = (v >>> 24) & 0xff;
      final c0 = huffmanCodes[codesOff];
      bw.putBits(c0.codes[g], c0.codeLengths[g]);
      final c1 = huffmanCodes[codesOff + 1];
      bw.putBits(c1.codes[r], c1.codeLengths[r]);
      final c2 = huffmanCodes[codesOff + 2];
      bw.putBits(c2.codes[b], c2.codeLengths[b]);
      final c3 = huffmanCodes[codesOff + 3];
      bw.putBits(c3.codes[a], c3.codeLengths[a]);
    } else if (mode == modeCacheIdx) {
      final literalIx = 256 + _numLengthCodes + refs.arg(i);
      final c0 = huffmanCodes[codesOff];
      bw.putBits(c0.codes[literalIx], c0.codeLengths[literalIx]);
    } else {
      final distance = refs.arg(i);
      prefixEncode(refs.len(i), prefix);
      final c0 = huffmanCodes[codesOff];
      final ix = 256 + prefix[0];
      bw.putBits(c0.codes[ix], c0.codeLengths[ix]);
      bw.putBits(prefix[2], prefix[1]);
      prefixEncode(distance, prefix);
      final c4 = huffmanCodes[codesOff + 4];
      bw.putBits(c4.codes[prefix[0]], c4.codeLengths[prefix[0]]);
      bw.putBits(prefix[2], prefix[1]);
    }
    x += refs.len(i);
    while (x >= width) {
      x -= width;
      y++;
    }
  }
}

/// Encodes a sub-image (transform data, palette, meta Huffman image) with
/// a single Huffman group and no color cache.
void encodeImageNoHuffman(
  Vp8lBitWriter bw,
  Uint32List argb,
  int width,
  int height,
  int quality,
  bool lowEffort,
) {
  final hashChain = HashChain(width * height);
  hashChain.fill(quality, argb, width, height, lowEffort);
  final refs = BackwardRefs();
  getBackwardReferences(
    width,
    height,
    argb,
    quality,
    false,
    lz77Standard | lz77Rle,
    0,
    hashChain,
    refs,
  );
  final histo = Vp8lHistogram(0);
  histo.storeRefs(refs);
  final huffmanCodes = _getHuffBitLengthsAndCodes([histo]);
  bw.putBits(0, 1); // no color cache, no Huffman image
  for (var i = 0; i < 5; i++) {
    _storeHuffmanCode(bw, huffmanCodes[i]);
    _clearHuffmanTreeIfOnlyOneSymbol(huffmanCodes[i]);
  }
  _storeImageToBitMask(bw, width, 0, refs, Uint32List(1), huffmanCodes);
}

void _encodeImageInternal(
  Vp8lBitWriter bw,
  Uint32List argb,
  int width,
  int height,
  int quality,
  bool lowEffort,
  int lz77Types,
  int cacheBitsInit,
  int histogramBits,
) {
  final hashChain = HashChain(width * height);
  hashChain.fill(quality, argb, width, height, lowEffort);
  final refs = BackwardRefs();
  final cacheBits = getBackwardReferences(
    width,
    height,
    argb,
    quality,
    lowEffort,
    lz77Types,
    cacheBitsInit,
    hashChain,
    refs,
  );
  final histogramImageXysize =
      subSampleSize(width, histogramBits) *
      subSampleSize(height, histogramBits);
  final histogramArgb = Uint32List(histogramImageXysize);
  final histogramImage = getHistoImageSymbols(
    width,
    height,
    refs,
    quality,
    lowEffort,
    histogramBits,
    cacheBits,
    histogramArgb,
  );
  final huffmanCodes = _getHuffBitLengthsAndCodes(histogramImage);
  // Color cache parameters.
  if (cacheBits > 0) {
    bw.putBits(1, 1);
    bw.putBits(cacheBits, 4);
  } else {
    bw.putBits(0, 1);
  }
  // Huffman image + meta huffman.
  var histogramImageSize = 0;
  for (var i = 0; i < histogramImageXysize; i++) {
    if (histogramArgb[i] >= histogramImageSize) {
      histogramImageSize = histogramArgb[i] + 1;
    }
    histogramArgb[i] <<= 8;
  }
  final writeHistogramImage = histogramImageSize > 1;
  bw.putBits(writeHistogramImage ? 1 : 0, 1);
  if (writeHistogramImage) {
    final bits = optimizeSampling(
      histogramArgb,
      width,
      height,
      histogramBits,
      _maxHuffmanBits,
    );
    bw.putBits(bits - 2, 3);
    encodeImageNoHuffman(
      bw,
      Uint32List.sublistView(
        histogramArgb,
        0,
        subSampleSize(width, bits) * subSampleSize(height, bits),
      ),
      subSampleSize(width, bits),
      subSampleSize(height, bits),
      quality,
      lowEffort,
    );
    // The literal image uses the (possibly subsampled) histogram bits.
    for (var i = 0; i < 5 * histogramImageSize; i++) {
      _storeHuffmanCode(bw, huffmanCodes[i]);
      _clearHuffmanTreeIfOnlyOneSymbol(huffmanCodes[i]);
    }
    _storeImageToBitMask(
      bw,
      width,
      bits,
      refs,
      _unpackSymbols(histogramArgb),
      huffmanCodes,
    );
    return;
  }
  for (var i = 0; i < 5 * histogramImageSize; i++) {
    _storeHuffmanCode(bw, huffmanCodes[i]);
    _clearHuffmanTreeIfOnlyOneSymbol(huffmanCodes[i]);
  }
  _storeImageToBitMask(
    bw,
    width,
    histogramBits,
    refs,
    _unpackSymbols(histogramArgb),
    huffmanCodes,
  );
}

Uint32List _unpackSymbols(Uint32List packed) {
  final out = Uint32List(packed.length);
  for (var i = 0; i < packed.length; i++) {
    out[i] = (packed[i] >>> 8) & 0xffff;
  }
  return out;
}

//------------------------------------------------------------------------------
// Main entry points

/// Encodes an ARGB image stream (without the VP8L header) into [bw].
///
/// Used for both the main image and alpha planes (green channel).
void encodeVp8lStream(
  Vp8lBitWriter bw,
  Uint32List argbIn,
  int width,
  int height,
  Vp8lEncoderOptions options,
) {
  final method = options.method.clamp(0, 6);
  final quality = options.quality.clamp(0, 100);
  final lowEffort = method == 0;
  final exact = options.exact;
  if (!exact) {
    // Replace fully transparent pixels by 0 to help compression.
    final cleaned = Uint32List.fromList(argbIn);
    for (var i = 0; i < cleaned.length; i++) {
      if ((cleaned[i] & 0xff000000) == 0) cleaned[i] = 0;
    }
    argbIn = cleaned;
  }
  // Palette analysis.
  final paletteSorted = getColorPalette(argbIn);
  final usePalette = paletteSorted != null;
  final paletteSize = usePalette ? paletteSorted.length : 0;
  final histoBits = _getHistoBits(method, usePalette, width, height);
  final transformBits = _getTransformBits(method, histoBits);
  _EntropyIx entropyIx;
  var redAndBlueAlwaysZero = false;
  if (lowEffort) {
    entropyIx = usePalette ? _EntropyIx.palette : _EntropyIx.spatialSubGreen;
  } else {
    final a = _analyzeEntropy(
      argbIn,
      width,
      height,
      usePalette,
      paletteSize,
      transformBits,
    );
    entropyIx = a.entropyIx;
    redAndBlueAlwaysZero = a.redAndBlueAlwaysZero;
  }
  final doPalette = entropyIx == _EntropyIx.palette;
  final useSubtractGreen =
      entropyIx == _EntropyIx.subGreen ||
      entropyIx == _EntropyIx.spatialSubGreen;
  final usePredict =
      entropyIx == _EntropyIx.spatial ||
      entropyIx == _EntropyIx.spatialSubGreen;
  final useCrossColor = (lowEffort || doPalette)
      ? false
      : (redAndBlueAlwaysZero ? false : usePredict);
  var lz77Types = lz77Standard | lz77Rle;
  var cacheBitsMax = maxColorCacheBits;

  Uint32List argb;
  var currentWidth = width;
  if (doPalette) {
    final palette = paletteSortMinimizeDeltas(paletteSorted!);
    // Encode palette.
    final encodedPaletteSize =
        (palette[paletteSize - 1] == 0 && paletteSize > 17)
        ? paletteSize - 1
        : paletteSize;
    bw.putBits(1, 1);
    bw.putBits(3, 2); // COLOR_INDEXING_TRANSFORM
    bw.putBits(encodedPaletteSize - 1, 8);
    final tmpPalette = Uint32List(encodedPaletteSize);
    for (var i = encodedPaletteSize - 1; i >= 1; i--) {
      tmpPalette[i] = subPixels(palette[i], palette[i - 1]);
    }
    tmpPalette[0] = palette[0];
    encodeImageNoHuffman(bw, tmpPalette, encodedPaletteSize, 1, 20, lowEffort);
    final xbits = paletteSize <= 2
        ? 3
        : paletteSize <= 4
        ? 2
        : paletteSize <= 16
        ? 1
        : 0;
    argb = applyPalette(argbIn, width, height, palette, xbits);
    currentWidth = subSampleSize(width, xbits);
    if (paletteSize < (1 << maxColorCacheBits)) {
      cacheBitsMax = bitsLog2Floor(paletteSize) + 1;
    }
    if (paletteSize <= 16 && !lowEffort) {
      lz77Types = lz77Box;
    }
  } else {
    argb = Uint32List.fromList(argbIn);
  }
  if (useSubtractGreen) {
    bw.putBits(1, 1);
    bw.putBits(2, 2); // SUBTRACT_GREEN_TRANSFORM
    subtractGreenFromBlueAndRed(argb, 0, argb.length);
  }
  if (usePredict) {
    final bits = _clampBits(
      currentWidth,
      height,
      transformBits,
      _minTransformBits,
      maxTransformBits,
      _maxPredictorImageSize,
    );
    final image = residualImage(
      currentWidth,
      height,
      bits,
      lowEffort,
      argb,
      exact,
    );
    final bestBits = optimizeSampling(
      image,
      currentWidth,
      height,
      bits,
      maxTransformBits,
    );
    bw.putBits(1, 1);
    bw.putBits(0, 2); // PREDICTOR_TRANSFORM
    bw.putBits(bestBits - _minTransformBits, 3);
    final tw = subSampleSize(currentWidth, bestBits);
    final th = subSampleSize(height, bestBits);
    encodeImageNoHuffman(
      bw,
      Uint32List.sublistView(image, 0, tw * th),
      tw,
      th,
      quality,
      lowEffort,
    );
  }
  if (useCrossColor) {
    final image = colorSpaceTransform(
      currentWidth,
      height,
      transformBits,
      quality,
      argb,
    );
    final bestBits = optimizeSampling(
      image,
      currentWidth,
      height,
      transformBits,
      maxTransformBits,
    );
    bw.putBits(1, 1);
    bw.putBits(1, 2); // CROSS_COLOR_TRANSFORM
    bw.putBits(bestBits - _minTransformBits, 3);
    final tw = subSampleSize(currentWidth, bestBits);
    final th = subSampleSize(height, bestBits);
    encodeImageNoHuffman(
      bw,
      Uint32List.sublistView(image, 0, tw * th),
      tw,
      th,
      quality,
      lowEffort,
    );
  }
  bw.putBits(0, 1); // no more transforms
  if (lz77Types == lz77Box) {
    // Try both the standard and the box LZ77 and keep the smallest.
    final bw1 = Vp8lBitWriter(width * height ~/ 2 + 64);
    _encodeImageInternal(
      bw1,
      argb,
      currentWidth,
      height,
      quality,
      lowEffort,
      lz77Standard | lz77Rle,
      cacheBitsMax,
      histoBits,
    );
    final bw2 = Vp8lBitWriter(width * height ~/ 2 + 64);
    _encodeImageInternal(
      bw2,
      argb,
      currentWidth,
      height,
      quality,
      lowEffort,
      lz77Box,
      cacheBitsMax,
      histoBits,
    );
    final best = bw1.numBits <= bw2.numBits ? bw1 : bw2;
    _appendBits(bw, best);
  } else {
    _encodeImageInternal(
      bw,
      argb,
      currentWidth,
      height,
      quality,
      lowEffort,
      lz77Types,
      cacheBitsMax,
      histoBits,
    );
  }
}

void _appendBits(Vp8lBitWriter dst, Vp8lBitWriter src) {
  final nbits = src.numBits;
  final bytes = src.finish();
  var remaining = nbits;
  for (var i = 0; i < bytes.length && remaining > 0; i++) {
    final n = remaining >= 8 ? 8 : remaining;
    dst.putBits(bytes[i], n);
    remaining -= n;
  }
}

/// Encodes an ARGB image as a complete `VP8L` chunk payload.
Uint8List encodeVp8lChunk(
  Uint32List argb,
  int width,
  int height,
  bool hasAlpha,
  Vp8lEncoderOptions options,
) {
  final bw = Vp8lBitWriter(width * height ~/ 2 + 64);
  bw.putBits(vp8lMagicByte, 8);
  bw.putBits(width - 1, 14);
  bw.putBits(height - 1, 14);
  bw.putBits(hasAlpha ? 1 : 0, 1);
  bw.putBits(0, 3); // version
  encodeVp8lStream(bw, argb, width, height, options);
  return bw.finish();
}
