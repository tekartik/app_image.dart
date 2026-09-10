/// Fixed-point entropy helpers shared by the VP8L encoder.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'lossless_dsp.dart';

/// Precision (bits) of the fixed-point log2 values.
const log2PrecisionBits = 23;

/// `2^log2PrecisionBits`, used as a multiplier (shifts would overflow
/// 32 bits when compiled to JavaScript).
const log2Scale = 1 << log2PrecisionBits;

const _logLookupIdxMax = 256;
const _approxLogWithCorrectionMax = 65536;
const _approxLogMax = 4096;
const _log2ReciprocalFixed = 12102203;
const _log2ReciprocalFixedDouble = 12102203.161561485379934310913085937500;

/// `round(2^23 * log2(i))` for i < 256.
final Int32List kLog2Table = () {
  final t = Int32List(_logLookupIdxMax);
  for (var i = 1; i < _logLookupIdxMax; i++) {
    t[i] = ((1 << log2PrecisionBits) * math.log(i) / math.ln2).round();
  }
  return t;
}();

/// `round(2^23 * i * log2(i))` for i < 256.
final List<int> kSLog2Table = () {
  final t = List<int>.filled(_logLookupIdxMax, 0);
  for (var i = 1; i < _logLookupIdxMax; i++) {
    t[i] = ((1 << log2PrecisionBits) * math.log(i) / math.ln2 * i).round();
  }
  return t;
}();

int _fastSLog2Slow(int v) {
  if (v < _approxLogWithCorrectionMax) {
    final origV = v;
    final logCnt = bitsLog2Floor(v) - 7;
    final y = 1 << logCnt;
    v >>= logCnt;
    final correction = _log2ReciprocalFixed * (origV & (y - 1));
    return origV * (kLog2Table[v] + logCnt * log2Scale) + correction;
  } else {
    return (_log2ReciprocalFixedDouble * v * math.log(v) + .5).toInt();
  }
}

int _fastLog2Slow(int v) {
  if (v < _approxLogWithCorrectionMax) {
    final origV = v;
    final logCnt = bitsLog2Floor(v) - 7;
    final y = 1 << logCnt;
    v >>= logCnt;
    var log2 = kLog2Table[v] + logCnt * log2Scale;
    if (origV >= _approxLogMax) {
      final correction = _log2ReciprocalFixed * (origV & (y - 1));
      log2 += divRound(correction, origV);
    }
    return log2;
  } else {
    return (_log2ReciprocalFixedDouble * math.log(v) + .5).toInt();
  }
}

/// `v * log2(v)` in fixed point.
int fastSLog2(int v) =>
    v < _logLookupIdxMax ? kSLog2Table[v] : _fastSLog2Slow(v);

/// `log2(v)` in fixed point.
int fastLog2(int v) => v < _logLookupIdxMax ? kLog2Table[v] : _fastLog2Slow(v);

/// Rounded division of integers.
int divRound(int a, int b) =>
    ((a < 0) == (b < 0)) ? ((a + b ~/ 2) ~/ b) : ((a - b ~/ 2) ~/ b);

/// Shannon entropy (fixed point) of the first [n] counts of [x].
int shannonEntropy(List<int> x, int off, int n) {
  var retval = 0;
  var sumX = 0;
  for (var i = 0; i < n; i++) {
    final v = x[off + i];
    if (v != 0) {
      sumX += v;
      retval += fastSLog2(v);
    }
  }
  return fastSLog2(sumX) - retval;
}

/// Combined entropy of {X} and {X+Y} (256 entries each).
int combinedShannonEntropy(List<int> x, int xOff, List<int> y, int yOff) {
  var retval = 0;
  var sumX = 0;
  var sumXY = 0;
  for (var i = 0; i < 256; i++) {
    final xv = x[xOff + i];
    if (xv != 0) {
      final xy = xv + y[yOff + i];
      sumX += xv;
      retval += fastSLog2(xv);
      sumXY += xy;
      retval += fastSLog2(xy);
    } else {
      final yv = y[yOff + i];
      if (yv != 0) {
        sumXY += yv;
        retval += fastSLog2(yv);
      }
    }
  }
  return fastSLog2(sumX) + fastSLog2(sumXY) - retval;
}

/// Bit-entropy statistics of a population.
class BitEntropy {
  /// Entropy (fixed point).
  int entropy = 0;

  /// Sum of the population.
  int sum = 0;

  /// Number of non-zero elements.
  int nonzeros = 0;

  /// Maximum value.
  int maxVal = 0;

  /// Index of the last non-zero element (0xffff if none).
  int nonzeroCode = 0xffff;
}

/// Run statistics of a population (used to estimate the Huffman tree cost).
class Streaks {
  /// `counts[0]` zero streaks, `counts[1]` non-zero streaks (longer than 3).
  final counts = [0, 0];

  /// `streaks[zero/non-zero][short/long]` accumulated lengths.
  final streaks = [
    [0, 0],
    [0, 0],
  ];
}

/// Entropy of `array[0..n)` without refinement.
BitEntropy bitsEntropyUnrefined(List<int> array, int off, int n) {
  final e = BitEntropy();
  for (var i = 0; i < n; i++) {
    final v = array[off + i];
    if (v != 0) {
      e.sum += v;
      e.nonzeroCode = i;
      e.nonzeros++;
      e.entropy += fastSLog2(v);
      if (e.maxVal < v) e.maxVal = v;
    }
  }
  e.entropy = fastSLog2(e.sum) - e.entropy;
  return e;
}

void _entropyUnrefinedHelper(
  int val,
  int i,
  List<int> valPrev,
  List<int> iPrev,
  BitEntropy bitEntropy,
  Streaks stats,
) {
  final streak = i - iPrev[0];
  final vp = valPrev[0];
  if (vp != 0) {
    bitEntropy.sum += vp * streak;
    bitEntropy.nonzeros += streak;
    bitEntropy.nonzeroCode = iPrev[0];
    bitEntropy.entropy += fastSLog2(vp) * streak;
    if (bitEntropy.maxVal < vp) bitEntropy.maxVal = vp;
  }
  final nz = vp != 0 ? 1 : 0;
  stats.counts[nz] += streak > 3 ? 1 : 0;
  stats.streaks[nz][streak > 3 ? 1 : 0] += streak;
  valPrev[0] = val;
  iPrev[0] = i;
}

/// Computes entropy and streak statistics of `x[0..length)`.
void getEntropyUnrefined(
  List<int> x,
  int off,
  int length,
  BitEntropy bitEntropy,
  Streaks stats,
) {
  final iPrev = [0];
  final xPrev = [x[off]];
  var i = 1;
  for (; i < length; i++) {
    final v = x[off + i];
    if (v != xPrev[0]) {
      _entropyUnrefinedHelper(v, i, xPrev, iPrev, bitEntropy, stats);
    }
  }
  _entropyUnrefinedHelper(0, i, xPrev, iPrev, bitEntropy, stats);
  bitEntropy.entropy = fastSLog2(bitEntropy.sum) - bitEntropy.entropy;
}

/// Same as [getEntropyUnrefined] for the sum of two populations.
void getCombinedEntropyUnrefined(
  List<int> x,
  int xOff,
  List<int> y,
  int yOff,
  int length,
  BitEntropy bitEntropy,
  Streaks stats,
) {
  final iPrev = [0];
  final xyPrev = [x[xOff] + y[yOff]];
  var i = 1;
  for (; i < length; i++) {
    final xy = x[xOff + i] + y[yOff + i];
    if (xy != xyPrev[0]) {
      _entropyUnrefinedHelper(xy, i, xyPrev, iPrev, bitEntropy, stats);
    }
  }
  _entropyUnrefinedHelper(0, i, xyPrev, iPrev, bitEntropy, stats);
  bitEntropy.entropy = fastSLog2(bitEntropy.sum) - bitEntropy.entropy;
}

/// Refines a bit entropy taking Huffman coding limits into account.
int bitsEntropyRefine(BitEntropy entropy) {
  int mix;
  if (entropy.nonzeros < 5) {
    if (entropy.nonzeros <= 1) return 0;
    if (entropy.nonzeros == 2) {
      return divRound(99 * (entropy.sum * log2Scale) + entropy.entropy, 100);
    }
    mix = entropy.nonzeros == 3 ? 950 : 700;
  } else {
    mix = 627;
  }
  var minLimit = (2 * entropy.sum - entropy.maxVal) * log2Scale;
  minLimit = divRound(mix * minLimit + (1000 - mix) * entropy.entropy, 1000);
  return entropy.entropy < minLimit ? minLimit : entropy.entropy;
}

/// Entropy of `array[0..n)` including the Huffman refinement.
int bitsEntropy(List<int> array, int off, int n) =>
    bitsEntropyRefine(bitsEntropyUnrefined(array, off, n));

int _initialHuffmanCost() {
  const kHuffmanCodeOfHuffmanCodeSize = 19 * 3;
  return kHuffmanCodeOfHuffmanCodeSize * log2Scale -
      divRound(91 * log2Scale, 10);
}

/// Estimated cost of storing a Huffman tree with the given streaks.
int finalHuffmanCost(Streaks stats) {
  var retval = _initialHuffmanCost();
  var retvalExtra = stats.counts[0] * 1600 + 240 * stats.streaks[0][1];
  retvalExtra += stats.counts[1] * 2640 + 720 * stats.streaks[1][1];
  retvalExtra += 1840 * stats.streaks[0][0];
  retvalExtra += 3360 * stats.streaks[1][0];
  return retval + retvalExtra * (1 << (log2PrecisionBits - 10));
}

/// Extra bits cost of the length/distance prefix codes.
int extraCost(List<int> population, int off, int length) {
  var cost = population[off + 4] + population[off + 5];
  for (var i = 2; i < length ~/ 2 - 1; i++) {
    cost += i * (population[off + 2 * i + 2] + population[off + 2 * i + 3]);
  }
  return cost;
}

/// Prefix coding of a 1-based value: returns `[code, extraBits, extraBitsValue]`.
void prefixEncode(int distance, List<int> out) {
  distance--;
  if (distance < 2) {
    out[0] = distance;
    out[1] = 0;
    out[2] = 0;
    return;
  }
  final highestBit = bitsLog2Floor(distance);
  final secondHighestBit = (distance >> (highestBit - 1)) & 1;
  out[1] = highestBit - 1;
  out[2] = distance & ((1 << out[1]) - 1);
  out[0] = 2 * highestBit + secondHighestBit;
}

/// Prefix code of a 1-based value (without extra bits value).
int prefixEncodeCode(int distance) {
  distance--;
  if (distance < 2) return distance;
  final highestBit = bitsLog2Floor(distance);
  final secondHighestBit = (distance >> (highestBit - 1)) & 1;
  return 2 * highestBit + secondHighestBit;
}
