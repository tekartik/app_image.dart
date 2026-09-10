/// Speed-critical VP8 routines: transforms, intra predictions and loop
/// filters, operating on byte buffers with an explicit stride.
library;

import 'dart:typed_data';

import '../int_utils.dart';

/// Stride of the macroblock work buffers.
const bps = 32;

/// Size of the decoder work buffer (Y/U/V samples and borders).
const yuvSize = bps * 17 + bps * 9;

/// Offset of the luma block in the work buffer.
const yOff = bps * 1 + 8;

/// Offset of the U block in the work buffer.
const uOff = yOff + bps * 16 + bps;

/// Offset of the V block in the work buffer.
const vOff = uOff + 16;

int _clip8(int v) => (v & ~0xff) == 0 ? v : (v < 0 ? 0 : 255);

int _mul1(int a) => sar(a * 20091, 16) + a;
int _mul2(int a) => sar(a * 35468, 16);

/// Clip table for values in [-255, 510].
final Uint8List _clip1 = () {
  final t = Uint8List(255 + 510 + 1);
  for (var i = -255; i <= 510; i++) {
    t[255 + i] = _clip8(i);
  }
  return t;
}();

/// Clips [v] (in [-255, 510]) to [0, 255].
int clip1(int v) => _clip1[255 + v];

/// Signed clip to [-1020, 1020] -> [-128, 127].
final Int8List _sclip1 = () {
  final t = Int8List(1020 + 1020 + 1);
  for (var i = -1020; i <= 1020; i++) {
    t[1020 + i] = i < -128 ? -128 : (i > 127 ? 127 : i);
  }
  return t;
}();

/// Signed clip to [-112, 112] -> [-16, 15].
final Int8List _sclip2 = () {
  final t = Int8List(112 + 112 + 1);
  for (var i = -112; i <= 112; i++) {
    t[112 + i] = i < -16 ? -16 : (i > 15 ? 15 : i);
  }
  return t;
}();

/// Absolute value table for [-255, 255].
final Uint8List _abs0 = () {
  final t = Uint8List(255 + 255 + 1);
  for (var i = -255; i <= 255; i++) {
    t[255 + i] = i < 0 ? -i : i;
  }
  return t;
}();

//------------------------------------------------------------------------------
// Transforms (paragraph 14.4)

/// Inverse DCT of 16 coefficients at `input[inOff..]`, added to
/// `dst[dstOff..]` (stride [stride]).
void transformOne(
  Int16List input,
  int inOff,
  Uint8List dst,
  int dstOff,
  int stride,
) {
  final c = Int32List(16);
  var t = 0;
  var i0 = inOff;
  for (var i = 0; i < 4; i++) {
    final a = input[i0] + input[i0 + 8];
    final b = input[i0] - input[i0 + 8];
    final cc = _mul2(input[i0 + 4]) - _mul1(input[i0 + 12]);
    final d = _mul1(input[i0 + 4]) + _mul2(input[i0 + 12]);
    c[t] = a + d;
    c[t + 1] = b + cc;
    c[t + 2] = b - cc;
    c[t + 3] = a - d;
    t += 4;
    i0++;
  }
  t = 0;
  var d0 = dstOff;
  for (var i = 0; i < 4; i++) {
    final dc = c[t] + 4;
    final a = dc + c[t + 8];
    final b = dc - c[t + 8];
    final cc = _mul2(c[t + 4]) - _mul1(c[t + 12]);
    final d = _mul1(c[t + 4]) + _mul2(c[t + 12]);
    dst[d0] = _clip8(dst[d0] + sar(a + d, 3));
    dst[d0 + 1] = _clip8(dst[d0 + 1] + sar(b + cc, 3));
    dst[d0 + 2] = _clip8(dst[d0 + 2] + sar(b - cc, 3));
    dst[d0 + 3] = _clip8(dst[d0 + 3] + sar(a - d, 3));
    t++;
    d0 += stride;
  }
}

/// Inverse transform when only the DC coefficient is non-zero.
void transformDc(
  Int16List input,
  int inOff,
  Uint8List dst,
  int dstOff,
  int stride,
) {
  final dc = sar(input[inOff] + 4, 3);
  for (var j = 0; j < 4; j++) {
    final o = dstOff + j * stride;
    for (var i = 0; i < 4; i++) {
      dst[o + i] = _clip8(dst[o + i] + dc);
    }
  }
}

/// Inverse Walsh-Hadamard transform of the 16 DC values (paragraph 14.3).
///
/// Output DCs are written at `out[outOff + 16 * n]`.
void transformWht(Int16List input, int inOff, Int16List out, int outOff) {
  final tmp = Int32List(16);
  for (var i = 0; i < 4; i++) {
    final a0 = input[inOff + i] + input[inOff + 12 + i];
    final a1 = input[inOff + 4 + i] + input[inOff + 8 + i];
    final a2 = input[inOff + 4 + i] - input[inOff + 8 + i];
    final a3 = input[inOff + i] - input[inOff + 12 + i];
    tmp[i] = a0 + a1;
    tmp[8 + i] = a0 - a1;
    tmp[4 + i] = a3 + a2;
    tmp[12 + i] = a3 - a2;
  }
  var o = outOff;
  for (var i = 0; i < 4; i++) {
    final dc = tmp[i * 4] + 3;
    final a0 = dc + tmp[3 + i * 4];
    final a1 = tmp[1 + i * 4] + tmp[2 + i * 4];
    final a2 = tmp[1 + i * 4] - tmp[2 + i * 4];
    final a3 = dc - tmp[3 + i * 4];
    out[o] = sar(a0 + a1, 3);
    out[o + 16] = sar(a3 + a2, 3);
    out[o + 32] = sar(a0 - a1, 3);
    out[o + 48] = sar(a3 - a2, 3);
    o += 64;
  }
}

//------------------------------------------------------------------------------
// Intra predictions (decoder flavor: reads borders from the buffer itself).

void _fill(Uint8List dst, int off, int value, int size, int stride) {
  for (var j = 0; j < size; j++) {
    dst.fillRange(off + j * stride, off + j * stride + size, value);
  }
}

void _trueMotion(Uint8List dst, int off, int size, int stride) {
  final top = off - stride;
  final topLeft = dst[top - 1];
  for (var y = 0; y < size; y++) {
    final o = off + y * stride;
    final base = dst[o - 1] - topLeft;
    for (var x = 0; x < size; x++) {
      dst[o + x] = clip1(base + dst[top + x]);
    }
  }
}

void _vertical(Uint8List dst, int off, int size, int stride) {
  final top = off - stride;
  for (var j = 0; j < size; j++) {
    dst.setRange(off + j * stride, off + j * stride + size, dst, top);
  }
}

void _horizontal(Uint8List dst, int off, int size, int stride) {
  for (var j = 0; j < size; j++) {
    final o = off + j * stride;
    dst.fillRange(o, o + size, dst[o - 1]);
  }
}

void _dc(
  Uint8List dst,
  int off,
  int size,
  int stride,
  int shift,
  bool hasTop,
  bool hasLeft,
) {
  int dc;
  if (hasTop && hasLeft) {
    dc = size;
    for (var j = 0; j < size; j++) {
      dc += dst[off - 1 + j * stride] + dst[off + j - stride];
    }
    dc >>= shift;
  } else if (hasTop) {
    dc = size >> 1;
    for (var i = 0; i < size; i++) {
      dc += dst[off + i - stride];
    }
    dc >>= shift - 1;
  } else if (hasLeft) {
    dc = size >> 1;
    for (var j = 0; j < size; j++) {
      dc += dst[off - 1 + j * stride];
    }
    dc >>= shift - 1;
  } else {
    dc = 0x80;
  }
  _fill(dst, off, dc, size, stride);
}

/// 16x16 luma prediction for [mode] (0..6, see `tables.dart`).
void predLuma16(int mode, Uint8List dst, int off, int stride) {
  switch (mode) {
    case 0:
      _dc(dst, off, 16, stride, 5, true, true);
    case 1:
      _trueMotion(dst, off, 16, stride);
    case 2:
      _vertical(dst, off, 16, stride);
    case 3:
      _horizontal(dst, off, 16, stride);
    case 4:
      _dc(dst, off, 16, stride, 5, false, true);
    case 5:
      _dc(dst, off, 16, stride, 5, true, false);
    default:
      _dc(dst, off, 16, stride, 5, false, false);
  }
}

/// 8x8 chroma prediction for [mode] (0..6).
void predChroma8(int mode, Uint8List dst, int off, int stride) {
  switch (mode) {
    case 0:
      _dc(dst, off, 8, stride, 4, true, true);
    case 1:
      _trueMotion(dst, off, 8, stride);
    case 2:
      _vertical(dst, off, 8, stride);
    case 3:
      _horizontal(dst, off, 8, stride);
    case 4:
      _dc(dst, off, 8, stride, 4, false, true);
    case 5:
      _dc(dst, off, 8, stride, 4, true, false);
    default:
      _dc(dst, off, 8, stride, 4, false, false);
  }
}

int _avg3(int a, int b, int c) => (a + 2 * b + c + 2) >> 2;
int _avg2(int a, int b) => (a + b + 1) >> 1;

/// 4x4 luma prediction for [mode] (0..9) at `dst[off]` with [stride].
///
/// Top samples are read at `off - stride` (8 samples: top + top-right), left
/// samples at `off - 1 + j * stride` and the top-left at `off - stride - 1`.
void predLuma4(int mode, Uint8List dst, int off, int stride) {
  final top = off - stride;
  void set(int x, int y, int v) => dst[off + x + y * stride] = v;
  switch (mode) {
    case 0: // DC
      var dc = 4;
      for (var i = 0; i < 4; i++) {
        dc += dst[top + i] + dst[off - 1 + i * stride];
      }
      _fill(dst, off, dc >> 3, 4, stride);
    case 1: // TM
      _trueMotion(dst, off, 4, stride);
    case 2: // VE
      final v0 = _avg3(dst[top - 1], dst[top], dst[top + 1]);
      final v1 = _avg3(dst[top], dst[top + 1], dst[top + 2]);
      final v2 = _avg3(dst[top + 1], dst[top + 2], dst[top + 3]);
      final v3 = _avg3(dst[top + 2], dst[top + 3], dst[top + 4]);
      for (var i = 0; i < 4; i++) {
        final o = off + i * stride;
        dst[o] = v0;
        dst[o + 1] = v1;
        dst[o + 2] = v2;
        dst[o + 3] = v3;
      }
    case 3: // HE
      final a = dst[off - 1 - stride];
      final b = dst[off - 1];
      final c = dst[off - 1 + stride];
      final d = dst[off - 1 + 2 * stride];
      final e = dst[off - 1 + 3 * stride];
      dst.fillRange(off, off + 4, _avg3(a, b, c));
      dst.fillRange(off + stride, off + stride + 4, _avg3(b, c, d));
      dst.fillRange(off + 2 * stride, off + 2 * stride + 4, _avg3(c, d, e));
      dst.fillRange(off + 3 * stride, off + 3 * stride + 4, _avg3(d, e, e));
    case 4: // RD
      final i = dst[off - 1];
      final j = dst[off - 1 + stride];
      final k = dst[off - 1 + 2 * stride];
      final l = dst[off - 1 + 3 * stride];
      final x = dst[top - 1];
      final a = dst[top];
      final b = dst[top + 1];
      final c = dst[top + 2];
      final d = dst[top + 3];
      set(0, 3, _avg3(j, k, l));
      final v1 = _avg3(i, j, k);
      set(1, 3, v1);
      set(0, 2, v1);
      final v2 = _avg3(x, i, j);
      set(2, 3, v2);
      set(1, 2, v2);
      set(0, 1, v2);
      final v3 = _avg3(a, x, i);
      set(3, 3, v3);
      set(2, 2, v3);
      set(1, 1, v3);
      set(0, 0, v3);
      final v4 = _avg3(b, a, x);
      set(3, 2, v4);
      set(2, 1, v4);
      set(1, 0, v4);
      final v5 = _avg3(c, b, a);
      set(3, 1, v5);
      set(2, 0, v5);
      set(3, 0, _avg3(d, c, b));
    case 5: // VR
      final i = dst[off - 1];
      final j = dst[off - 1 + stride];
      final k = dst[off - 1 + 2 * stride];
      final x = dst[top - 1];
      final a = dst[top];
      final b = dst[top + 1];
      final c = dst[top + 2];
      final d = dst[top + 3];
      final v0 = _avg2(x, a);
      set(0, 0, v0);
      set(1, 2, v0);
      final v1 = _avg2(a, b);
      set(1, 0, v1);
      set(2, 2, v1);
      final v2 = _avg2(b, c);
      set(2, 0, v2);
      set(3, 2, v2);
      set(3, 0, _avg2(c, d));
      set(0, 3, _avg3(k, j, i));
      set(0, 2, _avg3(j, i, x));
      final v3 = _avg3(i, x, a);
      set(0, 1, v3);
      set(1, 3, v3);
      final v4 = _avg3(x, a, b);
      set(1, 1, v4);
      set(2, 3, v4);
      final v5 = _avg3(a, b, c);
      set(2, 1, v5);
      set(3, 3, v5);
      set(3, 1, _avg3(b, c, d));
    case 6: // LD
      final a = dst[top];
      final b = dst[top + 1];
      final c = dst[top + 2];
      final d = dst[top + 3];
      final e = dst[top + 4];
      final f = dst[top + 5];
      final g = dst[top + 6];
      final h = dst[top + 7];
      set(0, 0, _avg3(a, b, c));
      final v1 = _avg3(b, c, d);
      set(1, 0, v1);
      set(0, 1, v1);
      final v2 = _avg3(c, d, e);
      set(2, 0, v2);
      set(1, 1, v2);
      set(0, 2, v2);
      final v3 = _avg3(d, e, f);
      set(3, 0, v3);
      set(2, 1, v3);
      set(1, 2, v3);
      set(0, 3, v3);
      final v4 = _avg3(e, f, g);
      set(3, 1, v4);
      set(2, 2, v4);
      set(1, 3, v4);
      final v5 = _avg3(f, g, h);
      set(3, 2, v5);
      set(2, 3, v5);
      set(3, 3, _avg3(g, h, h));
    case 7: // VL
      final a = dst[top];
      final b = dst[top + 1];
      final c = dst[top + 2];
      final d = dst[top + 3];
      final e = dst[top + 4];
      final f = dst[top + 5];
      final g = dst[top + 6];
      final h = dst[top + 7];
      set(0, 0, _avg2(a, b));
      final v1 = _avg2(b, c);
      set(1, 0, v1);
      set(0, 2, v1);
      final v2 = _avg2(c, d);
      set(2, 0, v2);
      set(1, 2, v2);
      final v3 = _avg2(d, e);
      set(3, 0, v3);
      set(2, 2, v3);
      set(0, 1, _avg3(a, b, c));
      final v4 = _avg3(b, c, d);
      set(1, 1, v4);
      set(0, 3, v4);
      final v5 = _avg3(c, d, e);
      set(2, 1, v5);
      set(1, 3, v5);
      final v6 = _avg3(d, e, f);
      set(3, 1, v6);
      set(2, 3, v6);
      set(3, 2, _avg3(e, f, g));
      set(3, 3, _avg3(f, g, h));
    case 8: // HD
      final i = dst[off - 1];
      final j = dst[off - 1 + stride];
      final k = dst[off - 1 + 2 * stride];
      final l = dst[off - 1 + 3 * stride];
      final x = dst[top - 1];
      final a = dst[top];
      final b = dst[top + 1];
      final c = dst[top + 2];
      final v0 = _avg2(i, x);
      set(0, 0, v0);
      set(2, 1, v0);
      final v1 = _avg2(j, i);
      set(0, 1, v1);
      set(2, 2, v1);
      final v2 = _avg2(k, j);
      set(0, 2, v2);
      set(2, 3, v2);
      set(0, 3, _avg2(l, k));
      set(3, 0, _avg3(a, b, c));
      set(2, 0, _avg3(x, a, b));
      final v3 = _avg3(i, x, a);
      set(1, 0, v3);
      set(3, 1, v3);
      final v4 = _avg3(j, i, x);
      set(1, 1, v4);
      set(3, 2, v4);
      final v5 = _avg3(k, j, i);
      set(1, 2, v5);
      set(3, 3, v5);
      set(1, 3, _avg3(l, k, j));
    default: // HU
      final i = dst[off - 1];
      final j = dst[off - 1 + stride];
      final k = dst[off - 1 + 2 * stride];
      final l = dst[off - 1 + 3 * stride];
      set(0, 0, _avg2(i, j));
      final v1 = _avg2(j, k);
      set(2, 0, v1);
      set(0, 1, v1);
      final v2 = _avg2(k, l);
      set(2, 1, v2);
      set(0, 2, v2);
      set(1, 0, _avg3(i, j, k));
      final v3 = _avg3(j, k, l);
      set(3, 0, v3);
      set(1, 1, v3);
      final v4 = _avg3(k, l, l);
      set(3, 1, v4);
      set(1, 2, v4);
      set(3, 2, l);
      set(2, 2, l);
      set(0, 3, l);
      set(1, 3, l);
      set(2, 3, l);
      set(3, 3, l);
  }
}

//------------------------------------------------------------------------------
// Loop filters (paragraph 15)

void _doFilter2(Uint8List p, int off, int step) {
  final p1 = p[off - 2 * step];
  final p0 = p[off - step];
  final q0 = p[off];
  final q1 = p[off + step];
  final a = 3 * (q0 - p0) + _sclip1[1020 + p1 - q1];
  final a1 = _sclip2[112 + sar(a + 4, 3)];
  final a2 = _sclip2[112 + sar(a + 3, 3)];
  p[off - step] = _clip1[255 + p0 + a2];
  p[off] = _clip1[255 + q0 - a1];
}

void _doFilter4(Uint8List p, int off, int step) {
  final p1 = p[off - 2 * step];
  final p0 = p[off - step];
  final q0 = p[off];
  final q1 = p[off + step];
  final a = 3 * (q0 - p0);
  final a1 = _sclip2[112 + sar(a + 4, 3)];
  final a2 = _sclip2[112 + sar(a + 3, 3)];
  final a3 = sar(a1 + 1, 1);
  p[off - 2 * step] = _clip1[255 + p1 + a3];
  p[off - step] = _clip1[255 + p0 + a2];
  p[off] = _clip1[255 + q0 - a1];
  p[off + step] = _clip1[255 + q1 - a3];
}

void _doFilter6(Uint8List p, int off, int step) {
  final p2 = p[off - 3 * step];
  final p1 = p[off - 2 * step];
  final p0 = p[off - step];
  final q0 = p[off];
  final q1 = p[off + step];
  final q2 = p[off + 2 * step];
  final a = _sclip1[1020 + 3 * (q0 - p0) + _sclip1[1020 + p1 - q1]];
  final a1 = sar(27 * a + 63, 7);
  final a2 = sar(18 * a + 63, 7);
  final a3 = sar(9 * a + 63, 7);
  p[off - 3 * step] = _clip1[255 + p2 + a3];
  p[off - 2 * step] = _clip1[255 + p1 + a2];
  p[off - step] = _clip1[255 + p0 + a1];
  p[off] = _clip1[255 + q0 - a1];
  p[off + step] = _clip1[255 + q1 - a2];
  p[off + 2 * step] = _clip1[255 + q2 - a3];
}

bool _hev(Uint8List p, int off, int step, int thresh) {
  final p1 = p[off - 2 * step];
  final p0 = p[off - step];
  final q0 = p[off];
  final q1 = p[off + step];
  return _abs0[255 + p1 - p0] > thresh || _abs0[255 + q1 - q0] > thresh;
}

bool _needsFilter(Uint8List p, int off, int step, int t) {
  final p1 = p[off - 2 * step];
  final p0 = p[off - step];
  final q0 = p[off];
  final q1 = p[off + step];
  return 4 * _abs0[255 + p0 - q0] + _abs0[255 + p1 - q1] <= t;
}

bool _needsFilter2(Uint8List p, int off, int step, int t, int it) {
  final p3 = p[off - 4 * step];
  final p2 = p[off - 3 * step];
  final p1 = p[off - 2 * step];
  final p0 = p[off - step];
  final q0 = p[off];
  final q1 = p[off + step];
  final q2 = p[off + 2 * step];
  final q3 = p[off + 3 * step];
  if (4 * _abs0[255 + p0 - q0] + _abs0[255 + p1 - q1] > t) return false;
  return _abs0[255 + p3 - p2] <= it &&
      _abs0[255 + p2 - p1] <= it &&
      _abs0[255 + p1 - p0] <= it &&
      _abs0[255 + q3 - q2] <= it &&
      _abs0[255 + q2 - q1] <= it &&
      _abs0[255 + q1 - q0] <= it;
}

/// Simple vertical filter across a horizontal edge (16 pixels wide).
void simpleVFilter16(Uint8List p, int off, int stride, int thresh) {
  final thresh2 = 2 * thresh + 1;
  for (var i = 0; i < 16; i++) {
    if (_needsFilter(p, off + i, stride, thresh2)) {
      _doFilter2(p, off + i, stride);
    }
  }
}

/// Simple horizontal filter across a vertical edge (16 pixels tall).
void simpleHFilter16(Uint8List p, int off, int stride, int thresh) {
  final thresh2 = 2 * thresh + 1;
  for (var i = 0; i < 16; i++) {
    if (_needsFilter(p, off + i * stride, 1, thresh2)) {
      _doFilter2(p, off + i * stride, 1);
    }
  }
}

/// Simple filter on the three inner horizontal edges.
void simpleVFilter16i(Uint8List p, int off, int stride, int thresh) {
  for (var k = 3; k > 0; k--) {
    off += 4 * stride;
    simpleVFilter16(p, off, stride, thresh);
  }
}

/// Simple filter on the three inner vertical edges.
void simpleHFilter16i(Uint8List p, int off, int stride, int thresh) {
  for (var k = 3; k > 0; k--) {
    off += 4;
    simpleHFilter16(p, off, stride, thresh);
  }
}

void _filterLoop26(
  Uint8List p,
  int off,
  int hstride,
  int vstride,
  int size,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  final thresh2 = 2 * thresh + 1;
  while (size-- > 0) {
    if (_needsFilter2(p, off, hstride, thresh2, ithresh)) {
      if (_hev(p, off, hstride, hevThresh)) {
        _doFilter2(p, off, hstride);
      } else {
        _doFilter6(p, off, hstride);
      }
    }
    off += vstride;
  }
}

void _filterLoop24(
  Uint8List p,
  int off,
  int hstride,
  int vstride,
  int size,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  final thresh2 = 2 * thresh + 1;
  while (size-- > 0) {
    if (_needsFilter2(p, off, hstride, thresh2, ithresh)) {
      if (_hev(p, off, hstride, hevThresh)) {
        _doFilter2(p, off, hstride);
      } else {
        _doFilter4(p, off, hstride);
      }
    }
    off += vstride;
  }
}

/// Complex filter on a macroblock top edge (luma).
void vFilter16(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  _filterLoop26(p, off, stride, 1, 16, thresh, ithresh, hevThresh);
}

/// Complex filter on a macroblock left edge (luma).
void hFilter16(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  _filterLoop26(p, off, 1, stride, 16, thresh, ithresh, hevThresh);
}

/// Complex filter on the three inner horizontal edges (luma).
void vFilter16i(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  for (var k = 3; k > 0; k--) {
    off += 4 * stride;
    _filterLoop24(p, off, stride, 1, 16, thresh, ithresh, hevThresh);
  }
}

/// Complex filter on the three inner vertical edges (luma).
void hFilter16i(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  for (var k = 3; k > 0; k--) {
    off += 4;
    _filterLoop24(p, off, 1, stride, 16, thresh, ithresh, hevThresh);
  }
}

/// Complex filter on a macroblock top edge (one 8x8 chroma plane).
void vFilter8(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  _filterLoop26(p, off, stride, 1, 8, thresh, ithresh, hevThresh);
}

/// Complex filter on a macroblock left edge (one 8x8 chroma plane).
void hFilter8(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  _filterLoop26(p, off, 1, stride, 8, thresh, ithresh, hevThresh);
}

/// Complex filter on the inner horizontal edge of a chroma block.
void vFilter8i(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  _filterLoop24(p, off + 4 * stride, stride, 1, 8, thresh, ithresh, hevThresh);
}

/// Complex filter on the inner vertical edge of a chroma block.
void hFilter8i(
  Uint8List p,
  int off,
  int stride,
  int thresh,
  int ithresh,
  int hevThresh,
) {
  _filterLoop24(p, off + 4, 1, stride, 8, thresh, ithresh, hevThresh);
}
