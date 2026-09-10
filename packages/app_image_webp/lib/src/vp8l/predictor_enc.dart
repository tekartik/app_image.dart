/// Forward spatial (predictor) and cross-color transforms for the VP8L
/// encoder.
library;

import 'dart:typed_data';

import 'entropy.dart';
import 'lossless_dsp.dart';

const _histoSize = 4 * 256;
const _kSpatialPredictorBias = 15 * log2Scale;
const _kPredLowEffort = 11;
const _kMaskAlpha = 0xff000000;
const _kNumPredModes = 14;

/// Maximum transform bits.
const maxTransformBits = 2 + (1 << 3) - 1;

int _predictionCostBias(Uint32List counts, int off, int weight0, int expVal) {
  const significantSymbols = 256 >> 4;
  const expDecayFactor = 6;
  var bits = (weight0 * counts[off]) * log2Scale;
  expVal *= log2Scale;
  for (var i = 1; i < significantSymbols; i++) {
    bits += divRound(expVal * (counts[off + i] + counts[off + 256 - i]), 100);
    expVal = divRound(expDecayFactor * expVal, 10);
  }
  return -divRound(bits, 10);
}

int _predictionCostSpatialHistogram(
  Uint32List accumulated,
  Uint32List tile,
  int mode,
  int leftMode,
  int aboveMode,
) {
  var retval = 0;
  for (var i = 0; i < 4; i++) {
    const kExpValue = 94;
    retval += _predictionCostBias(tile, i * 256, 1, kExpValue);
    retval += combinedShannonEntropy(tile, i * 256, accumulated, i * 256);
  }
  if (mode == leftMode) retval -= _kSpatialPredictorBias;
  if (mode == aboveMode) retval -= _kSpatialPredictorBias;
  return retval;
}

void _updateHisto(Uint32List histo, int off, int argb) {
  histo[off + ((argb >>> 24) & 0xff)]++;
  histo[off + 256 + ((argb >>> 16) & 0xff)]++;
  histo[off + 512 + ((argb >>> 8) & 0xff)]++;
  histo[off + 768 + (argb & 0xff)]++;
}

/// Computes residuals for pixels `[xStart, xEnd)` of row [y] with [mode].
///
/// [currentRow] and [upperRow] have `width + 1` entries (the extra entry is
/// the top-right context of the last pixel).
void _getResidual(
  int width,
  Uint32List upperRow,
  Uint32List currentRow,
  int mode,
  int xStart,
  int xEnd,
  int y,
  bool exact,
  Uint32List out,
  int outOff,
) {
  for (var x = xStart; x < xEnd; x++) {
    int pred;
    if (y == 0) {
      pred = x == 0 ? argbBlack : currentRow[x - 1];
    } else if (x == 0) {
      pred = upperRow[x];
    } else {
      pred = predict(mode, currentRow[x - 1], upperRow, x);
    }
    var residual = subPixels(currentRow[x], pred);
    if (!exact && (currentRow[x] & _kMaskAlpha) == 0) {
      residual &= _kMaskAlpha;
      currentRow[x] = pred & ~_kMaskAlpha;
      if (x == 0 && y != 0) upperRow[width] = currentRow[0];
    }
    out[outOff + x - xStart] = residual;
  }
}

/// Chooses a predictor mode per tile and replaces [argb] by residuals.
///
/// Returns the mode image (one entry per tile, mode in the green channel).
Uint32List residualImage(
  int width,
  int height,
  int bits,
  bool lowEffort,
  Uint32List argb,
  bool exact,
) {
  final tilesPerRow = subSampleSize(width, bits);
  final tilesPerCol = subSampleSize(height, bits);
  final image = Uint32List(tilesPerRow * tilesPerCol);
  if (lowEffort) {
    for (var i = 0; i < image.length; i++) {
      image[i] = argbBlack | (_kPredLowEffort << 8);
    }
  } else {
    _getBestPredictors(
      width,
      height,
      bits,
      argb,
      exact,
      image,
      tilesPerRow,
      tilesPerCol,
    );
  }
  _copyImageWithPrediction(width, height, bits, image, argb, lowEffort, exact);
  return image;
}

void _getBestPredictors(
  int width,
  int height,
  int bits,
  Uint32List argb,
  bool exact,
  Uint32List modes,
  int tilesPerRow,
  int tilesPerCol,
) {
  final accumulated = Uint32List(_histoSize);
  final histos = Uint32List(_kNumPredModes * _histoSize);
  final tileSize = 1 << bits;
  final upperRow = Uint32List(width + 1);
  final currentRow = Uint32List(width + 1);
  final residuals = Uint32List(tileSize);
  for (var tileY = 0; tileY < tilesPerCol; tileY++) {
    for (var tileX = 0; tileX < tilesPerRow; tileX++) {
      histos.fillRange(0, histos.length, 0);
      final startX = tileX << bits;
      final startY = tileY << bits;
      final maxY = tileSize < height - startY ? tileSize : height - startY;
      final maxX = tileSize < width - startX ? tileSize : width - startX;
      final haveLeft = startX > 0 ? 1 : 0;
      final contextStartX = startX - haveLeft;
      for (var mode = 0; mode < _kNumPredModes; mode++) {
        final histoOff = mode * _histoSize;
        var upper = upperRow;
        var current = currentRow;
        if (startY > 0) {
          final src = (startY - 1) * width + contextStartX;
          current.setRange(
            contextStartX,
            contextStartX + maxX + haveLeft + 1,
            argb,
            src,
          );
        }
        for (var relY = 0; relY < maxY; relY++) {
          final y = startY + relY;
          final tmp = upper;
          upper = current;
          current = tmp;
          final n = maxX + haveLeft + (y + 1 < height ? 1 : 0);
          current.setRange(
            contextStartX,
            contextStartX + n,
            argb,
            y * width + contextStartX,
          );
          _getResidual(
            width,
            upper,
            current,
            mode,
            startX,
            startX + maxX,
            y,
            true,
            residuals,
            0,
          );
          for (var relX = 0; relX < maxX; relX++) {
            _updateHisto(histos, histoOff, residuals[relX]);
          }
        }
      }
      // Pick the best mode.
      final leftMode = tileX > 0
          ? (modes[tileY * tilesPerRow + tileX - 1] >>> 8) & 0xff
          : 0xff;
      final aboveMode = tileY > 0
          ? (modes[(tileY - 1) * tilesPerRow + tileX] >>> 8) & 0xff
          : 0xff;
      var bestDiff = 0x1fffffffffffff;
      var bestMode = 0;
      for (var mode = 0; mode < _kNumPredModes; mode++) {
        final tile = Uint32List.sublistView(
          histos,
          mode * _histoSize,
          (mode + 1) * _histoSize,
        );
        final curDiff = _predictionCostSpatialHistogram(
          accumulated,
          tile,
          mode,
          leftMode,
          aboveMode,
        );
        if (curDiff < bestDiff) {
          bestDiff = curDiff;
          bestMode = mode;
        }
      }
      final bestOff = bestMode * _histoSize;
      for (var i = 0; i < _histoSize; i++) {
        accumulated[i] += histos[bestOff + i];
      }
      modes[tileY * tilesPerRow + tileX] = argbBlack | (bestMode << 8);
    }
  }
}

void _copyImageWithPrediction(
  int width,
  int height,
  int bits,
  Uint32List modes,
  Uint32List argb,
  bool lowEffort,
  bool exact,
) {
  final tilesPerRow = subSampleSize(width, bits);
  var upperRow = Uint32List(width + 1);
  var currentRow = Uint32List(width + 1);
  for (var y = 0; y < height; y++) {
    final tmp = upperRow;
    upperRow = currentRow;
    currentRow = tmp;
    final n = width + (y + 1 < height ? 1 : 0);
    currentRow.setRange(0, n, argb, y * width);
    if (lowEffort) {
      _getResidual(
        width,
        upperRow,
        currentRow,
        _kPredLowEffort,
        0,
        width,
        y,
        true,
        argb,
        y * width,
      );
    } else {
      var x = 0;
      while (x < width) {
        final mode =
            (modes[(y >> bits) * tilesPerRow + (x >> bits)] >>> 8) & 0xff;
        var xEnd = x + (1 << bits);
        if (xEnd > width) xEnd = width;
        _getResidual(
          width,
          upperRow,
          currentRow,
          mode,
          x,
          xEnd,
          y,
          exact,
          argb,
          y * width + x,
        );
        x = xEnd;
      }
    }
  }
}

/// Checks whether [image] can be subsampled further; returns the new bits
/// (possibly unchanged) and rewrites [image] in place.
int optimizeSampling(
  Uint32List image,
  int fullWidth,
  int fullHeight,
  int bits,
  int maxBits,
) {
  var width = subSampleSize(fullWidth, bits);
  var height = subSampleSize(fullHeight, bits);
  var bestBits = bits;
  while (bestBits < maxBits) {
    final newSquareSize = 1 << (bestBits + 1 - bits);
    var isGood = true;
    final squareSize = 1 << (bestBits - bits);
    for (var y = 0; y + squareSize < height; y += newSquareSize) {
      final a = y * width;
      final b = (y + squareSize) * width;
      for (var i = 0; i < width; i++) {
        if (image[a + i] != image[b + i]) {
          isGood = false;
          break;
        }
      }
      if (!isGood) break;
    }
    if (isGood) {
      bestBits++;
    } else {
      break;
    }
  }
  if (bestBits == bits) return bits;
  while (bestBits > bits) {
    var isGood = true;
    final squareSize = 1 << (bestBits - bits);
    for (var y = 0; isGood && y < height; y++) {
      for (var x = 0; isGood && x < width; x += squareSize) {
        final end = x + squareSize < width ? x + squareSize : width;
        for (var i = x + 1; i < end; i++) {
          if (image[y * width + i] != image[y * width + x]) {
            isGood = false;
            break;
          }
        }
      }
    }
    if (isGood) break;
    bestBits--;
  }
  if (bestBits == bits) return bits;
  final oldWidth = width;
  final squareSize = 1 << (bestBits - bits);
  width = subSampleSize(fullWidth, bestBits);
  height = subSampleSize(fullHeight, bestBits);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image[y * width + x] = image[squareSize * (y * oldWidth + x)];
    }
  }
  return bestBits;
}

//------------------------------------------------------------------------------
// Cross color transform.

int _predictionCostCrossColor(Uint32List accumulated, Uint32List counts) {
  const kExpValue = 240;
  return combinedShannonEntropy(counts, 0, accumulated, 0) +
      _predictionCostBias(counts, 0, 3, kExpValue);
}

int _transformColorRed(int greenToRed, int argb) {
  final green = (argb >>> 8) & 0xff;
  var newRed = (argb >>> 16) & 0xff;
  newRed -= colorTransformDelta(greenToRed, green);
  return newRed & 0xff;
}

int _transformColorBlue(int greenToBlue, int redToBlue, int argb) {
  final green = (argb >>> 8) & 0xff;
  final red = (argb >>> 16) & 0xff;
  var newBlue = argb & 0xff;
  newBlue -= colorTransformDelta(greenToBlue, green);
  newBlue -= colorTransformDelta(redToBlue, red);
  return newBlue & 0xff;
}

int _getPredictionCostCrossColorRed(
  Uint32List argb,
  int off,
  int stride,
  int tileWidth,
  int tileHeight,
  int prevXG2r,
  int prevYG2r,
  int greenToRed,
  Uint32List accumulatedRed,
) {
  final histo = Uint32List(256);
  for (var y = 0; y < tileHeight; y++) {
    final o = off + y * stride;
    for (var x = 0; x < tileWidth; x++) {
      histo[_transformColorRed(greenToRed, argb[o + x])]++;
    }
  }
  var curDiff = _predictionCostCrossColor(accumulatedRed, histo);
  if ((greenToRed & 0xff) == prevXG2r) curDiff -= 3 * log2Scale;
  if ((greenToRed & 0xff) == prevYG2r) curDiff -= 3 * log2Scale;
  if (greenToRed == 0) curDiff -= 3 * log2Scale;
  return curDiff;
}

int _getBestGreenToRed(
  Uint32List argb,
  int off,
  int stride,
  int tileWidth,
  int tileHeight,
  int prevXG2r,
  int prevYG2r,
  int quality,
  Uint32List accumulatedRed,
) {
  final kMaxIters = 4 + ((7 * quality) >> 8);
  var greenToRedBest = 0;
  var bestDiff = _getPredictionCostCrossColorRed(
    argb,
    off,
    stride,
    tileWidth,
    tileHeight,
    prevXG2r,
    prevYG2r,
    greenToRedBest,
    accumulatedRed,
  );
  for (var iter = 0; iter < kMaxIters; iter++) {
    final delta = 32 >> iter;
    for (var offset = -delta; offset <= delta; offset += 2 * delta) {
      final greenToRedCur = offset + greenToRedBest;
      final curDiff = _getPredictionCostCrossColorRed(
        argb,
        off,
        stride,
        tileWidth,
        tileHeight,
        prevXG2r,
        prevYG2r,
        greenToRedCur,
        accumulatedRed,
      );
      if (curDiff < bestDiff) {
        bestDiff = curDiff;
        greenToRedBest = greenToRedCur;
      }
    }
  }
  return greenToRedBest & 0xff;
}

int _getPredictionCostCrossColorBlue(
  Uint32List argb,
  int off,
  int stride,
  int tileWidth,
  int tileHeight,
  int prevXG2b,
  int prevXR2b,
  int prevYG2b,
  int prevYR2b,
  int greenToBlue,
  int redToBlue,
  Uint32List accumulatedBlue,
) {
  final histo = Uint32List(256);
  for (var y = 0; y < tileHeight; y++) {
    final o = off + y * stride;
    for (var x = 0; x < tileWidth; x++) {
      histo[_transformColorBlue(greenToBlue, redToBlue, argb[o + x])]++;
    }
  }
  var curDiff = _predictionCostCrossColor(accumulatedBlue, histo);
  if ((greenToBlue & 0xff) == prevXG2b) curDiff -= 3 * log2Scale;
  if ((greenToBlue & 0xff) == prevYG2b) curDiff -= 3 * log2Scale;
  if ((redToBlue & 0xff) == prevXR2b) curDiff -= 3 * log2Scale;
  if ((redToBlue & 0xff) == prevYR2b) curDiff -= 3 * log2Scale;
  if (greenToBlue == 0) curDiff -= 3 * log2Scale;
  if (redToBlue == 0) curDiff -= 3 * log2Scale;
  return curDiff;
}

const _kGreenRedToBlueNumAxis = 8;
const _kGreenRedToBlueMaxIters = 7;
const _offsets = [
  [0, -1],
  [0, 1],
  [-1, 0],
  [1, 0],
  [-1, -1],
  [-1, 1],
  [1, -1],
  [1, 1],
];
const _deltaLut = [16, 16, 8, 4, 2, 2, 2];

/// Returns `[greenToBlue, redToBlue]`.
List<int> _getBestGreenRedToBlue(
  Uint32List argb,
  int off,
  int stride,
  int tileWidth,
  int tileHeight,
  List<int> prevX,
  List<int> prevY,
  int quality,
  Uint32List accumulatedBlue,
) {
  final iters = quality < 25
      ? 1
      : quality > 50
      ? _kGreenRedToBlueMaxIters
      : 4;
  var greenToBlueBest = 0;
  var redToBlueBest = 0;
  var bestDiff = _getPredictionCostCrossColorBlue(
    argb,
    off,
    stride,
    tileWidth,
    tileHeight,
    prevX[1],
    prevX[2],
    prevY[1],
    prevY[2],
    greenToBlueBest,
    redToBlueBest,
    accumulatedBlue,
  );
  for (var iter = 0; iter < iters; iter++) {
    final delta = _deltaLut[iter];
    for (var axis = 0; axis < _kGreenRedToBlueNumAxis; axis++) {
      final greenToBlueCur = _offsets[axis][0] * delta + greenToBlueBest;
      final redToBlueCur = _offsets[axis][1] * delta + redToBlueBest;
      final curDiff = _getPredictionCostCrossColorBlue(
        argb,
        off,
        stride,
        tileWidth,
        tileHeight,
        prevX[1],
        prevX[2],
        prevY[1],
        prevY[2],
        greenToBlueCur,
        redToBlueCur,
        accumulatedBlue,
      );
      if (curDiff < bestDiff) {
        bestDiff = curDiff;
        greenToBlueBest = greenToBlueCur;
        redToBlueBest = redToBlueCur;
      }
    }
    if (delta == 2 && greenToBlueBest == 0 && redToBlueBest == 0) break;
  }
  return [greenToBlueBest & 0xff, redToBlueBest & 0xff];
}

/// Applies the forward cross-color transform per tile; returns the
/// multipliers image (one entry per tile).
Uint32List colorSpaceTransform(
  int width,
  int height,
  int bits,
  int quality,
  Uint32List argb,
) {
  final maxTileSize = 1 << bits;
  final tileXsize = subSampleSize(width, bits);
  final tileYsize = subSampleSize(height, bits);
  final image = Uint32List(tileXsize * tileYsize);
  final accumulatedRed = Uint32List(256);
  final accumulatedBlue = Uint32List(256);
  var prevX = [0, 0, 0]; // greenToRed, greenToBlue, redToBlue
  var prevY = [0, 0, 0];
  for (var tileY = 0; tileY < tileYsize; tileY++) {
    for (var tileX = 0; tileX < tileXsize; tileX++) {
      final tileXOffset = tileX * maxTileSize;
      final tileYOffset = tileY * maxTileSize;
      final allXMax = tileXOffset + maxTileSize < width
          ? tileXOffset + maxTileSize
          : width;
      final allYMax = tileYOffset + maxTileSize < height
          ? tileYOffset + maxTileSize
          : height;
      final offset = tileY * tileXsize + tileX;
      if (tileY != 0) {
        final code = image[offset - tileXsize];
        prevY = [code & 0xff, (code >>> 8) & 0xff, (code >>> 16) & 0xff];
      }
      final tileWidth = allXMax - tileXOffset;
      final tileHeight = allYMax - tileYOffset;
      final tileOff = tileYOffset * width + tileXOffset;
      final g2r = _getBestGreenToRed(
        argb,
        tileOff,
        width,
        tileWidth,
        tileHeight,
        prevX[0],
        prevY[0],
        quality,
        accumulatedRed,
      );
      final gb = _getBestGreenRedToBlue(
        argb,
        tileOff,
        width,
        tileWidth,
        tileHeight,
        prevX,
        prevY,
        quality,
        accumulatedBlue,
      );
      prevX = [g2r, gb[0], gb[1]];
      image[offset] = 0xff000000 | (gb[1] << 16) | (gb[0] << 8) | g2r;
      // Apply the transform to the tile.
      for (var y = tileYOffset; y < allYMax; y++) {
        final o = y * width;
        for (var x = tileXOffset; x < allXMax; x++) {
          argb[o + x] = transformColor(g2r, gb[0], gb[1], argb[o + x]);
        }
      }
      // Gather accumulated histogram data.
      for (var y = tileYOffset; y < allYMax; y++) {
        var ix = y * width + tileXOffset;
        final ixEnd = ix + allXMax - tileXOffset;
        for (; ix < ixEnd; ix++) {
          final pix = argb[ix];
          if (ix >= 2 && pix == argb[ix - 2] && pix == argb[ix - 1]) continue;
          if (ix >= width + 2 &&
              argb[ix - 2] == argb[ix - width - 2] &&
              argb[ix - 1] == argb[ix - width - 1] &&
              pix == argb[ix - width]) {
            continue;
          }
          accumulatedRed[(pix >>> 16) & 0xff]++;
          accumulatedBlue[pix & 0xff]++;
        }
      }
    }
  }
  return image;
}
