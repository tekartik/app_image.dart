/// Pixel arithmetic and predictors shared by the VP8L encoder and decoder.
///
/// Pixels are packed as `0xAARRGGBB` in 32-bit unsigned integers.
library;

import '../int_utils.dart';

/// Opaque black.
const argbBlack = 0xff000000;

/// Adds two pixels channel by channel modulo 256.
int addPixels(int a, int b) {
  final alphaAndGreen = (a & 0xff00ff00) + (b & 0xff00ff00);
  final redAndBlue = (a & 0x00ff00ff) + (b & 0x00ff00ff);
  return (alphaAndGreen & 0xff00ff00) | (redAndBlue & 0x00ff00ff);
}

/// Subtracts [b] from [a] channel by channel modulo 256.
int subPixels(int a, int b) {
  final alphaAndGreen = 0x00ff00ff + (a & 0xff00ff00) - (b & 0xff00ff00);
  final redAndBlue = 0xff00ff00 + (a & 0x00ff00ff) - (b & 0x00ff00ff);
  return (alphaAndGreen & 0xff00ff00) | (redAndBlue & 0x00ff00ff);
}

/// Per-channel average of two pixels (rounding down).
int average2(int a, int b) => (((a ^ b) & 0xfefefefe) >>> 1) + (a & b);

/// `average2(average2(a, c), b)`.
int average3(int a, int b, int c) => average2(average2(a, c), b);

/// `average2(average2(a, b), average2(c, d))`.
int average4(int a, int b, int c, int d) =>
    average2(average2(a, b), average2(c, d));

int _clip255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// Per-channel `a + b - c`, clamped to [0, 255].
int clampedAddSubtractFull(int a, int b, int c) {
  var r = 0;
  for (var shift = 0; shift < 32; shift += 8) {
    final v =
        ((a >>> shift) & 0xff) +
        ((b >>> shift) & 0xff) -
        ((c >>> shift) & 0xff);
    r |= _clip255(v) << shift;
  }
  return r;
}

/// Per-channel `avg + (avg - c) / 2` where `avg = average2(a, b)`, clamped.
int clampedAddSubtractHalf(int a, int b, int c) {
  final avg = average2(a, b);
  var r = 0;
  for (var shift = 0; shift < 32; shift += 8) {
    final va = (avg >>> shift) & 0xff;
    final vc = (c >>> shift) & 0xff;
    // C integer division truncates toward zero.
    final v = va + (va - vc) ~/ 2;
    r |= _clip255(v) << shift;
  }
  return r;
}

/// Select predictor: returns [top] or [left] depending on gradient.
int selectPredictor(int top, int left, int topLeft) {
  var paMinusPb = 0;
  for (var shift = 0; shift < 32; shift += 8) {
    final ac = ((top >>> shift) & 0xff) - ((topLeft >>> shift) & 0xff);
    final bc = ((left >>> shift) & 0xff) - ((topLeft >>> shift) & 0xff);
    paMinusPb += bc.abs() - ac.abs();
  }
  return paMinusPb <= 0 ? top : left;
}

/// Returns the prediction for [mode] (0..13) given the left pixel, the row
/// above ([upper] indexed so that `upper[x]` is the top pixel) and [x].
///
/// Used for x >= 1 and y >= 1 (borders are handled by the caller).
int predict(int mode, int left, List<int> upper, int x) {
  switch (mode) {
    case 0:
      return argbBlack;
    case 1:
      return left;
    case 2:
      return upper[x];
    case 3:
      return upper[x + 1];
    case 4:
      return upper[x - 1];
    case 5:
      return average3(left, upper[x], upper[x + 1]);
    case 6:
      return average2(left, upper[x - 1]);
    case 7:
      return average2(left, upper[x]);
    case 8:
      return average2(upper[x - 1], upper[x]);
    case 9:
      return average2(upper[x], upper[x + 1]);
    case 10:
      return average4(left, upper[x - 1], upper[x], upper[x + 1]);
    case 11:
      return selectPredictor(upper[x], left, upper[x - 1]);
    case 12:
      return clampedAddSubtractFull(left, upper[x], upper[x - 1]);
    case 13:
      return clampedAddSubtractHalf(left, upper[x], upper[x - 1]);
    default:
      return argbBlack;
  }
}

/// Signed 8-bit interpretation of the low byte of [v].
int toS8(int v) {
  v &= 0xff;
  return v >= 128 ? v - 256 : v;
}

/// Color transform delta: `(colorPred * color) >> 5` with both as int8.
int colorTransformDelta(int colorPred, int color) =>
    sar(toS8(colorPred) * toS8(color), 5);

/// Adds green to red and blue (inverse of subtract-green) in place.
void addGreenToBlueAndRed(List<int> argb, int start, int end) {
  for (var i = start; i < end; i++) {
    final p = argb[i];
    final green = (p >>> 8) & 0xff;
    var redBlue = p & 0x00ff00ff;
    redBlue += (green << 16) | green;
    redBlue &= 0x00ff00ff;
    argb[i] = (p & 0xff00ff00) | redBlue;
  }
}

/// Subtracts green from red and blue in place.
void subtractGreenFromBlueAndRed(List<int> argb, int start, int end) {
  for (var i = start; i < end; i++) {
    final p = argb[i];
    final green = (p >>> 8) & 0xff;
    final newR = (((p >>> 16) & 0xff) - green) & 0xff;
    final newB = ((p & 0xff) - green) & 0xff;
    argb[i] = (p & 0xff00ff00) | (newR << 16) | newB;
  }
}

/// Applies the inverse cross-color transform with the given multipliers.
int transformColorInverse(
  int greenToRed,
  int greenToBlue,
  int redToBlue,
  int argb,
) {
  final green = (argb >>> 8) & 0xff;
  var red = (argb >>> 16) & 0xff;
  var blue = argb & 0xff;
  red = (red + colorTransformDelta(greenToRed, green)) & 0xff;
  blue += colorTransformDelta(greenToBlue, green);
  blue += colorTransformDelta(redToBlue, red);
  blue &= 0xff;
  return (argb & 0xff00ff00) | (red << 16) | blue;
}

/// Applies the forward cross-color transform with the given multipliers.
int transformColor(int greenToRed, int greenToBlue, int redToBlue, int argb) {
  final green = (argb >>> 8) & 0xff;
  final red = (argb >>> 16) & 0xff;
  var newRed = red;
  var newBlue = argb & 0xff;
  newRed = (newRed - colorTransformDelta(greenToRed, green)) & 0xff;
  newBlue -= colorTransformDelta(greenToBlue, green);
  newBlue -= colorTransformDelta(redToBlue, red);
  newBlue &= 0xff;
  return (argb & 0xff00ff00) | (newRed << 16) | newBlue;
}

/// 32-bit multiplication that is safe when compiled to JavaScript.
int mul32(int a, int b) {
  a &= 0xffffffff;
  b &= 0xffffffff;
  final lo = (a & 0xffff) * b;
  final hi = ((a >>> 16) * b) & 0xffff;
  return (lo + (hi << 16)) & 0xffffffff;
}

/// Hash used by the VP8L color cache: `(argb * 0x1e35a7bd) >> shift`.
int hashPix(int argb, int shift) => mul32(argb, 0x1e35a7bd) >>> shift;

/// `ceil(size / 2^bits)`.
int subSampleSize(int size, int bits) => (size + (1 << bits) - 1) >> bits;

/// `floor(log2(v))` for v > 0.
int bitsLog2Floor(int v) => v <= 0 ? 0 : v.bitLength - 1;
