/// `ALPH` chunk handling: decoding and encoding of the alpha plane.
library;

import 'dart:typed_data';

import '../vp8l/bit_writer.dart';
import '../vp8l/vp8l_decoder.dart';
import '../vp8l/vp8l_encoder.dart';
import '../webp_image.dart';

/// No prediction filter.
const alphaFilterNone = 0;

/// Horizontal (left) prediction filter.
const alphaFilterHorizontal = 1;

/// Vertical (top) prediction filter.
const alphaFilterVertical = 2;

/// Gradient prediction filter.
const alphaFilterGradient = 3;

int _gradientPredictor(int a, int b, int c) {
  final g = a + b - c;
  return (g & ~0xff) == 0 ? g : (g < 0 ? 0 : 255);
}

/// Undoes prediction [filter] in place on [data] (`width * height` bytes).
void unfilterAlpha(int filter, Uint8List data, int width, int height) {
  if (filter == alphaFilterNone) return;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    final prev = row - width;
    if (y == 0 || filter == alphaFilterHorizontal) {
      var pred = y == 0 ? 0 : data[prev];
      for (var i = 0; i < width; i++) {
        pred = (pred + data[row + i]) & 0xff;
        data[row + i] = pred;
      }
    } else if (filter == alphaFilterVertical) {
      for (var i = 0; i < width; i++) {
        data[row + i] = (data[prev + i] + data[row + i]) & 0xff;
      }
    } else {
      var top = data[prev];
      var topLeft = top;
      var left = top;
      for (var i = 0; i < width; i++) {
        top = data[prev + i];
        left = (data[row + i] + _gradientPredictor(left, top, topLeft)) & 0xff;
        topLeft = top;
        data[row + i] = left;
      }
    }
  }
}

/// Applies prediction [filter] to [input], writing residuals to [out].
void filterAlpha(
  int filter,
  Uint8List input,
  int width,
  int height,
  Uint8List out,
) {
  if (filter == alphaFilterNone) {
    out.setAll(0, input);
    return;
  }
  // Top row: left prediction.
  out[0] = input[0];
  for (var i = 1; i < width; i++) {
    out[i] = (input[i] - input[i - 1]) & 0xff;
  }
  for (var y = 1; y < height; y++) {
    final row = y * width;
    final prev = row - width;
    if (filter == alphaFilterHorizontal) {
      out[row] = (input[row] - input[prev]) & 0xff;
      for (var i = 1; i < width; i++) {
        out[row + i] = (input[row + i] - input[row + i - 1]) & 0xff;
      }
    } else if (filter == alphaFilterVertical) {
      for (var i = 0; i < width; i++) {
        out[row + i] = (input[row + i] - input[prev + i]) & 0xff;
      }
    } else {
      out[row] = (input[row] - input[prev]) & 0xff;
      for (var i = 1; i < width; i++) {
        final pred = _gradientPredictor(
          input[row + i - 1],
          input[prev + i],
          input[prev + i - 1],
        );
        out[row + i] = (input[row + i] - pred) & 0xff;
      }
    }
  }
}

/// Decodes an `ALPH` chunk payload into a `width * height` alpha plane.
Uint8List decodeAlphaChunk(Uint8List data, int width, int height) {
  if (data.length <= 1) throw WebpFormatException('Truncated ALPH chunk');
  final method = data[0] & 3;
  final filter = (data[0] >> 2) & 3;
  final preProcessing = (data[0] >> 4) & 3;
  final rsrv = (data[0] >> 6) & 3;
  if (method > 1 || preProcessing > 1 || rsrv != 0) {
    throw WebpFormatException('Invalid ALPH header');
  }
  final payload = Uint8List.sublistView(data, 1);
  Uint8List plane;
  if (method == 0) {
    if (payload.length < width * height) {
      throw WebpFormatException('Truncated raw alpha data');
    }
    plane = Uint8List.fromList(payload.sublist(0, width * height));
  } else {
    plane = decodeVp8lAlphaPlane(payload, width, height);
  }
  unfilterAlpha(filter, plane, width, height);
  return plane;
}

/// Estimates the best prediction filter for an alpha plane (libwebp's
/// `WebPEstimateBestFilter`).
int estimateBestAlphaFilter(Uint8List data, int width, int height) {
  const smax = 16;
  final bins = List.generate(4, (_) => List<int>.filled(smax, 0));
  int sdiff(int a, int b) => (a - b).abs() >> 4;
  for (var j = 2; j < height - 1; j += 2) {
    final p = j * width;
    var mean = data[p];
    for (var i = 2; i < width - 1; i += 2) {
      final diff0 = sdiff(data[p + i], mean);
      final diff1 = sdiff(data[p + i], data[p + i - 1]);
      final diff2 = sdiff(data[p + i], data[p + i - width]);
      final gradPred = _gradientPredictor(
        data[p + i - 1],
        data[p + i - width],
        data[p + i - width - 1],
      );
      final diff3 = sdiff(data[p + i], gradPred);
      bins[alphaFilterNone][diff0] = 1;
      bins[alphaFilterHorizontal][diff1] = 1;
      bins[alphaFilterVertical][diff2] = 1;
      bins[alphaFilterGradient][diff3] = 1;
      mean = (3 * mean + data[p + i] + 2) >> 2;
    }
  }
  var bestFilter = alphaFilterNone;
  var bestScore = 0x7fffffff;
  for (var filter = 0; filter < 4; filter++) {
    var score = 0;
    for (var i = 0; i < smax; i++) {
      if (bins[filter][i] > 0) score += i;
    }
    if (score < bestScore) {
      bestScore = score;
      bestFilter = filter;
    }
  }
  return bestFilter;
}

/// Quantizes the alpha plane to [numLevels] levels (k-means), in place.
void quantizeAlphaLevels(Uint8List data, int numLevels) {
  if (numLevels < 2 || numLevels > 256) return;
  final freq = List<int>.filled(256, 0);
  var minS = 255;
  var maxS = 0;
  var numLevelsIn = 0;
  for (final v in data) {
    if (freq[v] == 0) numLevelsIn++;
    if (minS > v) minS = v;
    if (maxS < v) maxS = v;
    freq[v]++;
  }
  if (numLevelsIn <= numLevels) return;
  final invQLevel = List<double>.filled(256, 0);
  final qLevel = List<int>.filled(256, 0);
  for (var i = 0; i < numLevels; i++) {
    invQLevel[i] = minS + (maxS - minS) * i / (numLevels - 1);
  }
  qLevel[minS] = 0;
  qLevel[maxS] = numLevels - 1;
  var lastErr = 1e38;
  final errThreshold = 1e-4 * data.length;
  for (var iter = 0; iter < 6; iter++) {
    final qSum = List<double>.filled(256, 0);
    final qCount = List<double>.filled(256, 0);
    var slot = 0;
    for (var s = minS; s <= maxS; s++) {
      while (slot < numLevels - 1 &&
          2 * s > invQLevel[slot] + invQLevel[slot + 1]) {
        slot++;
      }
      if (freq[s] > 0) {
        qSum[slot] += s * freq[s];
        qCount[slot] += freq[s];
      }
      qLevel[s] = slot;
    }
    if (numLevels > 2) {
      for (slot = 1; slot < numLevels - 1; slot++) {
        final count = qCount[slot];
        if (count > 0) invQLevel[slot] = qSum[slot] / count;
      }
    }
    var err = 0.0;
    for (var s = minS; s <= maxS; s++) {
      final error = s - invQLevel[qLevel[s]];
      err += freq[s] * error * error;
    }
    if (lastErr - err < errThreshold) break;
    lastErr = err;
  }
  final map = Uint8List(256);
  for (var s = minS; s <= maxS; s++) {
    map[s] = (invQLevel[qLevel[s]] + .5).toInt();
  }
  for (var i = 0; i < data.length; i++) {
    data[i] = map[data[i]];
  }
}

/// Alpha filtering strategy.
enum AlphaFiltering {
  /// No prediction filter.
  none,

  /// Quick estimate of the best filter (default).
  fast,

  /// Try all filters and keep the smallest output.
  best,
}

Uint8List _encodeAlphaInternal(
  Uint8List alpha,
  int width,
  int height,
  int method,
  int filter,
  bool reduceLevels,
  int effortLevel,
) {
  Uint8List src;
  if (filter != alphaFilterNone) {
    src = Uint8List(width * height);
    filterAlpha(filter, alpha, width, height, src);
  } else {
    src = alpha;
  }
  Uint8List? output;
  if (method != 0) {
    final argb = Uint32List(width * height);
    for (var i = 0; i < argb.length; i++) {
      argb[i] = src[i] << 8;
    }
    final bw = Vp8lBitWriter(width * height ~/ 8 + 64);
    encodeVp8lStream(
      bw,
      argb,
      width,
      height,
      Vp8lEncoderOptions(
        method: effortLevel,
        quality: (!reduceLevels && effortLevel == 6) ? 100 : 8 * effortLevel,
        exact: true,
      ),
    );
    output = bw.finish();
    if (output.length > width * height) {
      method = 0;
      output = null;
    }
  }
  output ??= src;
  final out = Uint8List(1 + output.length);
  out[0] = method | (filter << 2) | ((reduceLevels ? 1 : 0) << 4);
  out.setRange(1, out.length, output);
  return out;
}

/// Encodes an alpha plane into an `ALPH` chunk payload.
///
/// [quality] below 100 quantizes the alpha levels (lossy alpha);
/// [method] 0 stores raw bytes, 1 uses lossless compression; [effortLevel]
/// is the compression method (0..6).
Uint8List encodeAlphaChunk(
  Uint8List alphaIn,
  int width,
  int height, {
  int quality = 100,
  int method = 1,
  AlphaFiltering filtering = AlphaFiltering.fast,
  int effortLevel = 4,
}) {
  final alpha = Uint8List.fromList(alphaIn);
  final reduceLevels = quality < 100;
  if (reduceLevels) {
    final alphaLevels = quality <= 70
        ? 2 + quality ~/ 5
        : 16 + (quality - 70) * 8;
    quantizeAlphaLevels(alpha, alphaLevels);
  }
  var filters = <int>[];
  if (method == 0) {
    filters = [alphaFilterNone];
  } else {
    switch (filtering) {
      case AlphaFiltering.none:
        filters = [alphaFilterNone];
      case AlphaFiltering.best:
        filters = [
          alphaFilterNone,
          alphaFilterHorizontal,
          alphaFilterVertical,
          alphaFilterGradient,
        ];
      case AlphaFiltering.fast:
        final tryFilterNone = effortLevel > 3;
        var numColors = 0;
        final seen = Uint8List(256);
        for (final v in alpha) {
          if (seen[v] == 0) {
            seen[v] = 1;
            numColors++;
          }
        }
        final filter = numColors <= 16
            ? alphaFilterNone
            : estimateBestAlphaFilter(alpha, width, height);
        filters = [filter];
        if ((tryFilterNone || numColors > 192) && filter != alphaFilterNone) {
          filters.add(alphaFilterNone);
        }
    }
  }
  Uint8List? best;
  for (final filter in filters) {
    final trial = _encodeAlphaInternal(
      alpha,
      width,
      height,
      method,
      filter,
      reduceLevels,
      effortLevel,
    );
    if (best == null || trial.length < best.length) best = trial;
  }
  return best!;
}
