import 'dart:typed_data';

import '../int_utils.dart';
import '../webp_image.dart';
import 'bool_reader.dart';
import 'dsp.dart';
import 'tables.dart';

/// Per-segment dequantization factors.
class _QuantMatrix {
  final y1 = Int32List(2);
  final y2 = Int32List(2);
  final uv = Int32List(2);
}

/// Filter parameters of a macroblock.
class _FInfo {
  int fLimit = 0;
  int fIlevel = 0;
  bool fInner = false;
  int hevThresh = 0;
  void copyFrom(_FInfo o) {
    fLimit = o.fLimit;
    fIlevel = o.fIlevel;
    fInner = o.fInner;
    hevThresh = o.hevThresh;
  }
}

/// Parsed data of a macroblock, needed for reconstruction.
class _MbData {
  final coeffs = Int16List(384);
  bool isI4x4 = false;
  final imodes = Uint8List(16);
  int uvmode = 0;
  int nonZeroY = 0;
  int nonZeroUv = 0;
  bool skip = false;
  int segment = 0;
}

/// Decoder for the VP8 (lossy) key-frame bitstream.
///
/// Produces Y/U/V planes; see `yuv.dart` for the RGB conversion.
class Vp8Decoder {
  final Uint8List _data;

  /// Picture width.
  int width = 0;

  /// Picture height.
  int height = 0;

  /// Width in macroblocks.
  int mbW = 0;

  /// Height in macroblocks.
  int mbH = 0;

  /// Decoded luma plane (stride [yStride], `mbH * 16` rows).
  late Uint8List yPlane;

  /// Decoded U plane (stride [uvStride], `mbH * 8` rows).
  late Uint8List uPlane;

  /// Decoded V plane.
  late Uint8List vPlane;

  /// Luma stride (`mbW * 16`).
  int get yStride => mbW * 16;

  /// Chroma stride (`mbW * 8`).
  int get uvStride => mbW * 8;

  // Headers.
  int _profile = 0;
  int _partitionLength = 0;
  bool _useSegment = false;
  bool _updateMap = false;
  bool _absoluteDelta = true;
  final _segQuantizer = Int32List(numMbSegments);
  final _segFilterStrength = Int32List(numMbSegments);
  final _segmentProbas = Uint8List(3);
  bool _filterSimple = false;
  int _filterLevel = 0;
  int _filterSharpness = 0;
  bool _useLfDelta = false;
  final _refLfDelta = Int32List(4);
  final _modeLfDelta = Int32List(4);
  int _filterType = 0; // 0=off, 1=simple, 2=complex
  final _dqm = List.generate(numMbSegments, (_) => _QuantMatrix());
  final _proba = Uint8List(numTypes * numBands * numCtx * numProbas);
  bool _useSkipProba = false;
  int _skipP = 0;

  late Vp8BoolReader _br;
  late List<Vp8BoolReader> _parts;
  int _numPartsMinusOne = 0;

  // Contexts.
  late Uint8List _intraT;
  final _intraL = Uint8List(4);
  late Uint8List _mbNz; // mbW + 1 entries (index 0 = left)
  late Uint8List _mbNzDc;
  late List<_MbData> _mbData;
  late List<_FInfo> _fInfo;
  final _fstrengths = List.generate(numMbSegments, (_) => [_FInfo(), _FInfo()]);
  late Uint8List _yuvT; // top samples: 32 bytes per MB (16 y, 8 u, 8 v)
  final _yuvB = Uint8List(yuvSize);

  /// Creates a decoder for a `VP8 ` chunk payload and parses the headers.
  Vp8Decoder(this._data) {
    _parseHeaders();
  }

  /// Checks the 3-byte VP8 key-frame signature at [off].
  static bool checkSignature(Uint8List d, int off) =>
      d.length >= off + 3 &&
      d[off] == 0x9d &&
      d[off + 1] == 0x01 &&
      d[off + 2] == 0x2a;

  /// Reads only the dimensions of a `VP8 ` payload.
  static WebpInfo readInfo(Uint8List data) {
    if (data.length < 10) throw WebpFormatException('Truncated VP8 header');
    final bits = data[0] | (data[1] << 8) | (data[2] << 16);
    if ((bits & 1) != 0) throw WebpFormatException('Not a VP8 key frame');
    if (!checkSignature(data, 3)) {
      throw WebpFormatException('Bad VP8 signature');
    }
    final w = ((data[7] << 8) | data[6]) & 0x3fff;
    final h = ((data[9] << 8) | data[8]) & 0x3fff;
    if (w == 0 || h == 0) throw WebpFormatException('Invalid VP8 dimensions');
    return WebpInfo(
      width: w,
      height: h,
      hasAlpha: false,
      format: WebpFormat.lossy,
    );
  }

  void _parseHeaders() {
    final buf = _data;
    if (buf.length < 10) throw WebpFormatException('Truncated VP8 header');
    final bits = buf[0] | (buf[1] << 8) | (buf[2] << 16);
    final keyFrame = (bits & 1) == 0;
    _profile = (bits >> 1) & 7;
    final show = (bits >> 4) & 1;
    _partitionLength = bits >> 5;
    if (!keyFrame) throw WebpFormatException('Not a VP8 key frame');
    if (_profile > 3) throw WebpFormatException('Incorrect VP8 profile');
    if (show == 0) throw WebpFormatException('VP8 frame not displayable');
    if (!checkSignature(buf, 3)) throw WebpFormatException('Bad VP8 signature');
    width = ((buf[7] << 8) | buf[6]) & 0x3fff;
    height = ((buf[9] << 8) | buf[8]) & 0x3fff;
    if (width == 0 || height == 0) {
      throw WebpFormatException('Invalid VP8 dimensions');
    }
    mbW = (width + 15) >> 4;
    mbH = (height + 15) >> 4;
    var pos = 10;
    if (_partitionLength > buf.length - pos) {
      throw WebpFormatException('Bad VP8 partition length');
    }
    final br = Vp8BoolReader(buf, pos, _partitionLength);
    _br = br;
    pos += _partitionLength;
    br.getBit(0x80); // colorspace
    br.getBit(0x80); // clamp type
    _parseSegmentHeader(br);
    _parseFilterHeader(br);
    _parsePartitions(buf, pos);
    _parseQuant(br);
    br.getBit(0x80); // update_proba (ignored)
    _parseProba(br);
  }

  void _parseSegmentHeader(Vp8BoolReader br) {
    _useSegment = br.getBit(0x80) != 0;
    if (_useSegment) {
      _updateMap = br.getBit(0x80) != 0;
      if (br.getBit(0x80) != 0) {
        _absoluteDelta = br.getBit(0x80) != 0;
        for (var s = 0; s < numMbSegments; s++) {
          _segQuantizer[s] = br.getBit(0x80) != 0 ? br.getSignedValue(7) : 0;
        }
        for (var s = 0; s < numMbSegments; s++) {
          _segFilterStrength[s] = br.getBit(0x80) != 0
              ? br.getSignedValue(6)
              : 0;
        }
      }
      if (_updateMap) {
        for (var s = 0; s < 3; s++) {
          _segmentProbas[s] = br.getBit(0x80) != 0 ? br.getValue(8) : 255;
        }
      }
    } else {
      _updateMap = false;
    }
    if (br.eof) throw WebpFormatException('Cannot parse VP8 segment header');
  }

  void _parseFilterHeader(Vp8BoolReader br) {
    _filterSimple = br.getBit(0x80) != 0;
    _filterLevel = br.getValue(6);
    _filterSharpness = br.getValue(3);
    _useLfDelta = br.getBit(0x80) != 0;
    if (_useLfDelta) {
      if (br.getBit(0x80) != 0) {
        for (var i = 0; i < 4; i++) {
          if (br.getBit(0x80) != 0) _refLfDelta[i] = br.getSignedValue(6);
        }
        for (var i = 0; i < 4; i++) {
          if (br.getBit(0x80) != 0) _modeLfDelta[i] = br.getSignedValue(6);
        }
      }
    }
    _filterType = _filterLevel == 0 ? 0 : (_filterSimple ? 1 : 2);
    if (br.eof) throw WebpFormatException('Cannot parse VP8 filter header');
  }

  void _parsePartitions(Uint8List buf, int pos) {
    final br = _br;
    _numPartsMinusOne = (1 << br.getValue(2)) - 1;
    final lastPart = _numPartsMinusOne;
    final size = buf.length - pos;
    if (size < 3 * lastPart) {
      throw WebpFormatException('Cannot parse VP8 partitions');
    }
    var partStart = pos + lastPart * 3;
    var sizeLeft = size - lastPart * 3;
    _parts = <Vp8BoolReader>[];
    var sz = pos;
    for (var p = 0; p < lastPart; p++) {
      var psize = buf[sz] | (buf[sz + 1] << 8) | (buf[sz + 2] << 16);
      if (psize > sizeLeft) psize = sizeLeft;
      _parts.add(Vp8BoolReader(buf, partStart, psize));
      partStart += psize;
      sizeLeft -= psize;
      sz += 3;
    }
    _parts.add(Vp8BoolReader(buf, partStart, sizeLeft));
    if (partStart >= buf.length) {
      throw WebpFormatException('Truncated VP8 partitions');
    }
  }

  static int _clip(int v, int m) => v < 0 ? 0 : (v > m ? m : v);

  void _parseQuant(Vp8BoolReader br) {
    final baseQ0 = br.getValue(7);
    final dqy1Dc = br.getBit(0x80) != 0 ? br.getSignedValue(4) : 0;
    final dqy2Dc = br.getBit(0x80) != 0 ? br.getSignedValue(4) : 0;
    final dqy2Ac = br.getBit(0x80) != 0 ? br.getSignedValue(4) : 0;
    final dquvDc = br.getBit(0x80) != 0 ? br.getSignedValue(4) : 0;
    final dquvAc = br.getBit(0x80) != 0 ? br.getSignedValue(4) : 0;
    for (var i = 0; i < numMbSegments; i++) {
      int q;
      if (_useSegment) {
        q = _segQuantizer[i];
        if (!_absoluteDelta) q += baseQ0;
      } else {
        if (i > 0) {
          final m = _dqm[i];
          final m0 = _dqm[0];
          m.y1.setAll(0, m0.y1);
          m.y2.setAll(0, m0.y2);
          m.uv.setAll(0, m0.uv);
          continue;
        }
        q = baseQ0;
      }
      final m = _dqm[i];
      m.y1[0] = dcTable[_clip(q + dqy1Dc, 127)];
      m.y1[1] = acTable[_clip(q, 127)];
      m.y2[0] = dcTable[_clip(q + dqy2Dc, 127)] * 2;
      m.y2[1] = (acTable[_clip(q + dqy2Ac, 127)] * 101581) >> 16;
      if (m.y2[1] < 8) m.y2[1] = 8;
      m.uv[0] = dcTable[_clip(q + dquvDc, 117)];
      m.uv[1] = acTable[_clip(q + dquvAc, 127)];
    }
  }

  void _parseProba(Vp8BoolReader br) {
    final n = _proba.length;
    for (var i = 0; i < n; i++) {
      _proba[i] = br.getBit(coeffsUpdateProba[i]) != 0
          ? br.getValue(8)
          : coeffsProba0[i];
    }
    _useSkipProba = br.getBit(0x80) != 0;
    if (_useSkipProba) _skipP = br.getValue(8);
  }

  //----------------------------------------------------------------------------
  // Intra modes (partition 0)

  void _parseIntraModeRow() {
    final br = _br;
    for (var mbX = 0; mbX < mbW; mbX++) {
      final topOff = 4 * mbX;
      final block = _mbData[mbX];
      if (_updateMap) {
        block.segment = br.getBit(_segmentProbas[0]) == 0
            ? br.getBit(_segmentProbas[1])
            : br.getBit(_segmentProbas[2]) + 2;
      } else {
        block.segment = 0;
      }
      if (_useSkipProba) block.skip = br.getBit(_skipP) != 0;
      block.isI4x4 = br.getBit(145) == 0;
      if (!block.isI4x4) {
        final ymode = br.getBit(156) != 0
            ? (br.getBit(128) != 0 ? tmPred : hPred)
            : (br.getBit(163) != 0 ? vPred : dcPred);
        block.imodes[0] = ymode;
        for (var i = 0; i < 4; i++) {
          _intraT[topOff + i] = ymode;
          _intraL[i] = ymode;
        }
      } else {
        var m = 0;
        for (var y = 0; y < 4; y++) {
          var ymode = _intraL[y];
          for (var x = 0; x < 4; x++) {
            final p =
                (_intraT[topOff + x] * numBModes + ymode) * (numBModes - 1);
            final prob = bModesProba;
            ymode = br.getBit(prob[p]) == 0
                ? bDcPred
                : br.getBit(prob[p + 1]) == 0
                ? bTmPred
                : br.getBit(prob[p + 2]) == 0
                ? bVePred
                : br.getBit(prob[p + 3]) == 0
                ? (br.getBit(prob[p + 4]) == 0
                      ? bHePred
                      : (br.getBit(prob[p + 5]) == 0 ? bRdPred : bVrPred))
                : (br.getBit(prob[p + 6]) == 0
                      ? bLdPred
                      : (br.getBit(prob[p + 7]) == 0
                            ? bVlPred
                            : (br.getBit(prob[p + 8]) == 0
                                  ? bHdPred
                                  : bHuPred)));
            _intraT[topOff + x] = ymode;
            block.imodes[m++] = ymode;
          }
          _intraL[y] = ymode;
        }
      }
      block.uvmode = br.getBit(142) == 0
          ? dcPred
          : br.getBit(114) == 0
          ? vPred
          : (br.getBit(183) != 0 ? tmPred : hPred);
    }
  }

  //----------------------------------------------------------------------------
  // Residuals (paragraph 13)

  int _getLargeValue(Vp8BoolReader br, Uint8List p, int po) {
    int v;
    if (br.getBit(p[po + 3]) == 0) {
      if (br.getBit(p[po + 4]) == 0) {
        v = 2;
      } else {
        v = 3 + br.getBit(p[po + 5]);
      }
    } else {
      if (br.getBit(p[po + 6]) == 0) {
        if (br.getBit(p[po + 7]) == 0) {
          v = 5 + br.getBit(159);
        } else {
          v = 7 + 2 * br.getBit(165);
          v += br.getBit(145);
        }
      } else {
        final bit1 = br.getBit(p[po + 8]);
        final bit0 = br.getBit(p[po + 9 + bit1]);
        final cat = 2 * bit1 + bit0;
        v = 0;
        final tab = cat3456[cat];
        for (final t in tab) {
          v += v + br.getBit(t);
        }
        v += 3 + (8 << cat);
      }
    }
    return v;
  }

  /// Offset of `probas[type][band][ctx]` in the flat probability array.
  static int _probaOffset(int type, int band, int ctx) =>
      ((type * numBands + band) * numCtx + ctx) * numProbas;

  /// Returns the position of the last non-zero coefficient plus one.
  int _getCoeffs(
    Vp8BoolReader br,
    int type,
    int ctx,
    Int32List dq,
    int n,
    Int16List out,
    int outOff,
  ) {
    final p = _proba;
    var po = _probaOffset(type, bands[n], ctx);
    for (; n < 16; n++) {
      if (br.getBit(p[po]) == 0) {
        return n; // previous coeff was last non-zero coeff
      }
      while (br.getBit(p[po + 1]) == 0) {
        n++;
        po = _probaOffset(type, bands[n], 0);
        if (n == 16) return 16;
      }
      int v;
      if (br.getBit(p[po + 2]) == 0) {
        v = 1;
        po = _probaOffset(type, bands[n + 1], 1);
      } else {
        v = _getLargeValue(br, p, po);
        po = _probaOffset(type, bands[n + 1], 2);
      }
      out[outOff + zigzag[n]] = br.getSigned(v) * dq[n > 0 ? 1 : 0];
    }
    return 16;
  }

  static int _nzCodeBits(int nzCoeffs, int nz, int dcNz) {
    nzCoeffs <<= 2;
    nzCoeffs |= nz > 3 ? 3 : (nz > 1 ? 2 : dcNz);
    return nzCoeffs;
  }

  final _dcTmp = Int16List(16);

  /// Returns true if the macroblock has no non-zero coefficient.
  bool _parseResiduals(int mbX, _MbData block, Vp8BoolReader tokenBr) {
    final q = _dqm[block.segment];
    final dst = block.coeffs;
    dst.fillRange(0, 384, 0);
    var dstOff = 0;
    int first;
    int acType;
    final mb = mbX + 1;
    const left = 0; // single shared left context
    if (!block.isI4x4) {
      final dc = _dcTmp;
      dc.fillRange(0, 16, 0);
      final ctx = _mbNzDc[mb] + _mbNzDc[left];
      final nz = _getCoeffs(tokenBr, 1, ctx, q.y2, 0, dc, 0);
      _mbNzDc[mb] = _mbNzDc[left] = nz > 0 ? 1 : 0;
      if (nz > 1) {
        transformWht(dc, 0, dst, 0);
      } else {
        final dc0 = sar(dc[0] + 3, 3);
        for (var i = 0; i < 16 * 16; i += 16) {
          dst[i] = dc0;
        }
      }
      first = 1;
      acType = 0;
    } else {
      first = 0;
      acType = 3;
    }
    var tnz = _mbNz[mb] & 0x0f;
    var lnz = _mbNz[left] & 0x0f;
    var nonZeroY = 0;
    for (var y = 0; y < 4; y++) {
      var l = lnz & 1;
      var nzCoeffs = 0;
      for (var x = 0; x < 4; x++) {
        final ctx = l + (tnz & 1);
        final nz = _getCoeffs(tokenBr, acType, ctx, q.y1, first, dst, dstOff);
        l = nz > first ? 1 : 0;
        tnz = (tnz >> 1) | (l << 7);
        nzCoeffs = _nzCodeBits(nzCoeffs, nz, dst[dstOff] != 0 ? 1 : 0);
        dstOff += 16;
      }
      tnz >>= 4;
      lnz = (lnz >> 1) | (l << 7);
      nonZeroY = (nonZeroY << 8) | nzCoeffs;
    }
    var outTnz = tnz;
    var outLnz = lnz >> 4;
    var nonZeroUv = 0;
    for (var ch = 0; ch < 4; ch += 2) {
      var nzCoeffs = 0;
      tnz = _mbNz[mb] >> (4 + ch);
      lnz = _mbNz[left] >> (4 + ch);
      var l = 0;
      for (var y = 0; y < 2; y++) {
        l = lnz & 1;
        for (var x = 0; x < 2; x++) {
          final ctx = l + (tnz & 1);
          final nz = _getCoeffs(tokenBr, 2, ctx, q.uv, 0, dst, dstOff);
          l = nz > 0 ? 1 : 0;
          tnz = (tnz >> 1) | (l << 3);
          nzCoeffs = _nzCodeBits(nzCoeffs, nz, dst[dstOff] != 0 ? 1 : 0);
          dstOff += 16;
        }
        tnz >>= 2;
        lnz = (lnz >> 1) | (l << 5);
      }
      nonZeroUv |= nzCoeffs << (4 * ch);
      outTnz |= (tnz << 4) << ch;
      outLnz |= (lnz & 0xf0) << ch;
    }
    _mbNz[mb] = outTnz;
    _mbNz[left] = outLnz;
    block.nonZeroY = nonZeroY;
    block.nonZeroUv = nonZeroUv;
    return (nonZeroY | nonZeroUv) == 0;
  }

  void _decodeMb(int mbX, Vp8BoolReader tokenBr) {
    final block = _mbData[mbX];
    var skip = _useSkipProba ? block.skip : false;
    if (!skip) {
      skip = _parseResiduals(mbX, block, tokenBr);
    } else {
      _mbNz[0] = _mbNz[mbX + 1] = 0;
      if (!block.isI4x4) {
        _mbNzDc[0] = _mbNzDc[mbX + 1] = 0;
      }
      block.nonZeroY = 0;
      block.nonZeroUv = 0;
    }
    if (_filterType > 0) {
      final finfo = _fInfo[mbX];
      finfo.copyFrom(_fstrengths[block.segment][block.isI4x4 ? 1 : 0]);
      finfo.fInner = finfo.fInner || !skip;
    }
  }

  //----------------------------------------------------------------------------
  // Reconstruction

  static int _checkMode(int mbX, int mbY, int mode) {
    if (mode == bDcPred) {
      if (mbX == 0) {
        return mbY == 0 ? bDcPredNoTopLeft : bDcPredNoLeft;
      } else {
        return mbY == 0 ? bDcPredNoTop : bDcPred;
      }
    }
    return mode;
  }

  static const _kScan = [
    0 + 0 * bps, 4 + 0 * bps, 8 + 0 * bps, 12 + 0 * bps, //
    0 + 4 * bps, 4 + 4 * bps, 8 + 4 * bps, 12 + 4 * bps, //
    0 + 8 * bps, 4 + 8 * bps, 8 + 8 * bps, 12 + 8 * bps, //
    0 + 12 * bps, 4 + 12 * bps, 8 + 12 * bps, 12 + 12 * bps, //
  ];

  void _doTransform(
    int bits,
    Int16List src,
    int srcOff,
    Uint8List dst,
    int dstOff,
  ) {
    switch (bits >>> 30) {
      case 3:
      case 2:
        transformOne(src, srcOff, dst, dstOff, bps);
      case 1:
        transformDc(src, srcOff, dst, dstOff, bps);
      default:
        break;
    }
  }

  void _doUvTransform(
    int bits,
    Int16List src,
    int srcOff,
    Uint8List dst,
    int dstOff,
  ) {
    if ((bits & 0xff) != 0) {
      if ((bits & 0xaa) != 0) {
        transformOne(src, srcOff, dst, dstOff, bps);
        transformOne(src, srcOff + 16, dst, dstOff + 4, bps);
        transformOne(src, srcOff + 32, dst, dstOff + 4 * bps, bps);
        transformOne(src, srcOff + 48, dst, dstOff + 4 * bps + 4, bps);
      } else {
        if (src[srcOff] != 0) transformDc(src, srcOff, dst, dstOff, bps);
        if (src[srcOff + 16] != 0) {
          transformDc(src, srcOff + 16, dst, dstOff + 4, bps);
        }
        if (src[srcOff + 32] != 0) {
          transformDc(src, srcOff + 32, dst, dstOff + 4 * bps, bps);
        }
        if (src[srcOff + 48] != 0) {
          transformDc(src, srcOff + 48, dst, dstOff + 4 * bps + 4, bps);
        }
      }
    }
  }

  void _reconstructRow(int mbY) {
    final yDst = _yuvB;
    // Initialize left-most block.
    for (var j = 0; j < 16; j++) {
      yDst[yOff + j * bps - 1] = 129;
    }
    for (var j = 0; j < 8; j++) {
      yDst[uOff + j * bps - 1] = 129;
      yDst[vOff + j * bps - 1] = 129;
    }
    if (mbY > 0) {
      yDst[yOff - 1 - bps] = 129;
      yDst[uOff - 1 - bps] = 129;
      yDst[vOff - 1 - bps] = 129;
    } else {
      yDst.fillRange(yOff - bps - 1, yOff - bps - 1 + 16 + 4 + 1, 127);
      yDst.fillRange(uOff - bps - 1, uOff - bps - 1 + 8 + 1, 127);
      yDst.fillRange(vOff - bps - 1, vOff - bps - 1 + 8 + 1, 127);
    }
    final ys = yStride;
    final uvs = uvStride;
    for (var mbX = 0; mbX < mbW; mbX++) {
      final block = _mbData[mbX];
      // Rotate in the left samples from previously decoded block.
      if (mbX > 0) {
        for (var j = -1; j < 16; j++) {
          final o = yOff + j * bps;
          yDst[o - 4] = yDst[o + 12];
          yDst[o - 3] = yDst[o + 13];
          yDst[o - 2] = yDst[o + 14];
          yDst[o - 1] = yDst[o + 15];
        }
        for (var j = -1; j < 8; j++) {
          var o = uOff + j * bps;
          yDst[o - 4] = yDst[o + 4];
          yDst[o - 3] = yDst[o + 5];
          yDst[o - 2] = yDst[o + 6];
          yDst[o - 1] = yDst[o + 7];
          o = vOff + j * bps;
          yDst[o - 4] = yDst[o + 4];
          yDst[o - 3] = yDst[o + 5];
          yDst[o - 2] = yDst[o + 6];
          yDst[o - 1] = yDst[o + 7];
        }
      }
      final topOff = mbX * 32;
      final coeffs = block.coeffs;
      var bits = block.nonZeroY;
      if (mbY > 0) {
        yDst.setRange(yOff - bps, yOff - bps + 16, _yuvT, topOff);
        yDst.setRange(uOff - bps, uOff - bps + 8, _yuvT, topOff + 16);
        yDst.setRange(vOff - bps, vOff - bps + 8, _yuvT, topOff + 24);
      }
      if (block.isI4x4) {
        final topRight = yOff - bps + 16;
        if (mbY > 0) {
          if (mbX >= mbW - 1) {
            yDst.fillRange(topRight, topRight + 4, _yuvT[topOff + 15]);
          } else {
            yDst.setRange(topRight, topRight + 4, _yuvT, topOff + 32);
          }
        }
        // Replicate the top-right pixels below.
        for (var k = 1; k <= 3; k++) {
          yDst.setRange(
            topRight + k * 4 * bps,
            topRight + k * 4 * bps + 4,
            yDst,
            topRight,
          );
        }
        for (var n = 0; n < 16; n++, bits = (bits << 2) & 0xffffffff) {
          final dst = yOff + _kScan[n];
          predLuma4(block.imodes[n], yDst, dst, bps);
          _doTransform(bits, coeffs, n * 16, yDst, dst);
        }
      } else {
        final predFunc = _checkMode(mbX, mbY, block.imodes[0]);
        predLuma16(predFunc, yDst, yOff, bps);
        if (bits != 0) {
          for (var n = 0; n < 16; n++, bits = (bits << 2) & 0xffffffff) {
            _doTransform(bits, coeffs, n * 16, yDst, yOff + _kScan[n]);
          }
        }
      }
      // Chroma.
      final bitsUv = block.nonZeroUv;
      final predFunc = _checkMode(mbX, mbY, block.uvmode);
      predChroma8(predFunc, yDst, uOff, bps);
      predChroma8(predFunc, yDst, vOff, bps);
      _doUvTransform(bitsUv, coeffs, 16 * 16, yDst, uOff);
      _doUvTransform(bitsUv >> 8, coeffs, 20 * 16, yDst, vOff);
      // Stash away top samples for next block.
      if (mbY < mbH - 1) {
        _yuvT.setRange(topOff, topOff + 16, yDst, yOff + 15 * bps);
        _yuvT.setRange(topOff + 16, topOff + 24, yDst, uOff + 7 * bps);
        _yuvT.setRange(topOff + 24, topOff + 32, yDst, vOff + 7 * bps);
      }
      // Transfer to the output planes.
      final yOut = mbY * 16 * ys + mbX * 16;
      final uvOut = mbY * 8 * uvs + mbX * 8;
      for (var j = 0; j < 16; j++) {
        yPlane.setRange(
          yOut + j * ys,
          yOut + j * ys + 16,
          yDst,
          yOff + j * bps,
        );
      }
      for (var j = 0; j < 8; j++) {
        uPlane.setRange(
          uvOut + j * uvs,
          uvOut + j * uvs + 8,
          yDst,
          uOff + j * bps,
        );
        vPlane.setRange(
          uvOut + j * uvs,
          uvOut + j * uvs + 8,
          yDst,
          vOff + j * bps,
        );
      }
    }
  }

  //----------------------------------------------------------------------------
  // Filtering

  void _precomputeFilterStrengths() {
    if (_filterType == 0) return;
    for (var s = 0; s < numMbSegments; s++) {
      int baseLevel;
      if (_useSegment) {
        baseLevel = _segFilterStrength[s];
        if (!_absoluteDelta) baseLevel += _filterLevel;
      } else {
        baseLevel = _filterLevel;
      }
      for (var i4x4 = 0; i4x4 <= 1; i4x4++) {
        final info = _fstrengths[s][i4x4];
        var level = baseLevel;
        if (_useLfDelta) {
          level += _refLfDelta[0];
          if (i4x4 != 0) level += _modeLfDelta[0];
        }
        level = level < 0 ? 0 : (level > 63 ? 63 : level);
        if (level > 0) {
          var ilevel = level;
          if (_filterSharpness > 0) {
            if (_filterSharpness > 4) {
              ilevel >>= 2;
            } else {
              ilevel >>= 1;
            }
            if (ilevel > 9 - _filterSharpness) ilevel = 9 - _filterSharpness;
          }
          if (ilevel < 1) ilevel = 1;
          info.fIlevel = ilevel;
          info.fLimit = 2 * level + ilevel;
          info.hevThresh = level >= 40 ? 2 : (level >= 15 ? 1 : 0);
        } else {
          info.fLimit = 0;
        }
        info.fInner = i4x4 != 0;
      }
    }
  }

  void _doFilter(int mbX, int mbY) {
    final ys = yStride;
    final fInfo = _fInfo[mbX];
    final yDst = mbY * 16 * ys + mbX * 16;
    final ilevel = fInfo.fIlevel;
    final limit = fInfo.fLimit;
    if (limit == 0) return;
    if (_filterType == 1) {
      if (mbX > 0) simpleHFilter16(yPlane, yDst, ys, limit + 4);
      if (fInfo.fInner) simpleHFilter16i(yPlane, yDst, ys, limit);
      if (mbY > 0) simpleVFilter16(yPlane, yDst, ys, limit + 4);
      if (fInfo.fInner) simpleVFilter16i(yPlane, yDst, ys, limit);
    } else {
      final uvs = uvStride;
      final uvDst = mbY * 8 * uvs + mbX * 8;
      final hev = fInfo.hevThresh;
      if (mbX > 0) {
        hFilter16(yPlane, yDst, ys, limit + 4, ilevel, hev);
        hFilter8(uPlane, uvDst, uvs, limit + 4, ilevel, hev);
        hFilter8(vPlane, uvDst, uvs, limit + 4, ilevel, hev);
      }
      if (fInfo.fInner) {
        hFilter16i(yPlane, yDst, ys, limit, ilevel, hev);
        hFilter8i(uPlane, uvDst, uvs, limit, ilevel, hev);
        hFilter8i(vPlane, uvDst, uvs, limit, ilevel, hev);
      }
      if (mbY > 0) {
        vFilter16(yPlane, yDst, ys, limit + 4, ilevel, hev);
        vFilter8(uPlane, uvDst, uvs, limit + 4, ilevel, hev);
        vFilter8(vPlane, uvDst, uvs, limit + 4, ilevel, hev);
      }
      if (fInfo.fInner) {
        vFilter16i(yPlane, yDst, ys, limit, ilevel, hev);
        vFilter8i(uPlane, uvDst, uvs, limit, ilevel, hev);
        vFilter8i(vPlane, uvDst, uvs, limit, ilevel, hev);
      }
    }
  }

  //----------------------------------------------------------------------------
  // Main loop

  /// Decodes the frame into [yPlane], [uPlane] and [vPlane].
  void decode() {
    _intraT = Uint8List(4 * mbW);
    _mbNz = Uint8List(mbW + 1);
    _mbNzDc = Uint8List(mbW + 1);
    _mbData = List.generate(mbW, (_) => _MbData());
    _fInfo = List.generate(mbW, (_) => _FInfo());
    _yuvT = Uint8List(32 * mbW);
    yPlane = Uint8List(yStride * mbH * 16);
    uPlane = Uint8List(uvStride * mbH * 8);
    vPlane = Uint8List(uvStride * mbH * 8);
    _precomputeFilterStrengths();
    _intraT.fillRange(0, _intraT.length, bDcPred);
    for (var mbY = 0; mbY < mbH; mbY++) {
      final tokenBr = _parts[mbY & _numPartsMinusOne];
      // Init scanline.
      _mbNz[0] = 0;
      _mbNzDc[0] = 0;
      _intraL.fillRange(0, 4, bDcPred);
      _parseIntraModeRow();
      if (_br.eof) {
        throw WebpFormatException('Premature end of VP8 partition 0');
      }
      for (var mbX = 0; mbX < mbW; mbX++) {
        _decodeMb(mbX, tokenBr);
        if (tokenBr.eof) {
          throw WebpFormatException('Premature end of VP8 data');
        }
      }
      _reconstructRow(mbY);
      if (_filterType > 0) {
        for (var mbX = 0; mbX < mbW; mbX++) {
          _doFilter(mbX, mbY);
        }
      }
    }
  }
}
