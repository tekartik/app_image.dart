/// Speed-critical VP8 encoding routines (forward transforms, predictions
/// into the scratch buffer, metrics, quantization).
library;

import 'dart:typed_data';

import '../int_utils.dart';
import 'dsp.dart' show bps, clip1;

/// Size of one Y/U/V sample block in the encoder work buffers.
const yuvSizeEnc = bps * 16;

/// Size of the prediction scratch buffer.
const predSizeEnc = 32 * bps + 16 * bps + 8 * bps;

/// Luma offset in the work buffer.
const yOffEnc = 0;

/// U offset in the work buffer.
const uOffEnc = 16;

/// V offset in the work buffer.
const vOffEnc = 16 + 8;

/// Intra16 prediction offsets in the scratch buffer.
const i16Dc16 = 0 * 16 * bps;

/// TM 16x16.
const i16Tm16 = i16Dc16 + 16;

/// Vertical 16x16.
const i16Ve16 = 1 * 16 * bps;

/// Horizontal 16x16.
const i16He16 = i16Ve16 + 16;

/// Chroma DC (U and V side by side).
const c8Dc8 = 2 * 16 * bps;

/// Chroma TM.
const c8Tm8 = c8Dc8 + 16;

/// Chroma vertical.
const c8Ve8 = 2 * 16 * bps + 8 * bps;

/// Chroma horizontal.
const c8He8 = c8Ve8 + 16;

/// Intra4 predictions base.
const i4Dc4 = 3 * 16 * bps + 0;

/// Intra4 TM.
const i4Tm4 = i4Dc4 + 4;

/// Intra4 VE.
const i4Ve4 = i4Dc4 + 8;

/// Intra4 HE.
const i4He4 = i4Dc4 + 12;

/// Intra4 RD.
const i4Rd4 = i4Dc4 + 16;

/// Intra4 VR.
const i4Vr4 = i4Dc4 + 20;

/// Intra4 LD.
const i4Ld4 = i4Dc4 + 24;

/// Intra4 VL.
const i4Vl4 = i4Dc4 + 28;

/// Intra4 HD.
const i4Hd4 = 3 * 16 * bps + 4 * bps;

/// Intra4 HU.
const i4Hu4 = i4Hd4 + 4;

/// Intra4 scratch block.
const i4Tmp = i4Hd4 + 8;

/// Offsets of the 4 intra16 modes (DC, TM, VE, HE).
const i16ModeOffsets = [i16Dc16, i16Tm16, i16Ve16, i16He16];

/// Offsets of the 4 chroma modes.
const uvModeOffsets = [c8Dc8, c8Tm8, c8Ve8, c8He8];

/// Offsets of the 10 intra4 modes.
const i4ModeOffsets = [
  i4Dc4,
  i4Tm4,
  i4Ve4,
  i4He4,
  i4Rd4,
  i4Vr4,
  i4Ld4,
  i4Vl4,
  i4Hd4,
  i4Hu4,
];

/// Offsets of the sixteen 4x4 luma blocks in the work buffer.
const scan = [
  0 + 0 * bps, 4 + 0 * bps, 8 + 0 * bps, 12 + 0 * bps, //
  0 + 4 * bps, 4 + 4 * bps, 8 + 4 * bps, 12 + 4 * bps, //
  0 + 8 * bps, 4 + 8 * bps, 8 + 8 * bps, 12 + 8 * bps, //
  0 + 12 * bps, 4 + 12 * bps, 8 + 12 * bps, 12 + 12 * bps, //
];

/// Offsets of the eight 4x4 chroma blocks (U then V) in the work buffer.
const scanUv = [
  0 + 0 * bps, 4 + 0 * bps, 0 + 4 * bps, 4 + 4 * bps, //
  8 + 0 * bps, 12 + 0 * bps, 8 + 4 * bps, 12 + 4 * bps, //
];

int _clip8(int v) => (v & ~0xff) == 0 ? v : (v < 0 ? 0 : 255);
int _mul1(int a) => sar(a * 20091, 16) + a;
int _mul2(int a) => sar(a * 35468, 16);

//------------------------------------------------------------------------------
// Transforms

/// Inverse transform of `input[inOff..]` added to `ref`, stored in `dst`.
void iTransform(
  Uint8List ref,
  int refOff,
  Int16List input,
  int inOff,
  Uint8List dst,
  int dstOff,
  bool doTwo,
) {
  _iTransformOne(ref, refOff, input, inOff, dst, dstOff);
  if (doTwo) {
    _iTransformOne(ref, refOff + 4, input, inOff + 16, dst, dstOff + 4);
  }
}

final _c = Int32List(16);

void _iTransformOne(
  Uint8List ref,
  int refOff,
  Int16List input,
  int inOff,
  Uint8List dst,
  int dstOff,
) {
  final c = _c;
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
  for (var i = 0; i < 4; i++) {
    final dc = c[t] + 4;
    final a = dc + c[t + 8];
    final b = dc - c[t + 8];
    final cc = _mul2(c[t + 4]) - _mul1(c[t + 12]);
    final d = _mul1(c[t + 4]) + _mul2(c[t + 12]);
    final r = refOff + i * bps;
    final o = dstOff + i * bps;
    dst[o] = _clip8(ref[r] + sar(a + d, 3));
    dst[o + 1] = _clip8(ref[r + 1] + sar(b + cc, 3));
    dst[o + 2] = _clip8(ref[r + 2] + sar(b - cc, 3));
    dst[o + 3] = _clip8(ref[r + 3] + sar(a - d, 3));
    t++;
  }
}

final _tmp = Int32List(16);

/// Forward DCT of the difference `src - ref` (4x4 blocks, stride [bps]).
void fTransform(
  Uint8List src,
  int srcOff,
  Uint8List ref,
  int refOff,
  Int16List out,
  int outOff,
) {
  final tmp = _tmp;
  for (var i = 0; i < 4; i++, srcOff += bps, refOff += bps) {
    final d0 = src[srcOff] - ref[refOff];
    final d1 = src[srcOff + 1] - ref[refOff + 1];
    final d2 = src[srcOff + 2] - ref[refOff + 2];
    final d3 = src[srcOff + 3] - ref[refOff + 3];
    final a0 = d0 + d3;
    final a1 = d1 + d2;
    final a2 = d1 - d2;
    final a3 = d0 - d3;
    tmp[i * 4] = (a0 + a1) * 8;
    tmp[1 + i * 4] = sar(a2 * 2217 + a3 * 5352 + 1812, 9);
    tmp[2 + i * 4] = (a0 - a1) * 8;
    tmp[3 + i * 4] = sar(a3 * 2217 - a2 * 5352 + 937, 9);
  }
  for (var i = 0; i < 4; i++) {
    final a0 = tmp[i] + tmp[12 + i];
    final a1 = tmp[4 + i] + tmp[8 + i];
    final a2 = tmp[4 + i] - tmp[8 + i];
    final a3 = tmp[i] - tmp[12 + i];
    out[outOff + i] = sar(a0 + a1 + 7, 4);
    out[outOff + 4 + i] =
        sar(a2 * 2217 + a3 * 5352 + 12000, 16) + (a3 != 0 ? 1 : 0);
    out[outOff + 8 + i] = sar(a0 - a1 + 7, 4);
    out[outOff + 12 + i] = sar(a3 * 2217 - a2 * 5352 + 51000, 16);
  }
}

/// Two horizontally adjacent [fTransform].
void fTransform2(
  Uint8List src,
  int srcOff,
  Uint8List ref,
  int refOff,
  Int16List out,
  int outOff,
) {
  fTransform(src, srcOff, ref, refOff, out, outOff);
  fTransform(src, srcOff + 4, ref, refOff + 4, out, outOff + 16);
}

/// Forward Walsh-Hadamard transform of the 16 DC coefficients found at
/// `input[inOff + 16 * n]`, output 16 values at `out[outOff..]`.
void fTransformWht(Int16List input, int inOff, Int16List out, int outOff) {
  final tmp = _tmp;
  for (var i = 0; i < 4; i++) {
    final base = inOff + i * 64;
    final a0 = input[base] + input[base + 32];
    final a1 = input[base + 16] + input[base + 48];
    final a2 = input[base + 16] - input[base + 48];
    final a3 = input[base] - input[base + 32];
    tmp[i * 4] = a0 + a1;
    tmp[1 + i * 4] = a3 + a2;
    tmp[2 + i * 4] = a3 - a2;
    tmp[3 + i * 4] = a0 - a1;
  }
  for (var i = 0; i < 4; i++) {
    final a0 = tmp[i] + tmp[8 + i];
    final a1 = tmp[4 + i] + tmp[12 + i];
    final a2 = tmp[4 + i] - tmp[12 + i];
    final a3 = tmp[i] - tmp[8 + i];
    final b0 = a0 + a1;
    final b1 = a3 + a2;
    final b2 = a3 - a2;
    final b3 = a0 - a1;
    out[outOff + i] = sar(b0, 1);
    out[outOff + 4 + i] = sar(b1, 1);
    out[outOff + 8 + i] = sar(b2, 1);
    out[outOff + 12 + i] = sar(b3, 1);
  }
}

//------------------------------------------------------------------------------
// Intra predictions (encoder flavor: explicit top/left arrays).

void _fill(Uint8List dst, int off, int value, int size) {
  for (var j = 0; j < size; j++) {
    dst.fillRange(off + j * bps, off + j * bps + size, value);
  }
}

void _verticalPred(
  Uint8List dst,
  int off,
  Uint8List? top,
  int topOff,
  int size,
) {
  if (top != null) {
    for (var j = 0; j < size; j++) {
      dst.setRange(off + j * bps, off + j * bps + size, top, topOff);
    }
  } else {
    _fill(dst, off, 127, size);
  }
}

void _horizontalPred(
  Uint8List dst,
  int off,
  Uint8List? left,
  int leftOff,
  int size,
) {
  if (left != null) {
    for (var j = 0; j < size; j++) {
      dst.fillRange(off + j * bps, off + j * bps + size, left[leftOff + j]);
    }
  } else {
    _fill(dst, off, 129, size);
  }
}

void _trueMotion(
  Uint8List dst,
  int off,
  Uint8List? left,
  int leftOff,
  Uint8List? top,
  int topOff,
  int size,
) {
  if (left != null) {
    if (top != null) {
      final topLeft = left[leftOff - 1];
      for (var y = 0; y < size; y++) {
        final base = left[leftOff + y] - topLeft;
        final o = off + y * bps;
        for (var x = 0; x < size; x++) {
          dst[o + x] = clip1(base + top[topOff + x]);
        }
      }
    } else {
      _horizontalPred(dst, off, left, leftOff, size);
    }
  } else {
    if (top != null) {
      _verticalPred(dst, off, top, topOff, size);
    } else {
      _fill(dst, off, 129, size);
    }
  }
}

void _dcMode(
  Uint8List dst,
  int off,
  Uint8List? left,
  int leftOff,
  Uint8List? top,
  int topOff,
  int size,
  int round,
  int shift,
) {
  var dc = 0;
  if (top != null) {
    for (var j = 0; j < size; j++) {
      dc += top[topOff + j];
    }
    if (left != null) {
      for (var j = 0; j < size; j++) {
        dc += left[leftOff + j];
      }
    } else {
      dc += dc;
    }
    dc = (dc + round) >> shift;
  } else if (left != null) {
    for (var j = 0; j < size; j++) {
      dc += left[leftOff + j];
    }
    dc += dc;
    dc = (dc + round) >> shift;
  } else {
    dc = 0x80;
  }
  _fill(dst, off, dc, size);
}

/// Computes the four 16x16 luma predictions into `dst` (scratch buffer).
///
/// [left] (16 samples at [leftOff], top-left at `leftOff - 1`) and [top]
/// (16 samples) may be null when unavailable.
void intra16Preds(
  Uint8List dst,
  Uint8List? left,
  int leftOff,
  Uint8List? top,
  int topOff,
) {
  _dcMode(dst, i16Dc16, left, leftOff, top, topOff, 16, 16, 5);
  _verticalPred(dst, i16Ve16, top, topOff, 16);
  _horizontalPred(dst, i16He16, left, leftOff, 16);
  _trueMotion(dst, i16Tm16, left, leftOff, top, topOff, 16);
}

/// Computes the four 8x8 chroma predictions (U and V) into `dst`.
///
/// [left] holds U samples at [leftOff] and V samples at `leftOff + 16`;
/// [top] holds U at [topOff] and V at `topOff + 8`.
void intraChromaPreds(
  Uint8List dst,
  Uint8List? left,
  int leftOff,
  Uint8List? top,
  int topOff,
) {
  _dcMode(dst, c8Dc8, left, leftOff, top, topOff, 8, 8, 4);
  _verticalPred(dst, c8Ve8, top, topOff, 8);
  _horizontalPred(dst, c8He8, left, leftOff, 8);
  _trueMotion(dst, c8Tm8, left, leftOff, top, topOff, 8);
  final lo = leftOff + 16;
  final to = topOff + 8;
  _dcMode(dst, c8Dc8 + 8, left, lo, top, to, 8, 8, 4);
  _verticalPred(dst, c8Ve8 + 8, top, to, 8);
  _horizontalPred(dst, c8He8 + 8, left, lo, 8);
  _trueMotion(dst, c8Tm8 + 8, left, lo, top, to, 8);
}

int _avg3(int a, int b, int c) => (a + 2 * b + c + 2) >> 2;
int _avg2(int a, int b) => (a + b + 1) >> 1;

/// Computes the ten 4x4 predictions into `dst`.
///
/// `top[t - 5 .. t - 2]` are the left samples (bottom to top), `top[t - 1]`
/// the top-left, `top[t .. t + 7]` the top and top-right samples.
void intra4Preds(Uint8List dst, Uint8List top, int t) {
  void set(int base, int x, int y, int v) => dst[base + x + y * bps] = v;
  final x0 = top[t - 1];
  final i = top[t - 2];
  final j = top[t - 3];
  final k = top[t - 4];
  final l = top[t - 5];
  final a = top[t];
  final b = top[t + 1];
  final c = top[t + 2];
  final d = top[t + 3];
  final e = top[t + 4];
  final f = top[t + 5];
  final g = top[t + 6];
  final h = top[t + 7];
  // DC4
  {
    var dc = 4;
    for (var n = 0; n < 4; n++) {
      dc += top[t + n] + top[t - 5 + n];
    }
    _fill(dst, i4Dc4, dc >> 3, 4);
  }
  // TM4
  {
    for (var y = 0; y < 4; y++) {
      final base = top[t - 2 - y] - x0;
      final o = i4Tm4 + y * bps;
      for (var x = 0; x < 4; x++) {
        dst[o + x] = clip1(base + top[t + x]);
      }
    }
  }
  // VE4
  {
    final v0 = _avg3(x0, a, b);
    final v1 = _avg3(a, b, c);
    final v2 = _avg3(b, c, d);
    final v3 = _avg3(c, d, e);
    for (var y = 0; y < 4; y++) {
      final o = i4Ve4 + y * bps;
      dst[o] = v0;
      dst[o + 1] = v1;
      dst[o + 2] = v2;
      dst[o + 3] = v3;
    }
  }
  // HE4
  {
    dst.fillRange(i4He4, i4He4 + 4, _avg3(x0, i, j));
    dst.fillRange(i4He4 + bps, i4He4 + bps + 4, _avg3(i, j, k));
    dst.fillRange(i4He4 + 2 * bps, i4He4 + 2 * bps + 4, _avg3(j, k, l));
    dst.fillRange(i4He4 + 3 * bps, i4He4 + 3 * bps + 4, _avg3(k, l, l));
  }
  // RD4
  {
    const o = i4Rd4;
    set(o, 0, 3, _avg3(j, k, l));
    final v1 = _avg3(i, j, k);
    set(o, 0, 2, v1);
    set(o, 1, 3, v1);
    final v2 = _avg3(x0, i, j);
    set(o, 0, 1, v2);
    set(o, 1, 2, v2);
    set(o, 2, 3, v2);
    final v3 = _avg3(a, x0, i);
    set(o, 0, 0, v3);
    set(o, 1, 1, v3);
    set(o, 2, 2, v3);
    set(o, 3, 3, v3);
    final v4 = _avg3(b, a, x0);
    set(o, 1, 0, v4);
    set(o, 2, 1, v4);
    set(o, 3, 2, v4);
    final v5 = _avg3(c, b, a);
    set(o, 2, 0, v5);
    set(o, 3, 1, v5);
    set(o, 3, 0, _avg3(d, c, b));
  }
  // VR4
  {
    const o = i4Vr4;
    final v0 = _avg2(x0, a);
    set(o, 0, 0, v0);
    set(o, 1, 2, v0);
    final v1 = _avg2(a, b);
    set(o, 1, 0, v1);
    set(o, 2, 2, v1);
    final v2 = _avg2(b, c);
    set(o, 2, 0, v2);
    set(o, 3, 2, v2);
    set(o, 3, 0, _avg2(c, d));
    set(o, 0, 3, _avg3(k, j, i));
    set(o, 0, 2, _avg3(j, i, x0));
    final v3 = _avg3(i, x0, a);
    set(o, 0, 1, v3);
    set(o, 1, 3, v3);
    final v4 = _avg3(x0, a, b);
    set(o, 1, 1, v4);
    set(o, 2, 3, v4);
    final v5 = _avg3(a, b, c);
    set(o, 2, 1, v5);
    set(o, 3, 3, v5);
    set(o, 3, 1, _avg3(b, c, d));
  }
  // LD4
  {
    const o = i4Ld4;
    set(o, 0, 0, _avg3(a, b, c));
    final v1 = _avg3(b, c, d);
    set(o, 1, 0, v1);
    set(o, 0, 1, v1);
    final v2 = _avg3(c, d, e);
    set(o, 2, 0, v2);
    set(o, 1, 1, v2);
    set(o, 0, 2, v2);
    final v3 = _avg3(d, e, f);
    set(o, 3, 0, v3);
    set(o, 2, 1, v3);
    set(o, 1, 2, v3);
    set(o, 0, 3, v3);
    final v4 = _avg3(e, f, g);
    set(o, 3, 1, v4);
    set(o, 2, 2, v4);
    set(o, 1, 3, v4);
    final v5 = _avg3(f, g, h);
    set(o, 3, 2, v5);
    set(o, 2, 3, v5);
    set(o, 3, 3, _avg3(g, h, h));
  }
  // VL4
  {
    const o = i4Vl4;
    set(o, 0, 0, _avg2(a, b));
    final v1 = _avg2(b, c);
    set(o, 1, 0, v1);
    set(o, 0, 2, v1);
    final v2 = _avg2(c, d);
    set(o, 2, 0, v2);
    set(o, 1, 2, v2);
    final v3 = _avg2(d, e);
    set(o, 3, 0, v3);
    set(o, 2, 2, v3);
    set(o, 0, 1, _avg3(a, b, c));
    final v4 = _avg3(b, c, d);
    set(o, 1, 1, v4);
    set(o, 0, 3, v4);
    final v5 = _avg3(c, d, e);
    set(o, 2, 1, v5);
    set(o, 1, 3, v5);
    final v6 = _avg3(d, e, f);
    set(o, 3, 1, v6);
    set(o, 2, 3, v6);
    set(o, 3, 2, _avg3(e, f, g));
    set(o, 3, 3, _avg3(f, g, h));
  }
  // HD4
  {
    const o = i4Hd4;
    final v0 = _avg2(i, x0);
    set(o, 0, 0, v0);
    set(o, 2, 1, v0);
    final v1 = _avg2(j, i);
    set(o, 0, 1, v1);
    set(o, 2, 2, v1);
    final v2 = _avg2(k, j);
    set(o, 0, 2, v2);
    set(o, 2, 3, v2);
    set(o, 0, 3, _avg2(l, k));
    set(o, 3, 0, _avg3(a, b, c));
    set(o, 2, 0, _avg3(x0, a, b));
    final v3 = _avg3(i, x0, a);
    set(o, 1, 0, v3);
    set(o, 3, 1, v3);
    final v4 = _avg3(j, i, x0);
    set(o, 1, 1, v4);
    set(o, 3, 2, v4);
    final v5 = _avg3(k, j, i);
    set(o, 1, 2, v5);
    set(o, 3, 3, v5);
    set(o, 1, 3, _avg3(l, k, j));
  }
  // HU4
  {
    const o = i4Hu4;
    set(o, 0, 0, _avg2(i, j));
    final v1 = _avg2(j, k);
    set(o, 2, 0, v1);
    set(o, 0, 1, v1);
    final v2 = _avg2(k, l);
    set(o, 2, 1, v2);
    set(o, 0, 2, v2);
    set(o, 1, 0, _avg3(i, j, k));
    final v3 = _avg3(j, k, l);
    set(o, 3, 0, v3);
    set(o, 1, 1, v3);
    final v4 = _avg3(k, l, l);
    set(o, 3, 1, v4);
    set(o, 1, 2, v4);
    set(o, 3, 2, l);
    set(o, 2, 2, l);
    set(o, 0, 3, l);
    set(o, 1, 3, l);
    set(o, 2, 3, l);
    set(o, 3, 3, l);
  }
}

//------------------------------------------------------------------------------
// Metrics

int _sse(Uint8List a, int ao, Uint8List b, int bo, int w, int h) {
  var count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final diff = a[ao + x] - b[bo + x];
      count += diff * diff;
    }
    ao += bps;
    bo += bps;
  }
  return count;
}

/// Sum of squared errors over a 16x16 block.
int sse16x16(Uint8List a, int ao, Uint8List b, int bo) =>
    _sse(a, ao, b, bo, 16, 16);

/// Sum of squared errors over a 16x8 block.
int sse16x8(Uint8List a, int ao, Uint8List b, int bo) =>
    _sse(a, ao, b, bo, 16, 8);

/// Sum of squared errors over a 8x8 block.
int sse8x8(Uint8List a, int ao, Uint8List b, int bo) =>
    _sse(a, ao, b, bo, 8, 8);

/// Sum of squared errors over a 4x4 block.
int sse4x4(Uint8List a, int ao, Uint8List b, int bo) =>
    _sse(a, ao, b, bo, 4, 4);

/// Sums of the 4x4 blocks of a 16x4 strip.
void mean16x4(Uint8List ref, int off, Uint32List dc) {
  for (var k = 0; k < 4; k++) {
    var avg = 0;
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        avg += ref[off + x + y * bps];
      }
    }
    dc[k] = avg;
    off += 4;
  }
}

int _tTransform(Uint8List input, int off, List<int> w) {
  var sum = 0;
  final tmp = _tmp;
  for (var i = 0; i < 4; i++, off += bps) {
    final a0 = input[off] + input[off + 2];
    final a1 = input[off + 1] + input[off + 3];
    final a2 = input[off + 1] - input[off + 3];
    final a3 = input[off] - input[off + 2];
    tmp[i * 4] = a0 + a1;
    tmp[1 + i * 4] = a3 + a2;
    tmp[2 + i * 4] = a3 - a2;
    tmp[3 + i * 4] = a0 - a1;
  }
  for (var i = 0; i < 4; i++) {
    final a0 = tmp[i] + tmp[8 + i];
    final a1 = tmp[4 + i] + tmp[12 + i];
    final a2 = tmp[4 + i] - tmp[12 + i];
    final a3 = tmp[i] - tmp[8 + i];
    final b0 = a0 + a1;
    final b1 = a3 + a2;
    final b2 = a3 - a2;
    final b3 = a0 - a1;
    sum += w[i] * b0.abs();
    sum += w[4 + i] * b1.abs();
    sum += w[8 + i] * b2.abs();
    sum += w[12 + i] * b3.abs();
  }
  return sum;
}

/// Weighted spectral distortion between two 4x4 blocks.
int disto4x4(Uint8List a, int ao, Uint8List b, int bo, List<int> w) {
  final sum1 = _tTransform(a, ao, w);
  final sum2 = _tTransform(b, bo, w);
  return (sum2 - sum1).abs() >> 5;
}

/// Weighted spectral distortion between two 16x16 blocks.
int disto16x16(Uint8List a, int ao, Uint8List b, int bo, List<int> w) {
  var d = 0;
  for (var y = 0; y < 16 * bps; y += 4 * bps) {
    for (var x = 0; x < 16; x += 4) {
      d += disto4x4(a, ao + x + y, b, bo + x + y, w);
    }
  }
  return d;
}

//------------------------------------------------------------------------------
// Quantization

/// Fixed point precision of the quantizer reciprocals.
const qfix = 17;

/// Quantization matrix for one coefficient type.
class Vp8Matrix {
  /// Quantizer steps.
  final q = Uint16List(16);

  /// Reciprocals (fixed point).
  final iq = Uint32List(16);

  /// Rounding bias.
  final bias = Uint32List(16);

  /// Value below which a coefficient is zeroed.
  final zthresh = Uint32List(16);

  /// Frequency boosters.
  final sharpen = Uint16List(16);
}

/// `QUANTDIV`: `(n * iQ + B) >> QFIX`.
int quantDiv(int n, int iQ, int b) => (n * iQ + b) >> qfix;

const _kZigzag = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15];

/// Quantizes `input[inOff..]` (in place, dequantized) into
/// `out[outOff..]` (zigzag order). Returns 1 if any level is non-zero.
int quantizeBlock(
  Int16List input,
  int inOff,
  Int16List out,
  int outOff,
  Vp8Matrix mtx,
) {
  var last = -1;
  for (var n = 0; n < 16; n++) {
    final j = _kZigzag[n];
    final v = input[inOff + j];
    final sign = v < 0;
    final coeff = (sign ? -v : v) + mtx.sharpen[j];
    if (coeff > mtx.zthresh[j]) {
      final qq = mtx.q[j];
      final iQ = mtx.iq[j];
      final b = mtx.bias[j];
      var level = quantDiv(coeff, iQ, b);
      if (level > 2047) level = 2047;
      if (sign) level = -level;
      input[inOff + j] = level * qq;
      out[outOff + n] = level;
      if (level != 0) last = n;
    } else {
      out[outOff + n] = 0;
      input[inOff + j] = 0;
    }
  }
  return last >= 0 ? 1 : 0;
}

/// Quantizes two consecutive blocks; returns the non-zero bits.
int quantize2Blocks(
  Int16List input,
  int inOff,
  Int16List out,
  int outOff,
  Vp8Matrix mtx,
) {
  var nz = quantizeBlock(input, inOff, out, outOff, mtx);
  nz |= quantizeBlock(input, inOff + 16, out, outOff + 16, mtx) << 1;
  return nz;
}

//------------------------------------------------------------------------------
// Histogram of DCT coefficients (analysis)

/// Maximum coefficient bin.
const maxCoeffThresh = 31;

/// Offsets of the 16 luma + 8 chroma blocks for [collectHistogram].
const dspScan = [
  0 + 0 * bps, 4 + 0 * bps, 8 + 0 * bps, 12 + 0 * bps, //
  0 + 4 * bps, 4 + 4 * bps, 8 + 4 * bps, 12 + 4 * bps, //
  0 + 8 * bps, 4 + 8 * bps, 8 + 8 * bps, 12 + 8 * bps, //
  0 + 12 * bps, 4 + 12 * bps, 8 + 12 * bps, 12 + 12 * bps, //
  0 + 0 * bps, 4 + 0 * bps, 0 + 4 * bps, 4 + 4 * bps, //
  8 + 0 * bps, 12 + 0 * bps, 8 + 4 * bps, 12 + 4 * bps, //
];

/// Collects the coefficient histogram of blocks `[startBlock, endBlock)`;
/// returns `[maxValue, lastNonZero]`.
List<int> collectHistogram(
  Uint8List ref,
  int refOff,
  Uint8List pred,
  int predOff,
  int startBlock,
  int endBlock,
) {
  final distribution = List<int>.filled(maxCoeffThresh + 1, 0);
  final out = Int16List(16);
  for (var j = startBlock; j < endBlock; j++) {
    fTransform(ref, refOff + dspScan[j], pred, predOff + dspScan[j], out, 0);
    for (var k = 0; k < 16; k++) {
      var v = out[k].abs() >> 3;
      if (v > maxCoeffThresh) v = maxCoeffThresh;
      distribution[v]++;
    }
  }
  var maxValue = 0;
  var lastNonZero = 1;
  for (var k = 0; k <= maxCoeffThresh; k++) {
    final value = distribution[k];
    if (value > 0) {
      if (value > maxValue) maxValue = value;
      lastNonZero = k;
    }
  }
  return [maxValue, lastNonZero];
}
