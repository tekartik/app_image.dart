/// LZ77 backward references for the VP8L encoder.
library;

import 'dart:typed_data';

import 'color_cache.dart';
import 'entropy.dart';
import 'histogram.dart';
import 'lossless_dsp.dart';

/// Literal pixel.
const modeLiteral = 0;

/// Color cache index.
const modeCacheIdx = 1;

/// Backward copy.
const modeCopy = 2;

/// Maximum color cache bits used by the encoder.
const maxColorCacheBits = 10;

const _hashBits = 18;
const _hashSize = 1 << _hashBits;
const _maxLengthBits = 12;
const _windowSizeBits = 20;

/// Maximum copy length.
const maxLength = (1 << _maxLengthBits) - 1;
const _windowSize = (1 << _windowSizeBits) - 120;
const _minLength = 4;

/// Growable list of pixel-or-copy symbols stored as parallel arrays.
class BackwardRefs {
  Uint8List _mode = Uint8List(1024);
  Uint16List _len = Uint16List(1024);
  Uint32List _arg = Uint32List(1024);
  int _size = 0;

  /// Number of symbols.
  int get length => _size;

  /// Removes all symbols.
  void clear() => _size = 0;

  void _grow() {
    final n = _mode.length * 2;
    _mode = Uint8List(n)..setRange(0, _size, _mode);
    _len = Uint16List(n)..setRange(0, _size, _len);
    _arg = Uint32List(n)..setRange(0, _size, _arg);
  }

  /// Appends a symbol.
  void add(int mode, int len, int arg) {
    if (_size == _mode.length) _grow();
    _mode[_size] = mode;
    _len[_size] = len;
    _arg[_size] = arg;
    _size++;
  }

  /// Mode of symbol [i].
  int mode(int i) => _mode[i];

  /// Length of symbol [i] (1 for literals and cache indices).
  int len(int i) => _len[i];

  /// ARGB value, cache index or distance of symbol [i].
  int arg(int i) => _arg[i];

  /// Replaces symbol [i].
  void set(int i, int mode, int len, int arg) {
    _mode[i] = mode;
    _len[i] = len;
    _arg[i] = arg;
  }

  /// Copies the content of [other] into this.
  void copyFrom(BackwardRefs other) {
    _size = 0;
    for (var i = 0; i < other._size; i++) {
      add(other._mode[i], other._len[i], other._arg[i]);
    }
  }
}

const _planeToCodeLut = [
  96, 73, 55, 39, 23, 13, 5, 1, 255, 255, 255, 255, 255, 255, 255, 255, //
  101, 78, 58, 42, 26, 16, 8, 2, 0, 3, 9, 17, 27, 43, 59, 79, //
  102, 86, 62, 46, 32, 20, 10, 6, 4, 7, 11, 21, 33, 47, 63, 87, //
  105, 90, 70, 52, 37, 28, 18, 14, 12, 15, 19, 29, 38, 53, 71, 91, //
  110, 99, 82, 66, 48, 35, 30, 24, 22, 25, 31, 36, 49, 67, 83, 100, //
  115, 108, 94, 76, 64, 50, 44, 40, 34, 41, 45, 51, 65, 77, 95, 109, //
  118, 113, 103, 92, 80, 68, 60, 56, 54, 57, 61, 69, 81, 93, 104, 114, //
  119, 116, 111, 106, 97, 88, 84, 74, 72, 75, 85, 89, 98, 107, 112, 117, //
];

/// Converts a pixel distance to a distance code (1-based).
int distanceToPlaneCode(int xsize, int dist) {
  final yoffset = dist ~/ xsize;
  final xoffset = dist - yoffset * xsize;
  if (xoffset <= 8 && yoffset < 8) {
    return _planeToCodeLut[yoffset * 16 + 8 - xoffset] + 1;
  } else if (xoffset > xsize - 8 && yoffset < 7) {
    return _planeToCodeLut[(yoffset + 1) * 16 + 8 + (xsize - xoffset)] + 1;
  }
  return dist + 120;
}

int _vectorMismatch(Uint32List argb, int a, int b, int length) {
  var matchLen = 0;
  while (matchLen < length && argb[a + matchLen] == argb[b + matchLen]) {
    matchLen++;
  }
  return matchLen;
}

int _findMatchLength(
  Uint32List argb,
  int a,
  int b,
  int bestLenMatch,
  int maxLimit,
) {
  if (argb[a + bestLenMatch] != argb[b + bestLenMatch]) return 0;
  return _vectorMismatch(argb, a, b, maxLimit);
}

/// Hash chain: best match (offset, length) for every pixel.
class HashChain {
  /// `(offset << 12) | length` per pixel.
  final Uint32List offsetLength;

  /// Creates a chain for [size] pixels.
  HashChain(int size) : offsetLength = Uint32List(size);

  /// Match offset at [pos].
  int offsetAt(int pos) => offsetLength[pos] >>> _maxLengthBits;

  /// Match length at [pos].
  int lengthAt(int pos) => offsetLength[pos] & ((1 << _maxLengthBits) - 1);

  static int _getPixPairHash64(int a0, int a1) {
    var key = mul32(a1, 0xc6a4a793);
    key = (key + mul32(a0, 0x5bd1e996)) & 0xffffffff;
    return key >>> (32 - _hashBits);
  }

  static int _maxItersForQuality(int quality) => 8 + (quality * quality) ~/ 128;

  static int _windowSizeForHashChain(int quality, int xsize) {
    final maxWindowSize = quality > 75
        ? _windowSize
        : quality > 50
        ? (xsize << 8)
        : quality > 25
        ? (xsize << 6)
        : (xsize << 4);
    return maxWindowSize > _windowSize ? _windowSize : maxWindowSize;
  }

  static int _maxFindCopyLength(int len) => len < maxLength ? len : maxLength;

  /// Computes the best matches for [argb] (`xsize * ysize` pixels).
  void fill(
    int quality,
    Uint32List argb,
    int xsize,
    int ysize,
    bool lowEffort,
  ) {
    final size = xsize * ysize;
    final iterMax = _maxItersForQuality(quality);
    final windowSize = _windowSizeForHashChain(quality, xsize);
    if (size <= 2) {
      offsetLength[0] = 0;
      offsetLength[size - 1] = 0;
      return;
    }
    final hashToFirstIndex = Int32List(_hashSize)..fillRange(0, _hashSize, -1);
    final chain = Int32List(size);
    var argbComp = argb[0] == argb[1];
    var pos = 0;
    while (pos < size - 2) {
      final argbCompNext = argb[pos + 1] == argb[pos + 2];
      if (argbComp && argbCompNext) {
        var len = 1;
        final color = argb[pos];
        while (pos + len + 2 < size && argb[pos + len + 2] == color) {
          len++;
        }
        if (len > maxLength) {
          chain.fillRange(pos, pos + len - maxLength, -1);
          pos += len - maxLength;
          len = maxLength;
        }
        while (len > 0) {
          final hashCode = _getPixPairHash64(color, len);
          len--;
          chain[pos] = hashToFirstIndex[hashCode];
          hashToFirstIndex[hashCode] = pos++;
        }
        argbComp = false;
      } else {
        final hashCode = _getPixPairHash64(argb[pos], argb[pos + 1]);
        chain[pos] = hashToFirstIndex[hashCode];
        hashToFirstIndex[hashCode] = pos++;
        argbComp = argbCompNext;
      }
    }
    chain[pos] = hashToFirstIndex[_getPixPairHash64(argb[pos], argb[pos + 1])];

    offsetLength[0] = 0;
    offsetLength[size - 1] = 0;
    var basePosition = size - 2;
    while (basePosition > 0) {
      final maxLen = _maxFindCopyLength(size - 1 - basePosition);
      var iter = iterMax;
      var bestLength = 0;
      var bestDistance = 0;
      final minPos = basePosition > windowSize ? basePosition - windowSize : 0;
      final lengthMax = maxLen < 256 ? maxLen : 256;
      pos = chain[basePosition];
      if (!lowEffort) {
        if (basePosition >= xsize) {
          final currLength = _findMatchLength(
            argb,
            basePosition - xsize,
            basePosition,
            bestLength,
            maxLen,
          );
          if (currLength > bestLength) {
            bestLength = currLength;
            bestDistance = xsize;
          }
          iter--;
        }
        final currLength = _findMatchLength(
          argb,
          basePosition - 1,
          basePosition,
          bestLength,
          maxLen,
        );
        if (currLength > bestLength) {
          bestLength = currLength;
          bestDistance = 1;
        }
        iter--;
        if (bestLength == maxLength) pos = minPos - 1;
      }
      var bestArgb = argb[basePosition + bestLength];
      for (; pos >= minPos && --iter > 0; pos = chain[pos]) {
        if (argb[pos + bestLength] != bestArgb) continue;
        final currLength = _vectorMismatch(argb, pos, basePosition, maxLen);
        if (bestLength < currLength) {
          bestLength = currLength;
          bestDistance = basePosition - pos;
          bestArgb = argb[basePosition + bestLength];
          if (bestLength >= lengthMax) break;
        }
      }
      var maxBasePosition = basePosition;
      while (true) {
        offsetLength[basePosition] =
            (bestDistance << _maxLengthBits) | bestLength;
        basePosition--;
        if (bestDistance == 0 || basePosition == 0) break;
        if (basePosition < bestDistance ||
            argb[basePosition - bestDistance] != argb[basePosition]) {
          break;
        }
        if (bestLength == maxLength &&
            bestDistance != 1 &&
            basePosition + maxLength < maxBasePosition) {
          break;
        }
        if (bestLength < maxLength) {
          bestLength++;
          maxBasePosition = basePosition;
        }
      }
    }
  }
}

void _addSingleLiteral(int pixel, ColorCache? cache, BackwardRefs refs) {
  if (cache != null) {
    final key = cache.index(pixel);
    if (cache.lookup(key) == pixel) {
      refs.add(modeCacheIdx, 1, key);
    } else {
      refs.add(modeLiteral, 1, pixel);
      cache.set(key, pixel);
    }
  } else {
    refs.add(modeLiteral, 1, pixel);
  }
}

void _backwardReferencesRle(
  int xsize,
  int ysize,
  Uint32List argb,
  int cacheBits,
  BackwardRefs refs,
) {
  final pixCount = xsize * ysize;
  final cache = cacheBits > 0 ? ColorCache(cacheBits) : null;
  refs.clear();
  _addSingleLiteral(argb[0], cache, refs);
  var i = 1;
  while (i < pixCount) {
    final maxLen = HashChain._maxFindCopyLength(pixCount - i);
    final rleLen = _findMatchLength(argb, i, i - 1, 0, maxLen);
    final prevRowLen = i < xsize
        ? 0
        : _findMatchLength(argb, i, i - xsize, 0, maxLen);
    if (rleLen >= prevRowLen && rleLen >= _minLength) {
      refs.add(modeCopy, rleLen, 1);
      i += rleLen;
    } else if (prevRowLen >= _minLength) {
      refs.add(modeCopy, prevRowLen, xsize);
      if (cache != null) {
        for (var k = 0; k < prevRowLen; k++) {
          cache.insert(argb[i + k]);
        }
      }
      i += prevRowLen;
    } else {
      _addSingleLiteral(argb[i], cache, refs);
      i++;
    }
  }
}

void _backwardReferencesLz77(
  int xsize,
  int ysize,
  Uint32List argb,
  int cacheBits,
  HashChain hashChain,
  BackwardRefs refs,
) {
  var iLastCheck = -1;
  final cache = cacheBits > 0 ? ColorCache(cacheBits) : null;
  final pixCount = xsize * ysize;
  refs.clear();
  var i = 0;
  while (i < pixCount) {
    var offset = hashChain.offsetAt(i);
    var len = hashChain.lengthAt(i);
    if (len >= _minLength) {
      final lenIni = len;
      var maxReach = 0;
      final jMax = (i + lenIni >= pixCount) ? pixCount - 1 : i + lenIni;
      iLastCheck = i > iLastCheck ? i : iLastCheck;
      for (var j = iLastCheck + 1; j <= jMax; j++) {
        final lenJ = hashChain.lengthAt(j);
        final reach = j + (lenJ >= _minLength ? lenJ : 1);
        if (reach > maxReach) {
          len = j - i;
          maxReach = reach;
          if (maxReach >= pixCount) break;
        }
      }
    } else {
      len = 1;
    }
    if (len == 1) {
      _addSingleLiteral(argb[i], cache, refs);
    } else {
      refs.add(modeCopy, len, offset);
      if (cache != null) {
        for (var j = i; j < i + len; j++) {
          cache.insert(argb[j]);
        }
      }
    }
    i += len;
  }
}

const _windowOffsetsSizeMax = 32;

void _backwardReferencesLz77Box(
  int xsize,
  int ysize,
  Uint32List argb,
  int cacheBits,
  HashChain hashChainBest,
  HashChain hashChain,
  BackwardRefs refs,
) {
  final pixCount = xsize * ysize;
  final windowOffsets = List<int>.filled(_windowOffsetsSizeMax, 0);
  final windowOffsetsNew = List<int>.filled(_windowOffsetsSizeMax, 0);
  var windowOffsetsSize = 0;
  var windowOffsetsNewSize = 0;
  final counts = Uint16List(pixCount);
  var bestOffsetPrev = -1;
  var bestLengthPrev = -1;
  counts[pixCount - 1] = 1;
  for (var i = pixCount - 2; i >= 0; i--) {
    if (argb[i] == argb[i + 1]) {
      counts[i] = counts[i + 1] + (counts[i + 1] != maxLength ? 1 : 0);
    } else {
      counts[i] = 1;
    }
  }
  for (var y = 0; y <= 6; y++) {
    for (var x = -6; x <= 6; x++) {
      final offset = y * xsize + x;
      if (offset <= 0) continue;
      final planeCode = distanceToPlaneCode(xsize, offset) - 1;
      if (planeCode >= _windowOffsetsSizeMax) continue;
      windowOffsets[planeCode] = offset;
    }
  }
  for (var i = 0; i < _windowOffsetsSizeMax; i++) {
    if (windowOffsets[i] == 0) continue;
    windowOffsets[windowOffsetsSize++] = windowOffsets[i];
  }
  for (var i = 0; i < windowOffsetsSize; i++) {
    var isReachable = false;
    for (var j = 0; j < windowOffsetsSize && !isReachable; j++) {
      isReachable |= windowOffsets[i] == windowOffsets[j] + 1;
    }
    if (!isReachable) {
      windowOffsetsNew[windowOffsetsNewSize++] = windowOffsets[i];
    }
  }
  hashChain.offsetLength[0] = 0;
  for (var i = 1; i < pixCount; i++) {
    var bestLength = hashChainBest.lengthAt(i);
    var bestOffset = 0;
    var doCompute = true;
    if (bestLength >= maxLength) {
      bestOffset = hashChainBest.offsetAt(i);
      for (var ind = 0; ind < windowOffsetsSize; ind++) {
        if (bestOffset == windowOffsets[ind]) {
          doCompute = false;
          break;
        }
      }
    }
    if (doCompute) {
      final usePrev = bestLengthPrev > 1 && bestLengthPrev < maxLength;
      final numInd = usePrev ? windowOffsetsNewSize : windowOffsetsSize;
      bestLength = usePrev ? bestLengthPrev - 1 : 0;
      bestOffset = usePrev ? bestOffsetPrev : 0;
      for (var ind = 0; ind < numInd; ind++) {
        var currLength = 0;
        var j = i;
        var jOffset = usePrev
            ? i - windowOffsetsNew[ind]
            : i - windowOffsets[ind];
        if (jOffset < 0 || argb[jOffset] != argb[i]) continue;
        do {
          final countsJOffset = counts[jOffset];
          final countsJ = counts[j];
          if (countsJOffset != countsJ) {
            currLength += countsJOffset < countsJ ? countsJOffset : countsJ;
            break;
          }
          currLength += countsJOffset;
          jOffset += countsJOffset;
          j += countsJOffset;
        } while (currLength <= maxLength &&
            j < pixCount &&
            argb[jOffset] == argb[j]);
        if (bestLength < currLength) {
          bestOffset = usePrev ? windowOffsetsNew[ind] : windowOffsets[ind];
          if (currLength >= maxLength) {
            bestLength = maxLength;
            break;
          } else {
            bestLength = currLength;
          }
        }
      }
    }
    if (bestLength <= _minLength) {
      hashChain.offsetLength[i] = 0;
      bestOffsetPrev = 0;
      bestLengthPrev = 0;
    } else {
      hashChain.offsetLength[i] = (bestOffset << _maxLengthBits) | bestLength;
      bestOffsetPrev = bestOffset;
      bestLengthPrev = bestLength;
    }
  }
  hashChain.offsetLength[0] = 0;
  _backwardReferencesLz77(xsize, ysize, argb, cacheBits, hashChain, refs);
}

void _backwardReferences2DLocality(int xsize, BackwardRefs refs) {
  for (var i = 0; i < refs.length; i++) {
    if (refs.mode(i) == modeCopy) {
      refs.set(
        i,
        modeCopy,
        refs.len(i),
        distanceToPlaneCode(xsize, refs.arg(i)),
      );
    }
  }
}

/// Evaluates the best color cache size (0 = disabled) for [refs].
int _calculateBestCacheSize(
  Uint32List argb,
  int quality,
  BackwardRefs refs,
  int cacheBitsMax,
) {
  cacheBitsMax = quality <= 25 ? 0 : cacheBitsMax;
  if (cacheBitsMax == 0) return 0;
  final hashers = List<ColorCache?>.filled(cacheBitsMax + 1, null);
  final histos = <Vp8lHistogram>[];
  for (var i = 0; i <= cacheBitsMax; i++) {
    histos.add(Vp8lHistogram(i));
    if (i > 0) hashers[i] = ColorCache(i);
  }
  var pos = 0;
  final prefix = [0, 0, 0];
  for (var r = 0; r < refs.length; r++) {
    final mode = refs.mode(r);
    if (mode == modeLiteral) {
      final pix = argb[pos++];
      final a = (pix >>> 24) & 0xff;
      final rr = (pix >>> 16) & 0xff;
      final g = (pix >>> 8) & 0xff;
      final b = pix & 0xff;
      var key = hashPix(pix, 32 - cacheBitsMax);
      histos[0].blue[b]++;
      histos[0].literal[g]++;
      histos[0].red[rr]++;
      histos[0].alpha[a]++;
      for (var i = cacheBitsMax; i >= 1; i--, key >>= 1) {
        final h = hashers[i]!;
        if (h.lookup(key) == pix) {
          histos[i].literal[256 + 24 + key]++;
        } else {
          h.set(key, pix);
          histos[i].blue[b]++;
          histos[i].literal[g]++;
          histos[i].red[rr]++;
          histos[i].alpha[a]++;
        }
      }
    } else {
      // Copy (refs created without cache never contain cache indices).
      var len = refs.len(r);
      var argbPrev = argb[pos] ^ 0xffffffff;
      prefixEncode(len, prefix);
      for (var i = 0; i <= cacheBitsMax; i++) {
        histos[i].literal[256 + prefix[0]]++;
      }
      do {
        final p = argb[pos];
        if (p != argbPrev) {
          var key = hashPix(p, 32 - cacheBitsMax);
          for (var i = cacheBitsMax; i >= 1; i--, key >>= 1) {
            hashers[i]!.colors[key] = p;
          }
          argbPrev = p;
        }
        pos++;
      } while (--len != 0);
    }
  }
  var bestBits = 0;
  var entropyMin = -1;
  for (var i = 0; i <= cacheBitsMax; i++) {
    final entropy = histos[i].estimateBits();
    if (i == 0 || entropy < entropyMin) {
      entropyMin = entropy;
      bestBits = i;
    }
  }
  return bestBits;
}

/// Rewrites [refs] (created without cache) using a color cache of [cacheBits].
void _backwardRefsWithLocalCache(
  Uint32List argb,
  int cacheBits,
  BackwardRefs refs,
) {
  var pixelIndex = 0;
  final cache = ColorCache(cacheBits);
  for (var i = 0; i < refs.length; i++) {
    if (refs.mode(i) == modeLiteral) {
      final argbLiteral = refs.arg(i);
      final ix = cache.contains(argbLiteral);
      if (ix >= 0) {
        refs.set(i, modeCacheIdx, 1, ix);
      } else {
        cache.insert(argbLiteral);
      }
      pixelIndex++;
    } else {
      final len = refs.len(i);
      for (var k = 0; k < len; k++) {
        cache.insert(argb[pixelIndex++]);
      }
    }
  }
}

/// LZ77 flavors to try.
const lz77Standard = 1;

/// Run-length flavor.
const lz77Rle = 2;

/// Box (2D window) flavor, for images with few colors.
const lz77Box = 4;

/// Computes the best backward references for [argb].
///
/// Returns the chosen color cache bits; the references are stored in [refs].
int getBackwardReferences(
  int width,
  int height,
  Uint32List argb,
  int quality,
  bool lowEffort,
  int lz77TypesToTry,
  int cacheBitsMax,
  HashChain hashChain,
  BackwardRefs refs,
) {
  if (lowEffort) {
    _backwardReferencesLz77(width, height, argb, 0, hashChain, refs);
    _backwardReferences2DLocality(width, refs);
    return 0;
  }
  final refsTmp = BackwardRefs();
  var bitCostBest = -1;
  var cacheBitsBest = 0;
  var found = false;
  for (
    var lz77Type = 1;
    lz77TypesToTry != 0;
    lz77TypesToTry &= ~lz77Type, lz77Type <<= 1
  ) {
    if ((lz77TypesToTry & lz77Type) == 0) continue;
    switch (lz77Type) {
      case lz77Rle:
        _backwardReferencesRle(width, height, argb, 0, refsTmp);
      case lz77Standard:
        _backwardReferencesLz77(width, height, argb, 0, hashChain, refsTmp);
      case lz77Box:
        final hashChainBox = HashChain(width * height);
        _backwardReferencesLz77Box(
          width,
          height,
          argb,
          0,
          hashChain,
          hashChainBox,
          refsTmp,
        );
    }
    final cacheBits = _calculateBestCacheSize(
      argb,
      quality,
      refsTmp,
      cacheBitsMax,
    );
    if (cacheBits > 0) {
      _backwardRefsWithLocalCache(argb, cacheBits, refsTmp);
    }
    final histo = Vp8lHistogram(cacheBits);
    histo.storeRefs(refsTmp);
    final bitCost = histo.estimateBits();
    if (!found || bitCost < bitCostBest) {
      found = true;
      refs.copyFrom(refsTmp);
      bitCostBest = bitCost;
      cacheBitsBest = cacheBits;
    }
  }
  _backwardReferences2DLocality(width, refs);
  return cacheBitsBest;
}
