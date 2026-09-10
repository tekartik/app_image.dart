/// YUV <-> RGB conversions (BT.601, libwebp fixed-point flavor) and the
/// "fancy" chroma upsampler.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const _yuvFix = 16;
const _yuvHalf = 1 << (_yuvFix - 1);
const _yuvFix2 = 6;
const _yuvMask2 = (256 << _yuvFix2) - 1;

int _multHi(int v, int coeff) => (v * coeff) >> 8;

int _clip8(int v) =>
    (v & ~_yuvMask2) == 0 ? (v >> _yuvFix2) : (v < 0 ? 0 : 255);

/// Red from luma [y] and chroma [v].
int yuvToR(int y, int v) =>
    _clip8(_multHi(y, 19077) + _multHi(v, 26149) - 14234);

/// Green from luma [y] and chroma [u], [v].
int yuvToG(int y, int u, int v) =>
    _clip8(_multHi(y, 19077) - _multHi(u, 6419) - _multHi(v, 13320) + 8708);

/// Blue from luma [y] and chroma [u].
int yuvToB(int y, int u) =>
    _clip8(_multHi(y, 19077) + _multHi(u, 33050) - 17685);

void _storeRgba(Uint8List dst, int off, int y, int u, int v) {
  dst[off] = yuvToR(y, v);
  dst[off + 1] = yuvToG(y, u, v);
  dst[off + 2] = yuvToB(y, u);
  dst[off + 3] = 255;
}

/// Upsamples one pair of luma lines with bilinear ("fancy") chroma filtering.
///
/// [bottomY] may be null (then only the top line is produced). Chroma rows
/// [topU]/[topV] and [curU]/[curV] are the chroma lines above and at the
/// current position; they can be the same for the first/last line.
void upsampleLinePair(
  Uint8List yBuf,
  int topY,
  int? bottomY,
  Uint8List uBuf,
  Uint8List vBuf,
  int topUv,
  int curUv,
  Uint8List dst,
  int topDst,
  int? bottomDst,
  int len,
) {
  final lastPixelPair = (len - 1) >> 1;
  var tlU = uBuf[topUv];
  var tlV = vBuf[topUv];
  var lU = uBuf[curUv];
  var lV = vBuf[curUv];
  {
    final u0 = (3 * tlU + lU + 2) >> 2;
    final v0 = (3 * tlV + lV + 2) >> 2;
    _storeRgba(dst, topDst, yBuf[topY], u0, v0);
  }
  if (bottomY != null) {
    final u0 = (3 * lU + tlU + 2) >> 2;
    final v0 = (3 * lV + tlV + 2) >> 2;
    _storeRgba(dst, bottomDst!, yBuf[bottomY], u0, v0);
  }
  for (var x = 1; x <= lastPixelPair; x++) {
    final tU = uBuf[topUv + x];
    final tV = vBuf[topUv + x];
    final cU = uBuf[curUv + x];
    final cV = vBuf[curUv + x];
    final avgU = tlU + tU + lU + cU + 8;
    final avgV = tlV + tV + lV + cV + 8;
    final diag12U = (avgU + 2 * (tU + lU)) >> 3;
    final diag12V = (avgV + 2 * (tV + lV)) >> 3;
    final diag03U = (avgU + 2 * (tlU + cU)) >> 3;
    final diag03V = (avgV + 2 * (tlV + cV)) >> 3;
    {
      final u0 = (diag12U + tlU) >> 1;
      final v0 = (diag12V + tlV) >> 1;
      final u1 = (diag03U + tU) >> 1;
      final v1 = (diag03V + tV) >> 1;
      _storeRgba(dst, topDst + (2 * x - 1) * 4, yBuf[topY + 2 * x - 1], u0, v0);
      _storeRgba(dst, topDst + (2 * x) * 4, yBuf[topY + 2 * x], u1, v1);
    }
    if (bottomY != null) {
      final u0 = (diag03U + lU) >> 1;
      final v0 = (diag03V + lV) >> 1;
      final u1 = (diag12U + cU) >> 1;
      final v1 = (diag12V + cV) >> 1;
      _storeRgba(
        dst,
        bottomDst! + (2 * x - 1) * 4,
        yBuf[bottomY + 2 * x - 1],
        u0,
        v0,
      );
      _storeRgba(dst, bottomDst + (2 * x) * 4, yBuf[bottomY + 2 * x], u1, v1);
    }
    tlU = tU;
    tlV = tV;
    lU = cU;
    lV = cV;
  }
  if ((len & 1) == 0) {
    {
      final u0 = (3 * tlU + lU + 2) >> 2;
      final v0 = (3 * tlV + lV + 2) >> 2;
      _storeRgba(dst, topDst + (len - 1) * 4, yBuf[topY + len - 1], u0, v0);
    }
    if (bottomY != null) {
      final u0 = (3 * lU + tlU + 2) >> 2;
      final v0 = (3 * lV + tlV + 2) >> 2;
      _storeRgba(
        dst,
        bottomDst! + (len - 1) * 4,
        yBuf[bottomY + len - 1],
        u0,
        v0,
      );
    }
  }
}

/// Converts Y/U/V planes (4:2:0) to an RGBA buffer using fancy upsampling.
Uint8List yuvToRgba(
  Uint8List y,
  int yStride,
  Uint8List u,
  Uint8List v,
  int uvStride,
  int width,
  int height,
) {
  final dst = Uint8List(width * height * 4);
  final rgbaStride = width * 4;
  var curY = 0;
  var curUv = 0;
  var dstOff = 0;
  upsampleLinePair(y, curY, null, u, v, curUv, curUv, dst, dstOff, null, width);
  curY += yStride;
  dstOff += rgbaStride;
  var row = 1;
  for (; row + 1 < height; row += 2) {
    final topUv = curUv;
    curUv += uvStride;
    upsampleLinePair(
      y,
      curY,
      curY + yStride,
      u,
      v,
      topUv,
      curUv,
      dst,
      dstOff,
      dstOff + rgbaStride,
      width,
    );
    curY += 2 * yStride;
    dstOff += 2 * rgbaStride;
  }
  if (height > 1 && (height & 1) == 0) {
    upsampleLinePair(
      y,
      curY,
      null,
      u,
      v,
      curUv,
      curUv,
      dst,
      dstOff,
      null,
      width,
    );
  }
  return dst;
}

//------------------------------------------------------------------------------
// RGB -> YUV (encoder side)

int _clipUv(int uv, int rounding) {
  uv = (uv + rounding + (128 << (_yuvFix + 2))) >> (_yuvFix + 2);
  return (uv & ~0xff) == 0 ? uv : (uv < 0 ? 0 : 255);
}

/// Luma from 8-bit RGB (rounding is normally `yuvHalf`).
int rgbToY(int r, int g, int b, int rounding) {
  final luma = 16839 * r + 33059 * g + 6420 * b;
  return (luma + rounding + (16 << _yuvFix)) >> _yuvFix;
}

/// U from RGB values accumulated over four pixels.
int rgbToU(int r, int g, int b, int rounding) {
  final u = -9719 * r - 19081 * g + 28800 * b;
  return _clipUv(u, rounding);
}

/// V from RGB values accumulated over four pixels.
int rgbToV(int r, int g, int b, int rounding) {
  final v = 28800 * r - 24116 * g - 4684 * b;
  return _clipUv(v, rounding);
}

/// Rounding constant for [rgbToY].
const yuvHalf = _yuvHalf;

// Gamma correction tables (kGamma = 0.80) used for chroma averaging.
const _gammaFix = 12;
const _gammaTabFix = 7;
const _gammaTabSize = 1 << (_gammaFix - _gammaTabFix);
const _gammaScale = (1 << _gammaFix) - 1;
const _gammaTabScale = 1 << _gammaTabFix;
const _gammaTabRounder = 1 << _gammaTabFix >> 1;

final Uint16List _gammaToLinearTab = () {
  final t = Uint16List(256);
  for (var v = 0; v <= 255; v++) {
    t[v] = (math.pow(v / 255.0, 0.80) * _gammaScale + .5).toInt();
  }
  return t;
}();

final Int32List _linearToGammaTab = () {
  final t = Int32List(_gammaTabSize + 1);
  final scale = _gammaTabScale / _gammaScale;
  for (var v = 0; v <= _gammaTabSize; v++) {
    t[v] = (255.0 * math.pow(scale * v, 1.0 / 0.80) + .5).toInt();
  }
  return t;
}();

int _gammaToLinear(int v) => _gammaToLinearTab[v];

int _interpolate(int v) {
  final tabPos = v >> (_gammaTabFix + 2);
  final x = v & ((_gammaTabScale << 2) - 1);
  final v0 = _linearToGammaTab[tabPos];
  final v1 = _linearToGammaTab[tabPos + 1];
  return v1 * x + v0 * ((_gammaTabScale << 2) - x);
}

int _linearToGamma(int baseValue, int shift) {
  final y = _interpolate(baseValue << shift);
  return (y + _gammaTabRounder) >> _gammaTabFix;
}

/// Inverse alpha table: `(1 << 19) / a` for a in 1..1020, index 0 unused.
final Int32List _invAlpha = () {
  final t = Int32List(4 * 0xff + 1);
  for (var a = 1; a <= 4 * 0xff; a++) {
    t[a] = (1 << 19) ~/ a;
  }
  return t;
}();

int _linearToGammaWeighted(
  Uint8List rgba,
  int off,
  int step,
  int rgbStride,
  int channel,
  int totalA,
) {
  final o = off + channel;
  final sum =
      rgba[off + 3] * _gammaToLinear(rgba[o]) +
      rgba[off + step + 3] * _gammaToLinear(rgba[o + step]) +
      rgba[off + rgbStride + 3] * _gammaToLinear(rgba[o + rgbStride]) +
      rgba[off + rgbStride + step + 3] *
          _gammaToLinear(rgba[o + rgbStride + step]);
  // (sum * invAlpha) >> (19 - 2): sum < 2^22, invAlpha <= 2^19 -> fits.
  return _linearToGamma((sum * _invAlpha[totalA]) >> 17, 0);
}

int _sum4(Uint8List rgba, int o, int step, int rgbStride) => _linearToGamma(
  _gammaToLinear(rgba[o]) +
      _gammaToLinear(rgba[o + step]) +
      _gammaToLinear(rgba[o + rgbStride]) +
      _gammaToLinear(rgba[o + rgbStride + step]),
  0,
);

int _sum2(Uint8List rgba, int o, int rgbStride) => _linearToGamma(
  _gammaToLinear(rgba[o]) + _gammaToLinear(rgba[o + rgbStride]),
  1,
);

/// Result of an RGBA -> YUV 4:2:0 conversion.
class YuvaPlanes {
  /// Picture width.
  final int width;

  /// Picture height.
  final int height;

  /// Luma plane, `width * height`.
  final Uint8List y;

  /// U plane, `uvWidth * uvHeight`.
  final Uint8List u;

  /// V plane.
  final Uint8List v;

  /// Alpha plane (`width * height`) or null if the image is opaque.
  final Uint8List? a;

  /// Creates planes.
  YuvaPlanes(this.width, this.height, this.y, this.u, this.v, this.a);

  /// Chroma width.
  int get uvWidth => (width + 1) >> 1;

  /// Chroma height.
  int get uvHeight => (height + 1) >> 1;
}

/// Converts an RGBA image to Y/U/V (4:2:0) planes plus an optional alpha
/// plane, replicating libwebp's `WebPPictureARGBToYUVA` (gamma-corrected
/// chroma averaging, alpha-weighted when the image has transparency).
YuvaPlanes rgbaToYuva(
  Uint8List rgba,
  int width,
  int height, {
  bool keepAlpha = true,
}) {
  var hasAlpha = false;
  if (keepAlpha) {
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) {
        hasAlpha = true;
        break;
      }
    }
  }
  final uvWidth = (width + 1) >> 1;
  final uvHeight = (height + 1) >> 1;
  final y = Uint8List(width * height);
  final u = Uint8List(uvWidth * uvHeight);
  final v = Uint8List(uvWidth * uvHeight);
  final a = hasAlpha ? Uint8List(width * height) : null;
  final rgbStride = width * 4;
  final tmp = Int32List(4 * uvWidth);

  void convertRowToY(int rowOff, int dstY) {
    for (var i = 0, j = rowOff; i < width; i++, j += 4) {
      y[dstY + i] = rgbToY(rgba[j], rgba[j + 1], rgba[j + 2], _yuvHalf);
    }
  }

  void accumulate(int rowOff, int stride, bool rowsHaveAlpha) {
    var j = rowOff;
    var d = 0;
    for (var i = 0; i < (width >> 1); i++, j += 8, d += 4) {
      if (rowsHaveAlpha) {
        final aSum =
            rgba[j + 3] +
            rgba[j + 7] +
            rgba[j + stride + 3] +
            rgba[j + stride + 7];
        if (aSum == 4 * 0xff || aSum == 0) {
          tmp[d] = _sum4(rgba, j, 4, stride);
          tmp[d + 1] = _sum4(rgba, j + 1, 4, stride);
          tmp[d + 2] = _sum4(rgba, j + 2, 4, stride);
        } else {
          tmp[d] = _linearToGammaWeighted(rgba, j, 4, stride, 0, aSum);
          tmp[d + 1] = _linearToGammaWeighted(rgba, j, 4, stride, 1, aSum);
          tmp[d + 2] = _linearToGammaWeighted(rgba, j, 4, stride, 2, aSum);
        }
      } else {
        tmp[d] = _sum4(rgba, j, 4, stride);
        tmp[d + 1] = _sum4(rgba, j + 1, 4, stride);
        tmp[d + 2] = _sum4(rgba, j + 2, 4, stride);
      }
    }
    if ((width & 1) != 0) {
      if (rowsHaveAlpha) {
        final aSum = 2 * (rgba[j + 3] + rgba[j + stride + 3]);
        if (aSum == 4 * 0xff || aSum == 0) {
          tmp[d] = _sum2(rgba, j, stride);
          tmp[d + 1] = _sum2(rgba, j + 1, stride);
          tmp[d + 2] = _sum2(rgba, j + 2, stride);
        } else {
          tmp[d] = _linearToGammaWeighted(rgba, j, 0, stride, 0, aSum);
          tmp[d + 1] = _linearToGammaWeighted(rgba, j, 0, stride, 1, aSum);
          tmp[d + 2] = _linearToGammaWeighted(rgba, j, 0, stride, 2, aSum);
        }
      } else {
        tmp[d] = _sum2(rgba, j, stride);
        tmp[d + 1] = _sum2(rgba, j + 1, stride);
        tmp[d + 2] = _sum2(rgba, j + 2, stride);
      }
    }
  }

  void convertToUv(int dstUv) {
    for (var i = 0, d = 0; i < uvWidth; i++, d += 4) {
      u[dstUv + i] = rgbToU(tmp[d], tmp[d + 1], tmp[d + 2], _yuvHalf << 2);
      v[dstUv + i] = rgbToV(tmp[d], tmp[d + 1], tmp[d + 2], _yuvHalf << 2);
    }
  }

  bool extractAlpha(int rowOff, int dstA, int rows) {
    // Returns true if all alpha values are 0xff.
    var allOpaque = 0xff;
    for (var r = 0; r < rows; r++) {
      final src = rowOff + r * rgbStride;
      final dst = dstA + r * width;
      for (var i = 0, j = src + 3; i < width; i++, j += 4) {
        final av = rgba[j];
        a![dst + i] = av;
        allOpaque &= av;
      }
    }
    return allOpaque == 0xff;
  }

  var rowOff = 0;
  var dstY = 0;
  var dstUv = 0;
  var dstA = 0;
  for (var row = 0; row < (height >> 1); row++) {
    var rowsHaveAlpha = hasAlpha;
    convertRowToY(rowOff, dstY);
    convertRowToY(rowOff + rgbStride, dstY + width);
    dstY += 2 * width;
    if (hasAlpha) {
      rowsHaveAlpha = !extractAlpha(rowOff, dstA, 2);
      dstA += 2 * width;
    }
    accumulate(rowOff, rgbStride, rowsHaveAlpha);
    convertToUv(dstUv);
    dstUv += uvWidth;
    rowOff += 2 * rgbStride;
  }
  if ((height & 1) != 0) {
    var rowHasAlpha = hasAlpha;
    convertRowToY(rowOff, dstY);
    if (hasAlpha) {
      rowHasAlpha = !extractAlpha(rowOff, dstA, 1);
    }
    accumulate(rowOff, 0, rowHasAlpha);
    convertToUv(dstUv);
  }
  return YuvaPlanes(width, height, y, u, v, a);
}
