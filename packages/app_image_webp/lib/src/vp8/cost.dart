/// Bit cost tables and residual cost estimation for the VP8 encoder.
library;

import 'dart:typed_data';

import 'tables.dart';

/// Last level with a variable (probability dependent) cost.
const maxVariableLevel = 67;

/// Maximum codable level.
const maxLevel = 2047;

/// Cost of coding [bit] with probability [proba], in 1/256 bit units.
int bitCost(int bit, int proba) =>
    bit == 0 ? entropyCost[proba] : entropyCost[255 - proba];

int _variableLevelCost(int level, Uint8List probas, int po) {
  var pattern = levelCodes[(level - 1) * 2];
  var bits = levelCodes[(level - 1) * 2 + 1];
  var cost = 0;
  for (var i = 2; pattern != 0; i++) {
    if ((pattern & 1) != 0) {
      cost += bitCost(bits & 1, probas[po + i]);
    }
    bits >>= 1;
    pattern >>= 1;
  }
  return cost;
}

/// Token probabilities, statistics and derived level costs.
class Vp8EncProba {
  /// Segment tree probabilities.
  final segments = Uint8List(3)..fillRange(0, 3, 255);

  /// Probability of a macroblock being skipped.
  int skipProba = 0;

  /// Whether the skip probability is used.
  bool useSkipProba = false;

  /// Number of skipped macroblocks recorded.
  int nbSkip = 0;

  /// Coefficient probabilities `[type][band][ctx][proba]` (flat).
  final coeffs = Uint8List.fromList(coeffsProba0);

  /// Statistics: `(total << 16) | nb` per probability (flat).
  final stats = Uint32List(numTypes * numBands * numCtx * numProbas);

  /// Level costs `[type][band][ctx][level 0..67]` (flat).
  final levelCost = Uint16List(
    numTypes * numBands * numCtx * (maxVariableLevel + 1),
  );

  /// Whether [levelCost] must be recomputed.
  bool dirty = true;

  /// Offset of `coeffs[type][band][ctx]`.
  static int probaOffset(int type, int band, int ctx) =>
      ((type * numBands + band) * numCtx + ctx) * numProbas;

  /// Offset of `levelCost[type][band][ctx]`.
  static int costOffset(int type, int band, int ctx) =>
      ((type * numBands + band) * numCtx + ctx) * (maxVariableLevel + 1);

  /// Offset of the costs for coefficient index [n] (band remapped).
  int remappedCostOffset(int type, int n, int ctx) =>
      costOffset(type, bands[n], ctx);

  /// Recomputes [levelCost] from [coeffs] if needed.
  void calculateLevelCosts() {
    if (!dirty) return;
    for (var ctype = 0; ctype < numTypes; ctype++) {
      for (var band = 0; band < numBands; band++) {
        for (var ctx = 0; ctx < numCtx; ctx++) {
          final po = probaOffset(ctype, band, ctx);
          final to = costOffset(ctype, band, ctx);
          final cost0 = ctx > 0 ? bitCost(1, coeffs[po]) : 0;
          final costBase = bitCost(1, coeffs[po + 1]) + cost0;
          levelCost[to] = bitCost(0, coeffs[po + 1]) + cost0;
          for (var v = 1; v <= maxVariableLevel; v++) {
            levelCost[to + v] = costBase + _variableLevelCost(v, coeffs, po);
          }
        }
      }
    }
    dirty = false;
  }

  /// Cost of coding [level] with the cost table at [to].
  int levelCostAt(int to, int level) =>
      levelFixedCosts[level] +
      levelCost[to + (level > maxVariableLevel ? maxVariableLevel : level)];

  /// Records [bit] into the statistics slot [s]. Returns [bit].
  int recordStats(int bit, int s) {
    var p = stats[s];
    if (p >= 0xfffe0000) {
      p = ((p + 1) >> 1) & 0x7fff7fff;
    }
    p += 0x00010000 + bit;
    stats[s] = p;
    return bit;
  }

  /// Resets the probabilities to their defaults.
  void reset() {
    coeffs.setAll(0, coeffsProba0);
    useSkipProba = false;
    segments.fillRange(0, 3, 255);
    dirty = true;
  }
}

/// A block of 16 coefficients to be coded or costed.
class Vp8Residual {
  /// First coefficient index (1 for i16 AC blocks).
  int first = 0;

  /// Index of the last non-zero coefficient (-1 if none).
  int last = -1;

  /// Coefficient type (0 i16-AC, 1 i16-DC, 2 chroma, 3 i4).
  int coeffType = 0;

  /// The coefficients (16 values at [coeffsOff]).
  Int16List coeffs = Int16List(16);

  /// Offset of the block inside [coeffs].
  int coeffsOff = 0;

  /// Sets the block and finds the last non-zero coefficient.
  void setCoeffs(Int16List c, int off) {
    coeffs = c;
    coeffsOff = off;
    last = -1;
    for (var n = 15; n >= 0; n--) {
      if (c[off + n] != 0) {
        last = n;
        break;
      }
    }
  }
}

/// Estimated cost of coding [res] in context [ctx0].
int getResidualCost(Vp8EncProba proba, int ctx0, Vp8Residual res) {
  var n = res.first;
  final type = res.coeffType;
  final p0 = proba.coeffs[Vp8EncProba.probaOffset(type, bands[n], ctx0)];
  var t = proba.remappedCostOffset(type, n, ctx0);
  var cost = ctx0 == 0 ? bitCost(1, p0) : 0;
  if (res.last < 0) {
    return bitCost(0, p0);
  }
  for (; n < res.last; n++) {
    final v = res.coeffs[res.coeffsOff + n].abs();
    final ctx = v >= 2 ? 2 : v;
    cost += proba.levelCostAt(t, v);
    t = proba.remappedCostOffset(type, n + 1, ctx);
  }
  {
    final v = res.coeffs[res.coeffsOff + n].abs();
    cost += proba.levelCostAt(t, v);
    if (n < 15) {
      final b = bands[n + 1];
      final ctx = v == 1 ? 1 : 2;
      final lastP0 = proba.coeffs[Vp8EncProba.probaOffset(type, b, ctx)];
      cost += bitCost(0, lastP0);
    }
  }
  return cost;
}

/// Records the coding statistics of [res]; returns 1 if non-zero.
int recordCoeffs(Vp8EncProba proba, int ctx, Vp8Residual res) {
  var n = res.first;
  final type = res.coeffType;
  var s = Vp8EncProba.probaOffset(type, bands[n], ctx);
  if (res.last < 0) {
    proba.recordStats(0, s);
    return 0;
  }
  while (n <= res.last) {
    int v;
    proba.recordStats(1, s);
    while ((v = res.coeffs[res.coeffsOff + n++]) == 0) {
      proba.recordStats(0, s + 1);
      s = Vp8EncProba.probaOffset(type, bands[n], 0);
    }
    proba.recordStats(1, s + 1);
    if (proba.recordStats(v.abs() > 1 ? 1 : 0, s + 2) == 0) {
      // v = -1 or 1
      s = Vp8EncProba.probaOffset(type, bands[n], 1);
    } else {
      v = v.abs();
      if (v > maxVariableLevel) v = maxVariableLevel;
      final bits = levelCodes[(v - 1) * 2 + 1];
      var pattern = levelCodes[(v - 1) * 2];
      for (var i = 0; (pattern >>= 1) != 0; i++) {
        final mask = 2 << i;
        if ((pattern & 1) != 0) {
          proba.recordStats((bits & mask) != 0 ? 1 : 0, s + 3 + i);
        }
      }
      s = Vp8EncProba.probaOffset(type, bands[n], 2);
    }
  }
  if (n < 16) proba.recordStats(0, s);
  return 1;
}
