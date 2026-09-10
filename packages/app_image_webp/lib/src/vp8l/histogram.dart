/// Symbol histograms and histogram clustering for the VP8L encoder.
library;

import 'dart:typed_data';

import 'backward_refs.dart';
import 'entropy.dart';
import 'lossless_dsp.dart';

/// Marker for a non trivial symbol.
const nonTrivialSym = 0xffff;

const _numLiteralCodes = 256;
const _numLengthCodes = 24;
const _numDistanceCodes = 40;

/// Number of literal codes given the color cache bits.
int histogramNumCodes(int cacheBits) =>
    _numLiteralCodes + _numLengthCodes + (cacheBits > 0 ? (1 << cacheBits) : 0);

/// Histogram of the 5 symbol streams of a tile.
class Vp8lHistogram {
  /// Green/length/cache codes.
  final Uint32List literal;

  /// Red codes.
  final Uint32List red = Uint32List(_numLiteralCodes);

  /// Blue codes.
  final Uint32List blue = Uint32List(_numLiteralCodes);

  /// Alpha codes.
  final Uint32List alpha = Uint32List(_numLiteralCodes);

  /// Distance prefix codes.
  final Uint32List distance = Uint32List(_numDistanceCodes);

  /// Color cache bits.
  final int paletteCodeBits;

  /// Unique symbol per stream (or [nonTrivialSym]).
  final trivialSymbol = List<int>.filled(5, nonTrivialSym);

  /// Total cached cost.
  int bitCost = 0;

  /// Cached per-stream costs.
  final costs = List<int>.filled(5, 0);

  /// Whether each stream is used.
  final isUsed = List<bool>.filled(5, true);

  /// Entropy bin index.
  int binId = 0;

  /// Creates an empty histogram with [paletteCodeBits] cache bits.
  Vp8lHistogram(this.paletteCodeBits)
    : literal = Uint32List(histogramNumCodes(paletteCodeBits));

  /// Resets all counts and statistics.
  void clear() {
    literal.fillRange(0, literal.length, 0);
    red.fillRange(0, 256, 0);
    blue.fillRange(0, 256, 0);
    alpha.fillRange(0, 256, 0);
    distance.fillRange(0, _numDistanceCodes, 0);
    for (var i = 0; i < 5; i++) {
      trivialSymbol[i] = nonTrivialSym;
      isUsed[i] = true;
      costs[i] = 0;
    }
    bitCost = 0;
  }

  /// Population of stream [index] (0 literal, 1 red, 2 blue, 3 alpha, 4 dist).
  Uint32List population(int index) {
    switch (index) {
      case 0:
        return literal;
      case 1:
        return red;
      case 2:
        return blue;
      case 3:
        return alpha;
      default:
        return distance;
    }
  }

  /// Copies [src] (same cache bits) into this.
  void copyFrom(Vp8lHistogram src) {
    literal.setAll(0, src.literal);
    red.setAll(0, src.red);
    blue.setAll(0, src.blue);
    alpha.setAll(0, src.alpha);
    distance.setAll(0, src.distance);
    for (var i = 0; i < 5; i++) {
      trivialSymbol[i] = src.trivialSymbol[i];
      isUsed[i] = src.isUsed[i];
      costs[i] = src.costs[i];
    }
    bitCost = src.bitCost;
    binId = src.binId;
  }

  /// Adds symbol [i] of [refs].
  void addSymbol(BackwardRefs refs, int i) {
    final mode = refs.mode(i);
    if (mode == modeLiteral) {
      final v = refs.arg(i);
      alpha[(v >>> 24) & 0xff]++;
      red[(v >>> 16) & 0xff]++;
      literal[(v >>> 8) & 0xff]++;
      blue[v & 0xff]++;
    } else if (mode == modeCacheIdx) {
      literal[_numLiteralCodes + _numLengthCodes + refs.arg(i)]++;
    } else {
      literal[_numLiteralCodes + prefixEncodeCode(refs.len(i))]++;
      distance[prefixEncodeCode(refs.arg(i))]++;
    }
  }

  /// Accumulates all symbols of [refs].
  void storeRefs(BackwardRefs refs) {
    for (var i = 0; i < refs.length; i++) {
      addSymbol(refs, i);
    }
  }

  /// Estimates the coded size (entropy + Huffman tree + extra bits).
  int estimateBits() {
    var cost = 0;
    for (var i = 0; i < 5; i++) {
      final p = population(i);
      cost += _populationCost(p, p.length, null, null);
    }
    cost +=
        (extraCost(literal, _numLiteralCodes, _numLengthCodes) +
            extraCost(distance, 0, _numDistanceCodes)) *
        log2Scale;
    return cost;
  }

  /// Computes per-stream costs and the total [bitCost].
  void computeCost() {
    final ts = [0];
    final iu = [false];
    for (var i = 0; i < 5; i++) {
      final p = population(i);
      costs[i] = _populationCost(p, p.length, ts, iu);
      trivialSymbol[i] = ts[0];
      isUsed[i] = iu[0];
    }
    bitCost = costs[0] + costs[1] + costs[2] + costs[3] + costs[4];
  }
}

int _populationCost(
  Uint32List population,
  int length,
  List<int>? trivialSym,
  List<bool>? isUsed,
) {
  final bitEntropy = BitEntropy();
  final stats = Streaks();
  getEntropyUnrefined(population, 0, length, bitEntropy, stats);
  if (trivialSym != null) {
    trivialSym[0] = bitEntropy.nonzeros == 1
        ? bitEntropy.nonzeroCode
        : nonTrivialSym;
  }
  if (isUsed != null) {
    isUsed[0] = stats.streaks[1][0] != 0 || stats.streaks[1][1] != 0;
  }
  return bitsEntropyRefine(bitEntropy) + finalHuffmanCost(stats);
}

int _getCombinedEntropy(Vp8lHistogram h1, Vp8lHistogram h2, int index) {
  final isH1Used = h1.isUsed[index];
  final isH2Used = h2.isUsed[index];
  final isTrivial =
      h1.trivialSymbol[index] != nonTrivialSym &&
      h1.trivialSymbol[index] == h2.trivialSymbol[index];
  if (isTrivial || !isH1Used || !isH2Used) {
    if (isH1Used) return h1.costs[index];
    return h2.costs[index];
  }
  final x = h1.population(index);
  final y = h2.population(index);
  final bitEntropy = BitEntropy();
  final stats = Streaks();
  getCombinedEntropyUnrefined(x, 0, y, 0, x.length, bitEntropy, stats);
  return bitsEntropyRefine(bitEntropy) + finalHuffmanCost(stats);
}

const _int64Max = 0x1fffffffffffff; // 2^53 - 1, JavaScript safe

int _saturateAdd(int a, int b) {
  if (b < 0 || a <= _int64Max - b) return b + a;
  return _int64Max;
}

/// Returns the combined cost if below [costThreshold], or -1.
int _getCombinedHistogramEntropy(
  Vp8lHistogram a,
  Vp8lHistogram b,
  int costThreshold,
  List<int> costs,
) {
  if (costThreshold <= 0) return -1;
  var cost = 0;
  for (var i = 0; i < 5; i++) {
    costs[i] = _getCombinedEntropy(a, b, i);
    cost += costs[i];
    if (cost >= costThreshold) return -1;
  }
  return cost;
}

void _histogramAdd(Vp8lHistogram h1, Vp8lHistogram h2, Vp8lHistogram hout) {
  for (var i = 0; i < 5; i++) {
    final p1 = h1.population(i);
    final p2 = h2.population(i);
    final pout = hout.population(i);
    final length = pout.length;
    if (identical(h2, hout)) {
      if (h1.isUsed[i]) {
        if (hout.isUsed[i]) {
          for (var k = 0; k < length; k++) {
            pout[k] += p1[k];
          }
        } else {
          pout.setAll(0, p1);
        }
      }
    } else {
      if (h1.isUsed[i]) {
        if (h2.isUsed[i]) {
          for (var k = 0; k < length; k++) {
            pout[k] = p1[k] + p2[k];
          }
        } else {
          pout.setAll(0, p1);
        }
      } else if (h2.isUsed[i]) {
        pout.setAll(0, p2);
      } else {
        pout.fillRange(0, length, 0);
      }
    }
  }
  for (var i = 0; i < 5; i++) {
    hout.trivialSymbol[i] = h1.trivialSymbol[i] == h2.trivialSymbol[i]
        ? h1.trivialSymbol[i]
        : nonTrivialSym;
    hout.isUsed[i] = h1.isUsed[i] || h2.isUsed[i];
  }
}

void _updateHistogramCost(int bitCost, List<int> costs, Vp8lHistogram h) {
  h.bitCost = bitCost;
  for (var i = 0; i < 5; i++) {
    h.costs[i] = costs[i];
  }
}

/// Performs out = a + b if the combined cost is below the threshold.
bool _histogramAddEval(
  Vp8lHistogram a,
  Vp8lHistogram b,
  Vp8lHistogram out,
  int costThreshold,
) {
  final sumCost = a.bitCost + b.bitCost;
  costThreshold = _saturateAdd(sumCost, costThreshold);
  final costs = List<int>.filled(5, 0);
  final bitCost = _getCombinedHistogramEntropy(a, b, costThreshold, costs);
  if (bitCost < 0) return false;
  _histogramAdd(a, b, out);
  _updateHistogramCost(bitCost, costs, out);
  return true;
}

/// Returns `C(a+b) - C(a)` if below the threshold, else null.
int? _histogramAddThresh(Vp8lHistogram a, Vp8lHistogram b, int costThreshold) {
  costThreshold = _saturateAdd(a.bitCost, costThreshold);
  final costs = List<int>.filled(5, 0);
  final cost = _getCombinedHistogramEntropy(a, b, costThreshold, costs);
  if (cost < 0) return null;
  return cost - a.bitCost;
}

const _numPartitions = 4;
const _binSize = _numPartitions * _numPartitions * _numPartitions;
const _maxHistoGreedy = 100;

int _getBinIdForEntropy(int min, int max, int val) {
  final range = max - min;
  if (range > 0) {
    final delta = val - min;
    return ((_numPartitions - 1e-6) * delta / range).toInt();
  }
  return 0;
}

void _histogramAnalyzeEntropyBin(List<Vp8lHistogram> histos, bool lowEffort) {
  var litMin = _int64Max, litMax = 0;
  var redMin = _int64Max, redMax = 0;
  var blueMin = _int64Max, blueMax = 0;
  for (final h in histos) {
    if (litMax < h.costs[0]) litMax = h.costs[0];
    if (litMin > h.costs[0]) litMin = h.costs[0];
    if (redMax < h.costs[1]) redMax = h.costs[1];
    if (redMin > h.costs[1]) redMin = h.costs[1];
    if (blueMax < h.costs[2]) blueMax = h.costs[2];
    if (blueMin > h.costs[2]) blueMin = h.costs[2];
  }
  for (final h in histos) {
    var binId = _getBinIdForEntropy(litMin, litMax, h.costs[0]);
    if (!lowEffort) {
      binId =
          binId * _numPartitions +
          _getBinIdForEntropy(redMin, redMax, h.costs[1]);
      binId =
          binId * _numPartitions +
          _getBinIdForEntropy(blueMin, blueMax, h.costs[2]);
    }
    h.binId = binId;
  }
}

void _histogramCombineEntropyBin(
  List<Vp8lHistogram> histos,
  Vp8lHistogram curCombo,
  int numBins,
  int combineCostFactor,
  bool lowEffort,
) {
  final binFirst = List<int>.filled(numBins, -1);
  final binFailures = List<int>.filled(numBins, 0);
  var idx = 0;
  while (idx < histos.length) {
    final binId = histos[idx].binId;
    final first = binFirst[binId];
    if (first == -1) {
      binFirst[binId] = idx;
      idx++;
    } else if (lowEffort) {
      _histogramAdd(histos[idx], histos[first], histos[first]);
      _removeAt(histos, idx);
    } else {
      final bitCost = histos[idx].bitCost;
      final bitCostThresh = -divRound(bitCost * combineCostFactor, 100);
      if (_histogramAddEval(
        histos[first],
        histos[idx],
        curCombo,
        bitCostThresh,
      )) {
        const maxCombineFailures = 32;
        var tryCombine =
            curCombo.trivialSymbol[1] != nonTrivialSym &&
            curCombo.trivialSymbol[2] != nonTrivialSym &&
            curCombo.trivialSymbol[3] != nonTrivialSym;
        if (!tryCombine) {
          tryCombine =
              histos[idx].trivialSymbol[1] == nonTrivialSym ||
              histos[idx].trivialSymbol[2] == nonTrivialSym ||
              histos[idx].trivialSymbol[3] == nonTrivialSym;
          tryCombine &=
              histos[first].trivialSymbol[1] == nonTrivialSym ||
              histos[first].trivialSymbol[2] == nonTrivialSym ||
              histos[first].trivialSymbol[3] == nonTrivialSym;
        }
        if (tryCombine || binFailures[binId] >= maxCombineFailures) {
          // Move the merged histogram to its final slot (swap objects).
          final tmp = histos[first];
          histos[first] = curCombo;
          curCombo = tmp;
          _removeAt(histos, idx);
        } else {
          binFailures[binId]++;
          idx++;
        }
      } else {
        idx++;
      }
    }
  }
  if (lowEffort) {
    for (final h in histos) {
      h.computeCost();
    }
  }
}

void _removeAt(List<Vp8lHistogram> histos, int i) {
  histos[i] = histos[histos.length - 1];
  histos.removeLast();
}

int _myRand(List<int> seed) {
  seed[0] = (seed[0] * 48271) % 2147483647;
  return seed[0];
}

class _HistogramPair {
  int idx1;
  int idx2;
  int costDiff = 0;
  int costCombo = 0;
  final costs = List<int>.filled(5, 0);
  _HistogramPair(this.idx1, this.idx2);
}

class _HistoQueue {
  final List<_HistogramPair> queue = [];
  final int maxSize;
  _HistoQueue(this.maxSize);
  int get size => queue.length;

  void popPair(int i) {
    queue[i] = queue[queue.length - 1];
    queue.removeLast();
  }

  void updateHead(int i) {
    if (queue[i].costDiff < queue[0].costDiff) {
      final tmp = queue[0];
      queue[0] = queue[i];
      queue[i] = tmp;
    }
  }

  static void fixPair(int badId, int goodId, _HistogramPair pair) {
    if (pair.idx1 == badId) pair.idx1 = goodId;
    if (pair.idx2 == badId) pair.idx2 = goodId;
    if (pair.idx1 > pair.idx2) {
      final tmp = pair.idx1;
      pair.idx1 = pair.idx2;
      pair.idx2 = tmp;
    }
  }

  static bool updatePair(
    Vp8lHistogram h1,
    Vp8lHistogram h2,
    int costThreshold,
    _HistogramPair pair,
  ) {
    final sumCost = h1.bitCost + h2.bitCost;
    costThreshold = _saturateAdd(sumCost, costThreshold);
    final cost = _getCombinedHistogramEntropy(
      h1,
      h2,
      costThreshold,
      pair.costs,
    );
    if (cost < 0) return false;
    pair.costCombo = cost;
    pair.costDiff = cost - sumCost;
    return true;
  }

  int push(List<Vp8lHistogram> histos, int idx1, int idx2, int threshold) {
    if (queue.length == maxSize) return 0;
    if (idx1 > idx2) {
      final tmp = idx2;
      idx2 = idx1;
      idx1 = tmp;
    }
    final pair = _HistogramPair(idx1, idx2);
    if (!updatePair(histos[idx1], histos[idx2], threshold, pair)) return 0;
    queue.add(pair);
    updateHead(queue.length - 1);
    return pair.costDiff;
  }
}

void _histogramCombineGreedy(List<Vp8lHistogram> histos) {
  final n = histos.length;
  final q = _HistoQueue(n * n);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      q.push(histos, i, j, 0);
    }
  }
  while (q.size > 0) {
    final idx1 = q.queue[0].idx1;
    final idx2 = q.queue[0].idx2;
    _histogramAdd(histos[idx2], histos[idx1], histos[idx1]);
    _updateHistogramCost(q.queue[0].costCombo, q.queue[0].costs, histos[idx1]);
    _removeAt(histos, idx2);
    var i = 0;
    while (i < q.size) {
      final p = q.queue[i];
      if (p.idx1 == idx1 ||
          p.idx2 == idx1 ||
          p.idx1 == idx2 ||
          p.idx2 == idx2) {
        q.popPair(i);
      } else {
        _HistoQueue.fixPair(histos.length, idx2, p);
        q.updateHead(i);
        i++;
      }
    }
    for (var k = 0; k < histos.length; k++) {
      if (k == idx1) continue;
      q.push(histos, idx1, k, 0);
    }
  }
}

/// Returns true if a greedy pass must follow.
bool _histogramCombineStochastic(
  List<Vp8lHistogram> histos,
  int minClusterSize,
) {
  if (histos.length < minClusterSize) return true;
  final seed = [1];
  var triesWithNoSuccess = 0;
  final outerIters = histos.length;
  final numTriesNoSuccess = outerIters ~/ 2;
  final q = _HistoQueue(9);
  for (
    var iter = 0;
    iter < outerIters &&
        histos.length >= minClusterSize &&
        ++triesWithNoSuccess < numTriesNoSuccess;
    iter++
  ) {
    var bestCost = q.size == 0 ? 0 : q.queue[0].costDiff;
    final randRange = (histos.length - 1) * histos.length;
    final numTries = histos.length ~/ 2;
    for (var j = 0; histos.length >= 2 && j < numTries; j++) {
      final tmp = _myRand(seed) % randRange;
      final idx1 = tmp ~/ (histos.length - 1);
      var idx2 = tmp % (histos.length - 1);
      if (idx2 >= idx1) idx2++;
      final currCost = q.push(histos, idx1, idx2, bestCost);
      if (currCost < 0) {
        bestCost = currCost;
        if (q.size == q.maxSize) break;
      }
    }
    if (q.size == 0) continue;
    final bestIdx1 = q.queue[0].idx1;
    final bestIdx2 = q.queue[0].idx2;
    _histogramAdd(histos[bestIdx2], histos[bestIdx1], histos[bestIdx1]);
    _updateHistogramCost(
      q.queue[0].costCombo,
      q.queue[0].costs,
      histos[bestIdx1],
    );
    _removeAt(histos, bestIdx2);
    var j = 0;
    while (j < q.size) {
      final p = q.queue[j];
      final isIdx1Best = p.idx1 == bestIdx1 || p.idx1 == bestIdx2;
      final isIdx2Best = p.idx2 == bestIdx1 || p.idx2 == bestIdx2;
      if (isIdx1Best && isIdx2Best) {
        q.popPair(j);
        continue;
      }
      if (isIdx1Best || isIdx2Best) {
        _HistoQueue.fixPair(bestIdx2, bestIdx1, p);
        // The histogram previously at index `histos.length` now lives at
        // `bestIdx2`.
        final h1 = p.idx1 == histos.length ? histos[bestIdx2] : histos[p.idx1];
        final h2 = p.idx2 == histos.length ? histos[bestIdx2] : histos[p.idx2];
        if (!_HistoQueue.updatePair(h1, h2, 0, p)) {
          q.popPair(j);
          continue;
        }
      }
      _HistoQueue.fixPair(histos.length, bestIdx2, p);
      q.updateHead(j);
      j++;
    }
    triesWithNoSuccess = 0;
  }
  return histos.length <= minClusterSize;
}

void _histogramRemap(
  List<Vp8lHistogram?> input,
  List<Vp8lHistogram> out,
  Uint32List symbols,
) {
  final inSize = input.length;
  final outSize = out.length;
  if (outSize > 1) {
    for (var i = 0; i < inSize; i++) {
      final h = input[i];
      if (h == null) {
        symbols[i] = i > 0 ? symbols[i - 1] : 0;
        continue;
      }
      var bestOut = 0;
      var bestBits = _int64Max;
      for (var k = 0; k < outSize; k++) {
        final curBits = _histogramAddThresh(out[k], h, bestBits);
        if (curBits != null) {
          bestBits = curBits;
          bestOut = k;
        }
      }
      symbols[i] = bestOut;
    }
  } else {
    for (var i = 0; i < inSize; i++) {
      symbols[i] = 0;
    }
  }
  for (final h in out) {
    h.clear();
  }
  for (var i = 0; i < inSize; i++) {
    final h = input[i];
    if (h == null) continue;
    _histogramAdd(h, out[symbols[i]], out[symbols[i]]);
  }
}

int _getCombineCostFactor(int histoSize, int quality) {
  var combineCostFactor = 16;
  if (quality < 90) {
    if (histoSize > 256) combineCostFactor ~/= 2;
    if (histoSize > 512) combineCostFactor ~/= 2;
    if (histoSize > 1024) combineCostFactor ~/= 2;
    if (quality <= 50) combineCostFactor ~/= 2;
  }
  return combineCostFactor;
}

/// Builds the histogram image: clusters per-tile histograms and returns
/// the final histograms; [histogramSymbols] receives the cluster index of
/// each tile.
List<Vp8lHistogram> getHistoImageSymbols(
  int xsize,
  int ysize,
  BackwardRefs refs,
  int quality,
  bool lowEffort,
  int histogramBits,
  int cacheBits,
  Uint32List histogramSymbols,
) {
  final histoXsize = histogramBits != 0
      ? subSampleSize(xsize, histogramBits)
      : 1;
  final histoYsize = histogramBits != 0
      ? subSampleSize(ysize, histogramBits)
      : 1;
  final imageHistoRawSize = histoXsize * histoYsize;
  final origHisto = List<Vp8lHistogram?>.generate(
    imageHistoRawSize,
    (_) => Vp8lHistogram(cacheBits),
  );
  // Build the histograms from backward references.
  {
    var x = 0;
    var y = 0;
    for (var i = 0; i < refs.length; i++) {
      final ix = histogramBits == 0
          ? 0
          : (y >> histogramBits) * histoXsize + (x >> histogramBits);
      origHisto[ix]!.addSymbol(refs, i);
      x += refs.len(i);
      while (x >= xsize) {
        x -= xsize;
        y++;
      }
    }
  }
  // Copy and analyze.
  final imageHisto = <Vp8lHistogram>[];
  for (var i = 0; i < imageHistoRawSize; i++) {
    final h = origHisto[i]!;
    h.computeCost();
    if (!h.isUsed[0] &&
        !h.isUsed[1] &&
        !h.isUsed[2] &&
        !h.isUsed[3] &&
        !h.isUsed[4]) {
      origHisto[i] = null;
    } else {
      final copy = Vp8lHistogram(cacheBits)..copyFrom(h);
      imageHisto.add(copy);
    }
  }
  final entropyCombineNumBins = lowEffort ? _numPartitions : _binSize;
  final entropyCombine =
      imageHisto.length > entropyCombineNumBins * 2 && quality < 100;
  if (entropyCombine) {
    final combineCostFactor = _getCombineCostFactor(imageHistoRawSize, quality);
    _histogramAnalyzeEntropyBin(imageHisto, lowEffort);
    _histogramCombineEntropyBin(
      imageHisto,
      Vp8lHistogram(cacheBits),
      entropyCombineNumBins,
      combineCostFactor,
      lowEffort,
    );
  }
  if (!lowEffort || !entropyCombine) {
    final thresholdSize =
        1 +
        divRound(
          quality * quality * quality * (_maxHistoGreedy - 1),
          100 * 100 * 100,
        );
    final doGreedy = _histogramCombineStochastic(imageHisto, thresholdSize);
    if (doGreedy) {
      _histogramCombineGreedy(imageHisto);
    }
  }
  _histogramRemap(origHisto, imageHisto, histogramSymbols);
  return imageHisto;
}
