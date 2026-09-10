/// VP8 (lossy) key-frame encoder, ported from libwebp.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../int_utils.dart';
import 'bool_writer.dart';
import 'cost.dart';
import 'dsp.dart' show bps;
import 'enc_dsp.dart';
import 'tables.dart';
import 'yuv.dart';

/// Configuration of the lossy encoder (mirrors libwebp's `WebPConfig`).
class Vp8EncoderConfig {
  /// Quality factor (0..100).
  final double quality;

  /// Compression method (0 fastest .. 6 slowest/best).
  final int method;

  /// Spatial noise shaping (0..100).
  final int snsStrength;

  /// Loop filter strength (0 = off .. 100).
  final int filterStrength;

  /// Loop filter sharpness (0..7).
  final int filterSharpness;

  /// Filter type: 0 = simple, 1 = strong.
  final int filterType;

  /// Number of segments (1..4).
  final int segments;

  /// Number of entropy analysis passes (1..10).
  final int pass;

  /// Preserve the RGB values of transparent pixels.
  final bool exact;

  /// Whether to emulate JPEG sizes (unused, kept for parity).
  final bool emulateJpegSize;

  /// Creates a configuration.
  const Vp8EncoderConfig({
    this.quality = 75,
    this.method = 4,
    this.snsStrength = 50,
    this.filterStrength = 60,
    this.filterSharpness = 0,
    this.filterType = 1,
    this.segments = 4,
    this.pass = 1,
    this.exact = false,
    this.emulateJpegSize = false,
  });
}

const _maxCost = 0x1fffffffffffff; // 2^53 - 1, JavaScript safe
const _rdDistoMult = 256;
const _flatnessLimitI16 = 0;
const _flatnessLimitI4 = 3;
const _flatnessLimitUv = 2;
const _flatnessPenalty = 140;
const _midAlpha = 64;
const _minAlpha = 30;
const _maxAlpha = 100;
const _snsToDq = 0.9;
const _maxDqUv = 6;
const _minDqUv = -4;
const _errorDiffusionQuality = 98;

int _bias(int b) => b << (qfix - 8);
int _clip(int v, int m, int mm) => v < m ? m : (v > mm ? mm : v);

/// Rate-distortion optimization levels.
enum _RdOpt { none, basic, trellis, trellisAll }

class _MbInfo {
  int type = 1; // 0 = i4x4, 1 = i16x16
  int uvMode = 0;
  bool skip = false;
  int segment = 0;
  int alpha = 0;
}

class _SegmentInfo {
  final y1 = Vp8Matrix();
  final y2 = Vp8Matrix();
  final uv = Vp8Matrix();
  int alpha = 0;
  int beta = 0;
  int quant = 0;
  int fstrength = 0;
  int maxEdge = 0;
  int minDisto = 0;
  int lambdaI16 = 0;
  int lambdaI4 = 0;
  int lambdaUv = 0;
  int lambdaMode = 0;
  int lambdaTrellis = 0;
  int tlambda = 0;
  int lambdaTrellisI16 = 0;
  int lambdaTrellisI4 = 0;
  int lambdaTrellisUv = 0;
  int i4Penalty = 0;

  void copyFrom(_SegmentInfo o) {
    quant = o.quant;
    fstrength = o.fstrength;
    alpha = o.alpha;
    beta = o.beta;
  }
}

class _ModeScore {
  int d = 0;
  int sd = 0;
  int h = 0;
  int r = 0;
  int score = _maxCost;
  final yDcLevels = Int16List(16);
  final yAcLevels = Int16List(16 * 16);
  final uvLevels = Int16List(8 * 16);
  int modeI16 = 0;
  final modesI4 = Uint8List(16);
  int modeUv = 0;
  int nz = 0;
  final derr = Int32List(6); // [ch][3]

  void init() {
    d = 0;
    sd = 0;
    r = 0;
    h = 0;
    nz = 0;
    score = _maxCost;
  }

  void copyScore(_ModeScore src) {
    d = src.d;
    sd = src.sd;
    r = src.r;
    h = src.h;
    nz = src.nz;
    score = src.score;
  }

  void addScore(_ModeScore src) {
    d += src.d;
    sd += src.sd;
    r += src.r;
    h += src.h;
    nz |= src.nz;
    score += src.score;
  }

  void setRdScore(int lambda) {
    score = (r + h) * lambda + _rdDistoMult * (d + sd);
  }
}

/// Encoder state for one picture.
class Vp8Encoder {
  /// Encoding configuration.
  final Vp8EncoderConfig config;

  /// Source picture (YUV 4:2:0 planes).
  final YuvaPlanes pic;

  /// Picture width.
  final int width;

  /// Picture height.
  final int height;

  /// Dimensions in macroblocks.
  final int mbW;

  /// Height in macroblocks.
  final int mbH;
  final int _predsW;
  late final Uint8List _preds; // (4*mbH + 1) * predsW, border at row 0 / col 0
  late final Uint32List _nz; // mbW + 1, index 0 = left border
  late final Uint8List _yTop; // mbW * 16
  late final Uint8List _uvTop; // mbW * 16
  late final List<_MbInfo> _mbInfo;
  Int8List? _topDerr; // mbW * 4: [x][ch][2]

  final _dqm = List.generate(numMbSegments, (_) => _SegmentInfo());
  int _baseQuant = 0;
  int _alpha = 0;
  int _uvAlpha = 0;
  int _dqY1Dc = 0;
  int _dqY2Dc = 0;
  int _dqY2Ac = 0;
  int _dqUvDc = 0;
  int _dqUvAc = 0;

  /// Token probabilities and statistics.
  final proba = Vp8EncProba();

  // Segment header.
  int _numSegments = 1;
  bool _updateMap = false;
  int _segmentHdrSize = 0;

  // Filter header.
  bool _filterSimple = true;
  int _filterLevel = 0;
  int _filterSharpness = 0;

  late final int _method;
  late final _RdOpt _rdOptLevel;
  late int _maxI4HeaderBits;
  late final int _mbHeaderLimit;
  int _profile = 0;

  // Token partition writer.
  late Vp8BoolWriter _part;

  /// Creates an encoder for [pic] (YUV 4:2:0 planes).
  Vp8Encoder(this.pic, this.config)
    : width = pic.width,
      height = pic.height,
      mbW = (pic.width + 15) >> 4,
      mbH = (pic.height + 15) >> 4,
      _predsW = 4 * ((pic.width + 15) >> 4) + 1 {
    final predsH = 4 * mbH + 1;
    _preds = Uint8List(_predsW * predsH);
    _nz = Uint32List(mbW + 1);
    _yTop = Uint8List(mbW * 16);
    _uvTop = Uint8List(mbW * 16);
    _mbInfo = List.generate(mbW * mbH, (_) => _MbInfo());
    _method = config.method.clamp(0, 6);
    _rdOptLevel = _method >= 6
        ? _RdOpt.trellisAll
        : _method >= 5
        ? _RdOpt.trellis
        : _method >= 3
        ? _RdOpt.basic
        : _RdOpt.none;
    const limit = 100; // 100 - partition_limit (0)
    _maxI4HeaderBits = 256 * 16 * 16 * (limit * limit) ~/ (100 * 100);
    _mbHeaderLimit = 256 * 510 * 8 * 1024 ~/ (mbW * mbH);
    if (config.quality <= _errorDiffusionQuality || config.pass > 1) {
      _topDerr = Int8List(mbW * 4);
    }
    _numSegments = config.segments.clamp(1, 4);
    _updateMap = _numSegments > 1;
    final useFilter = config.filterStrength > 0;
    _profile = useFilter ? (config.filterType == 1 ? 0 : 1) : 2;
    proba.reset();
    _resetBoundaryPredictions();
  }

  int _predIndex(int x4, int y4) => (y4 + 1) * _predsW + (x4 + 1);

  void _resetBoundaryPredictions() {
    for (var i = -1; i < 4 * mbW; i++) {
      _preds[_predIndex(i, -1)] = bDcPred;
    }
    for (var i = 0; i < 4 * mbH; i++) {
      _preds[_predIndex(-1, i)] = bDcPred;
    }
    _nz[0] = 0;
  }

  //----------------------------------------------------------------------------
  // Iterator

  late final _Iterator _it = _Iterator(this);

  //----------------------------------------------------------------------------
  // Quantization setup (quant_enc.c)

  static const _kBiasMatrices = [
    [96, 110],
    [96, 108],
    [110, 115],
  ];
  static const _kFreqSharpening = [
    0,
    30,
    60,
    90,
    30,
    60,
    90,
    90,
    60,
    90,
    90,
    90,
    90,
    90,
    90,
    90,
  ];

  static int _expandMatrix(Vp8Matrix m, int type) {
    for (var i = 0; i < 2; i++) {
      final isAcCoeff = i > 0 ? 1 : 0;
      final bias = _kBiasMatrices[type][isAcCoeff];
      m.iq[i] = (1 << qfix) ~/ m.q[i];
      m.bias[i] = _bias(bias);
      m.zthresh[i] = ((1 << qfix) - 1 - m.bias[i]) ~/ m.iq[i];
    }
    for (var i = 2; i < 16; i++) {
      m.q[i] = m.q[1];
      m.iq[i] = m.iq[1];
      m.bias[i] = m.bias[1];
      m.zthresh[i] = m.zthresh[1];
    }
    var sum = 0;
    for (var i = 0; i < 16; i++) {
      if (type == 0) {
        m.sharpen[i] = (_kFreqSharpening[i] * m.q[i]) >> 11;
      } else {
        m.sharpen[i] = 0;
      }
      sum += m.q[i];
    }
    return (sum + 8) >> 4;
  }

  void _setupMatrices() {
    final tlambdaScale = _method >= 4 ? config.snsStrength : 0;
    for (var i = 0; i < _numSegments; i++) {
      final m = _dqm[i];
      final q = m.quant;
      m.y1.q[0] = dcTable[_clip(q + _dqY1Dc, 0, 127)];
      m.y1.q[1] = acTable[_clip(q, 0, 127)];
      m.y2.q[0] = dcTable[_clip(q + _dqY2Dc, 0, 127)] * 2;
      m.y2.q[1] = acTable2[_clip(q + _dqY2Ac, 0, 127)];
      m.uv.q[0] = dcTable[_clip(q + _dqUvDc, 0, 117)];
      m.uv.q[1] = acTable[_clip(q + _dqUvAc, 0, 127)];
      final qI4 = _expandMatrix(m.y1, 0);
      final qI16 = _expandMatrix(m.y2, 1);
      final qUv = _expandMatrix(m.uv, 2);
      m.lambdaI4 = (3 * qI4 * qI4) >> 7;
      m.lambdaI16 = 3 * qI16 * qI16;
      m.lambdaUv = (3 * qUv * qUv) >> 6;
      m.lambdaMode = (1 * qI4 * qI4) >> 7;
      m.lambdaTrellisI4 = (7 * qI4 * qI4) >> 3;
      m.lambdaTrellisI16 = (qI16 * qI16) >> 2;
      m.lambdaTrellisUv = (qUv * qUv) << 1;
      m.tlambda = (tlambdaScale * qI4) >> 5;
      if (m.lambdaI4 < 1) m.lambdaI4 = 1;
      if (m.lambdaI16 < 1) m.lambdaI16 = 1;
      if (m.lambdaUv < 1) m.lambdaUv = 1;
      if (m.lambdaMode < 1) m.lambdaMode = 1;
      if (m.lambdaTrellisI4 < 1) m.lambdaTrellisI4 = 1;
      if (m.lambdaTrellisI16 < 1) m.lambdaTrellisI16 = 1;
      if (m.lambdaTrellisUv < 1) m.lambdaTrellisUv = 1;
      if (m.tlambda < 1) m.tlambda = 1;
      m.minDisto = 20 * m.y1.q[0];
      m.maxEdge = 0;
      m.i4Penalty = 1000 * qI4 * qI4;
    }
  }

  static int _filterStrengthFromDelta(int sharpness, int delta) {
    final pos = delta < 64 ? delta : 63;
    return levelsFromDelta[sharpness * 64 + pos];
  }

  void _setupFilterStrength() {
    const fstrengthCutoff = 2;
    final level0 = 5 * config.filterStrength;
    for (var i = 0; i < numMbSegments; i++) {
      final m = _dqm[i];
      final qstep = acTable[_clip(m.quant, 0, 127)] >> 2;
      final baseStrength = _filterStrengthFromDelta(_filterSharpness, qstep);
      final f = baseStrength * level0 ~/ (256 + m.beta);
      m.fstrength = f < fstrengthCutoff ? 0 : (f > 63 ? 63 : f);
    }
    _filterLevel = _dqm[0].fstrength;
    _filterSimple = config.filterType == 0;
    _filterSharpness = config.filterSharpness;
  }

  static double _qualityToCompression(double c) {
    final linearC = c < 0.75 ? c * (2.0 / 3.0) : 2.0 * c - 1.0;
    return math.pow(linearC, 1 / 3.0).toDouble();
  }

  static double _qualityToJpegCompression(double c, double alpha) {
    const amin = 0.30;
    const amax = 0.85;
    const expMin = 0.4;
    const expMax = 0.9;
    const slope = (expMin - expMax) / (amax - amin);
    final expn = alpha > amax
        ? expMin
        : alpha < amin
        ? expMax
        : expMax + slope * (alpha - amin);
    return math.pow(c, expn).toDouble();
  }

  void _simplifySegments() {
    final map = [0, 1, 2, 3];
    final numSegments = _numSegments;
    var numFinalSegments = 1;
    for (var s1 = 1; s1 < numSegments; s1++) {
      final si1 = _dqm[s1];
      var found = false;
      var s2 = 0;
      for (; s2 < numFinalSegments; s2++) {
        final si2 = _dqm[s2];
        if (si1.quant == si2.quant && si1.fstrength == si2.fstrength) {
          found = true;
          break;
        }
      }
      map[s1] = s2;
      if (!found) {
        if (numFinalSegments != s1) {
          _dqm[numFinalSegments].copyFrom(_dqm[s1]);
        }
        numFinalSegments++;
      }
    }
    if (numFinalSegments < numSegments) {
      for (final mb in _mbInfo) {
        mb.segment = map[mb.segment];
      }
      _numSegments = numFinalSegments;
      for (var i = numFinalSegments; i < numSegments; i++) {
        _dqm[i].copyFrom(_dqm[numFinalSegments - 1]);
      }
    }
  }

  void _setSegmentParams(double quality) {
    final numSegments = _numSegments;
    final amp = _snsToDq * config.snsStrength / 100.0 / 128.0;
    final q = quality / 100.0;
    final cBase = config.emulateJpegSize
        ? _qualityToJpegCompression(q, _alpha / 255.0)
        : _qualityToCompression(q);
    for (var i = 0; i < numSegments; i++) {
      final expn = 1.0 - amp * _dqm[i].alpha;
      final c = math.pow(cBase, expn).toDouble();
      final qq = (127.0 * (1.0 - c)).toInt();
      _dqm[i].quant = _clip(qq, 0, 127);
    }
    _baseQuant = _dqm[0].quant;
    for (var i = numSegments; i < numMbSegments; i++) {
      _dqm[i].quant = _baseQuant;
    }
    var dqUvAc =
        (_uvAlpha - _midAlpha) *
        (_maxDqUv - _minDqUv) ~/
        (_maxAlpha - _minAlpha);
    dqUvAc = dqUvAc * config.snsStrength ~/ 100;
    dqUvAc = _clip(dqUvAc, _minDqUv, _maxDqUv);
    var dqUvDc = -4 * config.snsStrength ~/ 100;
    dqUvDc = _clip(dqUvDc, -15, 15);
    _dqY1Dc = 0;
    _dqY2Dc = 0;
    _dqY2Ac = 0;
    _dqUvDc = dqUvDc;
    _dqUvAc = dqUvAc;
    _setupFilterStrength();
    if (numSegments > 1) _simplifySegments();
    _setupMatrices();
  }

  //----------------------------------------------------------------------------
  // Analysis (analysis_enc.c)

  static const _maxAlphaValue = 255;
  static const _alphaScale = 2 * _maxAlphaValue;

  static int _getAlpha(List<int> histo) {
    final maxValue = histo[0];
    final lastNonZero = histo[1];
    return maxValue > 1 ? _alphaScale * lastNonZero ~/ maxValue : 0;
  }

  int _mbAnalyzeBestIntra16Mode(_Iterator it) {
    const maxMode = 2;
    var bestAlpha = -1;
    var bestMode = 0;
    it.makeLuma16Preds();
    for (var mode = 0; mode < maxMode; mode++) {
      final histo = collectHistogram(
        it.yuvIn,
        yOffEnc,
        it.yuvP,
        i16ModeOffsets[mode],
        0,
        16,
      );
      final alpha = _getAlpha(histo);
      if (alpha > bestAlpha) {
        bestAlpha = alpha;
        bestMode = mode;
      }
    }
    it.setIntra16Mode(bestMode);
    return bestAlpha;
  }

  final _dcTmp = Uint32List(16);

  int _fastMbAnalyze(_Iterator it) {
    final q = config.quality.toInt();
    final kThreshold = 8 + (17 - 8) * q ~/ 100;
    final dc = _dcTmp;
    for (var k = 0; k < 16; k += 4) {
      final sub = Uint32List(4);
      mean16x4(it.yuvIn, yOffEnc + k * bps, sub);
      dc.setRange(k, k + 4, sub);
    }
    var m = 0;
    var m2 = 0;
    for (var k = 0; k < 16; k++) {
      m += dc[k];
      m2 += dc[k] * dc[k];
    }
    if (kThreshold * m2 < m * m) {
      it.setIntra16Mode(0);
    } else {
      it.setIntra4Mode(Uint8List(16));
    }
    return 0;
  }

  int _mbAnalyzeBestUvMode(_Iterator it) {
    var bestAlpha = -1;
    var smallestAlpha = 0;
    var bestMode = 0;
    const maxMode = 2;
    it.makeChroma8Preds();
    for (var mode = 0; mode < maxMode; mode++) {
      final histo = collectHistogram(
        it.yuvIn,
        uOffEnc,
        it.yuvP,
        uvModeOffsets[mode],
        16,
        16 + 4 + 4,
      );
      final alpha = _getAlpha(histo);
      if (alpha > bestAlpha) bestAlpha = alpha;
      if (mode == 0 || alpha < smallestAlpha) {
        smallestAlpha = alpha;
        bestMode = mode;
      }
    }
    it.setIntraUvMode(bestMode);
    return bestAlpha;
  }

  void _mbAnalyze(_Iterator it, List<int> alphas, List<int> totals) {
    it.setIntra16Mode(0);
    it.setSkip(false);
    it.setSegment(0);
    int bestAlpha;
    if (_method <= 1) {
      bestAlpha = _fastMbAnalyze(it);
    } else {
      bestAlpha = _mbAnalyzeBestIntra16Mode(it);
    }
    final bestUvAlpha = _mbAnalyzeBestUvMode(it);
    bestAlpha = (3 * bestAlpha + bestUvAlpha + 2) >> 2;
    bestAlpha = _clip(_maxAlphaValue - bestAlpha, 0, _maxAlphaValue);
    alphas[bestAlpha]++;
    it.mb.alpha = bestAlpha;
    totals[0] += bestAlpha;
    totals[1] += bestUvAlpha;
  }

  void _setSegmentAlphas(List<int> centers, int mid) {
    final nb = _numSegments;
    var min = centers[0];
    var max = centers[0];
    if (nb > 1) {
      for (var n = 0; n < nb; n++) {
        if (min > centers[n]) min = centers[n];
        if (max < centers[n]) max = centers[n];
      }
    }
    if (max == min) max = min + 1;
    for (var n = 0; n < nb; n++) {
      final alpha = 255 * (centers[n] - mid) ~/ (max - min);
      final beta = 255 * (centers[n] - min) ~/ (max - min);
      _dqm[n].alpha = _clip(alpha, -127, 127);
      _dqm[n].beta = _clip(beta, 0, 255);
    }
  }

  void _assignSegments(List<int> alphas) {
    final nb = _numSegments;
    final centers = List<int>.filled(numMbSegments, 0);
    var weightedAverage = 0;
    final map = List<int>.filled(_maxAlphaValue + 1, 0);
    var n = 0;
    for (; n <= _maxAlphaValue && alphas[n] == 0; n++) {}
    final minA = n;
    for (n = _maxAlphaValue; n > minA && alphas[n] == 0; n--) {}
    final maxA = n;
    final rangeA = maxA - minA;
    for (var k = 0, nn = 1; k < nb; k++, nn += 2) {
      centers[k] = minA + (nn * rangeA) ~/ (2 * nb);
    }
    final accum = List<int>.filled(numMbSegments, 0);
    final distAccum = List<int>.filled(numMbSegments, 0);
    for (var k = 0; k < 6; k++) {
      for (n = 0; n < nb; n++) {
        accum[n] = 0;
        distAccum[n] = 0;
      }
      n = 0;
      for (var a = minA; a <= maxA; a++) {
        if (alphas[a] != 0) {
          while (n + 1 < nb &&
              (a - centers[n + 1]).abs() < (a - centers[n]).abs()) {
            n++;
          }
          map[a] = n;
          distAccum[n] += a * alphas[a];
          accum[n] += alphas[a];
        }
      }
      var displaced = 0;
      weightedAverage = 0;
      var totalWeight = 0;
      for (n = 0; n < nb; n++) {
        if (accum[n] != 0) {
          final newCenter = (distAccum[n] + accum[n] ~/ 2) ~/ accum[n];
          displaced += (centers[n] - newCenter).abs();
          centers[n] = newCenter;
          weightedAverage += newCenter * accum[n];
          totalWeight += accum[n];
        }
      }
      weightedAverage = (weightedAverage + totalWeight ~/ 2) ~/ totalWeight;
      if (displaced < 5) break;
    }
    for (final mb in _mbInfo) {
      final alpha = mb.alpha;
      mb.segment = map[alpha];
      mb.alpha = centers[map[alpha]];
    }
    _setSegmentAlphas(centers, weightedAverage);
  }

  void _analyze() {
    final doSegments =
        config.emulateJpegSize || _numSegments > 1 || _method <= 1;
    if (doSegments) {
      final alphas = List<int>.filled(_maxAlphaValue + 1, 0);
      final totals = [0, 0];
      final it = _it;
      it.reset();
      final tmp32 = Uint8List(32);
      do {
        it.import(tmp32);
        _mbAnalyze(it, alphas, totals);
      } while (it.next());
      final totalMb = mbW * mbH;
      _alpha = totals[0] ~/ totalMb;
      _uvAlpha = totals[1] ~/ totalMb;
      _assignSegments(alphas);
    } else {
      for (final mb in _mbInfo) {
        mb.type = 1;
        mb.uvMode = 0;
        mb.skip = false;
        mb.segment = 0;
        mb.alpha = 0;
      }
      _dqm[0].alpha = 0;
      _dqm[0].beta = 0;
      _alpha = 0;
      _uvAlpha = 0;
    }
  }

  //----------------------------------------------------------------------------
  // Trellis quantization

  static const _kWeightTrellis = [
    30,
    27,
    19,
    11,
    27,
    24,
    17,
    10,
    19,
    17,
    12,
    8,
    11,
    10,
    8,
    6,
  ];
  static const _kZigzag = [
    0,
    1,
    4,
    8,
    5,
    2,
    3,
    6,
    9,
    12,
    13,
    10,
    7,
    11,
    14,
    15,
  ];

  // Trellis nodes: [16][2] with fields prev, sign, level.
  final _nodePrev = Int8List(32);
  final _nodeSign = Int8List(32);
  final _nodeLevel = Int16List(32);
  final _ssScore = List<int>.filled(4, 0); // [2][2]
  final _ssCosts = List<int>.filled(4, 0);

  static int _rdScoreTrellis(int lambda, int rate, int distortion) =>
      rate * lambda + _rdDistoMult * distortion;

  int _trellisQuantizeBlock(
    Int16List input,
    int inOff,
    Int16List out,
    int outOff,
    int ctx0,
    int coeffType,
    Vp8Matrix mtx,
    int lambda,
  ) {
    const minDelta = 0;
    const maxDelta = 1;
    final first = coeffType == 0 ? 1 : 0;
    var ssCur = 0; // index of current score-state row (0 or 1) * 2
    var ssPrev = 2;
    final bestPath = [-1, -1, -1];
    int bestScore;
    var last = first - 1;
    {
      final thresh = mtx.q[1] * mtx.q[1] ~/ 4;
      final lastProba =
          proba.coeffs[Vp8EncProba.probaOffset(coeffType, bands[first], ctx0)];
      for (var n = 15; n >= first; n--) {
        final j = _kZigzag[n];
        final err = input[inOff + j] * input[inOff + j];
        if (err > thresh) {
          last = n;
          break;
        }
      }
      if (last < 15) last++;
      final cost = bitCost(0, lastProba);
      bestScore = _rdScoreTrellis(lambda, cost, 0);
      for (var m = -minDelta; m <= maxDelta; m++) {
        final rate = ctx0 == 0 ? bitCost(1, lastProba) : 0;
        _ssScore[ssCur + m + minDelta] = _rdScoreTrellis(lambda, rate, 0);
        _ssCosts[ssCur + m + minDelta] = proba.remappedCostOffset(
          coeffType,
          first,
          ctx0,
        );
      }
    }
    for (var n = first; n <= last; n++) {
      final j = _kZigzag[n];
      final q = mtx.q[j];
      final iQ = mtx.iq[j];
      final b = _bias(0x00);
      final sign = input[inOff + j] < 0;
      final coeff0 =
          (sign ? -input[inOff + j] : input[inOff + j]) + mtx.sharpen[j];
      var level0 = quantDiv(coeff0, iQ, b);
      var threshLevel = quantDiv(coeff0, iQ, _bias(0x80));
      if (threshLevel > maxLevel) threshLevel = maxLevel;
      if (level0 > maxLevel) level0 = maxLevel;
      {
        final tmp = ssCur;
        ssCur = ssPrev;
        ssPrev = tmp;
      }
      for (var m = -minDelta; m <= maxDelta; m++) {
        final nodeIdx = n * 2 + m + minDelta;
        final level = level0 + m;
        final ctx = level > 2 ? 2 : level;
        final band = bands[n + 1];
        if (n + 1 < 16) {
          _ssCosts[ssCur + m + minDelta] = proba.remappedCostOffset(
            coeffType,
            n + 1,
            ctx,
          );
        } else {
          _ssCosts[ssCur + m + minDelta] = -1;
        }
        if (level < 0 || level > threshLevel) {
          _ssScore[ssCur + m + minDelta] = _maxCost;
          continue;
        }
        int baseScore;
        {
          final newError = coeff0 - level * q;
          final deltaError =
              _kWeightTrellis[j] * (newError * newError - coeff0 * coeff0);
          baseScore = _rdScoreTrellis(lambda, 0, deltaError);
        }
        var cost = proba.levelCostAt(
          _ssCosts[ssPrev - minDelta + minDelta],
          level,
        );
        var bestCurScore = _ssScore[ssPrev] + _rdScoreTrellis(lambda, cost, 0);
        var bestPrev = -minDelta;
        for (var p = -minDelta + 1; p <= maxDelta; p++) {
          cost = proba.levelCostAt(_ssCosts[ssPrev + p + minDelta], level);
          final score =
              _ssScore[ssPrev + p + minDelta] +
              _rdScoreTrellis(lambda, cost, 0);
          if (score < bestCurScore) {
            bestCurScore = score;
            bestPrev = p;
          }
        }
        bestCurScore += baseScore;
        _nodeSign[nodeIdx] = sign ? 1 : 0;
        _nodeLevel[nodeIdx] = level;
        _nodePrev[nodeIdx] = bestPrev;
        _ssScore[ssCur + m + minDelta] = bestCurScore;
        if (level != 0 && bestCurScore < bestScore) {
          final lastPosCost = n < 15
              ? bitCost(
                  0,
                  proba.coeffs[Vp8EncProba.probaOffset(coeffType, band, ctx)],
                )
              : 0;
          final lastPosScore = _rdScoreTrellis(lambda, lastPosCost, 0);
          final score = bestCurScore + lastPosScore;
          if (score < bestScore) {
            bestScore = score;
            bestPath[0] = n;
            bestPath[1] = m;
            bestPath[2] = bestPrev;
          }
        }
      }
    }
    if (coeffType == 0) {
      input.fillRange(inOff + 1, inOff + 16, 0);
      out.fillRange(outOff + 1, outOff + 16, 0);
    } else {
      input.fillRange(inOff, inOff + 16, 0);
      out.fillRange(outOff, outOff + 16, 0);
    }
    if (bestPath[0] == -1) return 0;
    var nz = 0;
    var bestNode = bestPath[1];
    var n = bestPath[0];
    _nodePrev[n * 2 + bestNode + minDelta] = bestPath[2];
    for (; n >= first; n--) {
      final idx = n * 2 + bestNode + minDelta;
      final j = _kZigzag[n];
      final level = _nodeLevel[idx];
      out[outOff + n] = _nodeSign[idx] != 0 ? -level : level;
      nz |= level;
      input[inOff + j] = out[outOff + n] * mtx.q[j];
      bestNode = _nodePrev[idx];
    }
    return nz != 0 ? 1 : 0;
  }

  //----------------------------------------------------------------------------
  // Reconstruction

  final _tmp16 = Int16List(16 * 16);
  final _dcTmp16 = Int16List(16);
  final _tmp8 = Int16List(8 * 16);

  int _reconstructIntra16(
    _Iterator it,
    _ModeScore rd,
    int yuvOutOff,
    int mode,
  ) {
    final ref = i16ModeOffsets[mode];
    final dqm = _dqm[it.mb.segment];
    var nz = 0;
    final tmp = _tmp16;
    for (var n = 0; n < 16; n += 2) {
      fTransform2(
        it.yuvIn,
        yOffEnc + scan[n],
        it.yuvP,
        ref + scan[n],
        tmp,
        n * 16,
      );
    }
    fTransformWht(tmp, 0, _dcTmp16, 0);
    nz |= quantizeBlock(_dcTmp16, 0, rd.yDcLevels, 0, dqm.y2) << 24;
    if (it.doTrellis) {
      it.nzToBytes();
      for (var y = 0, n = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++, n++) {
          final ctx = it.topNz[x] + it.leftNz[y];
          final nonZero = _trellisQuantizeBlock(
            tmp,
            n * 16,
            rd.yAcLevels,
            n * 16,
            ctx,
            0,
            dqm.y1,
            dqm.lambdaTrellisI16,
          );
          it.topNz[x] = it.leftNz[y] = nonZero;
          rd.yAcLevels[n * 16] = 0;
          nz |= nonZero << n;
        }
      }
    } else {
      for (var n = 0; n < 16; n += 2) {
        tmp[n * 16] = 0;
        tmp[(n + 1) * 16] = 0;
        nz |= quantize2Blocks(tmp, n * 16, rd.yAcLevels, n * 16, dqm.y1) << n;
      }
    }
    // Transform back.
    _transformWhtToDc(_dcTmp16, tmp);
    for (var n = 0; n < 16; n += 2) {
      iTransform(
        it.yuvP,
        ref + scan[n],
        tmp,
        n * 16,
        it.yuvOut,
        yuvOutOff + scan[n],
        true,
      );
    }
    return nz;
  }

  static void _transformWhtToDc(Int16List input, Int16List out) {
    final tmp = Int32List(16);
    for (var i = 0; i < 4; i++) {
      final a0 = input[i] + input[12 + i];
      final a1 = input[4 + i] + input[8 + i];
      final a2 = input[4 + i] - input[8 + i];
      final a3 = input[i] - input[12 + i];
      tmp[i] = a0 + a1;
      tmp[8 + i] = a0 - a1;
      tmp[4 + i] = a3 + a2;
      tmp[12 + i] = a3 - a2;
    }
    var o = 0;
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

  final _tmp4 = Int16List(16);

  int _reconstructIntra4(
    _Iterator it,
    Int16List levels,
    int levelsOff,
    int srcOff,
    Uint8List dst,
    int dstOff,
    int mode,
  ) {
    final ref = i4ModeOffsets[mode];
    final dqm = _dqm[it.mb.segment];
    final tmp = _tmp4;
    fTransform(it.yuvIn, srcOff, it.yuvP, ref, tmp, 0);
    int nz;
    if (it.doTrellis) {
      final x = it.i4 & 3;
      final y = it.i4 >> 2;
      final ctx = it.topNz[x] + it.leftNz[y];
      nz = _trellisQuantizeBlock(
        tmp,
        0,
        levels,
        levelsOff,
        ctx,
        3,
        dqm.y1,
        dqm.lambdaTrellisI4,
      );
    } else {
      nz = quantizeBlock(tmp, 0, levels, levelsOff, dqm.y1);
    }
    iTransform(it.yuvP, ref, tmp, 0, dst, dstOff, false);
    return nz;
  }

  // DC error diffusion.
  static const _c1 = 7;
  static const _c2 = 8;
  static const _dshift = 4;
  static const _dscale = 1;

  static int _quantizeSingle(Int16List v, int off, Vp8Matrix mtx) {
    var vv = v[off];
    final sign = vv < 0;
    if (sign) vv = -vv;
    if (vv > mtx.zthresh[0]) {
      final qV = quantDiv(vv, mtx.iq[0], mtx.bias[0]) * mtx.q[0];
      final err = vv - qV;
      v[off] = sign ? -qV : qV;
      return sar(sign ? -err : err, _dscale);
    }
    v[off] = 0;
    return sar(sign ? -vv : vv, _dscale);
  }

  void _correctDcValues(
    _Iterator it,
    Vp8Matrix mtx,
    Int16List tmp,
    _ModeScore rd,
  ) {
    final topDerr = _topDerr!;
    for (var ch = 0; ch <= 1; ch++) {
      final top = it.x * 4 + ch * 2;
      final left = ch * 2;
      final c = ch * 4 * 16;
      tmp[c] += sar(
        _c1 * topDerr[top] + _c2 * it.leftDerr[left],
        _dshift - _dscale,
      );
      final err0 = _quantizeSingle(tmp, c, mtx);
      tmp[c + 16] += sar(
        _c1 * topDerr[top + 1] + _c2 * err0,
        _dshift - _dscale,
      );
      final err1 = _quantizeSingle(tmp, c + 16, mtx);
      tmp[c + 32] += sar(
        _c1 * err0 + _c2 * it.leftDerr[left + 1],
        _dshift - _dscale,
      );
      final err2 = _quantizeSingle(tmp, c + 32, mtx);
      tmp[c + 48] += sar(_c1 * err1 + _c2 * err2, _dshift - _dscale);
      final err3 = _quantizeSingle(tmp, c + 48, mtx);
      rd.derr[ch * 3] = err1;
      rd.derr[ch * 3 + 1] = err2;
      rd.derr[ch * 3 + 2] = err3;
    }
  }

  void _storeDiffusionErrors(_Iterator it, _ModeScore rd) {
    final topDerr = _topDerr!;
    for (var ch = 0; ch <= 1; ch++) {
      final top = it.x * 4 + ch * 2;
      final left = ch * 2;
      it.leftDerr[left] = rd.derr[ch * 3];
      it.leftDerr[left + 1] = sar(3 * rd.derr[ch * 3 + 2], 2);
      topDerr[top] = rd.derr[ch * 3 + 1];
      topDerr[top + 1] = rd.derr[ch * 3 + 2] - it.leftDerr[left + 1];
    }
  }

  int _reconstructUv(_Iterator it, _ModeScore rd, int yuvOutOff, int mode) {
    final ref = uvModeOffsets[mode];
    final dqm = _dqm[it.mb.segment];
    var nz = 0;
    final tmp = _tmp8;
    for (var n = 0; n < 8; n += 2) {
      fTransform2(
        it.yuvIn,
        uOffEnc + scanUv[n],
        it.yuvP,
        ref + scanUv[n],
        tmp,
        n * 16,
      );
    }
    if (_topDerr != null) _correctDcValues(it, dqm.uv, tmp, rd);
    for (var n = 0; n < 8; n += 2) {
      nz |= quantize2Blocks(tmp, n * 16, rd.uvLevels, n * 16, dqm.uv) << n;
    }
    for (var n = 0; n < 8; n += 2) {
      iTransform(
        it.yuvP,
        ref + scanUv[n],
        tmp,
        n * 16,
        it.yuvOut,
        yuvOutOff + scanUv[n],
        true,
      );
    }
    return nz << 16;
  }

  //----------------------------------------------------------------------------
  // Mode decision

  static const _kWeightY = [
    38,
    32,
    20,
    9,
    32,
    28,
    17,
    7,
    20,
    17,
    10,
    4,
    9,
    7,
    4,
    2,
  ];

  static bool _isFlat(Int16List levels, int off, int numBlocks, int thresh) {
    var score = 0;
    for (var b = 0; b < numBlocks; b++) {
      for (var i = 1; i < 16; i++) {
        if (levels[off + b * 16 + i] != 0) {
          score += 1;
          if (score > thresh) return false;
        }
      }
    }
    return true;
  }

  static bool _isFlatSource16(Uint8List src, int off) {
    final v = src[off];
    for (var i = 0; i < 16; i++) {
      final o = off + i * bps;
      for (var x = 0; x < 16; x++) {
        if (src[o + x] != v) return false;
      }
    }
    return true;
  }

  static int _mult8b(int a, int b) => (a * b + 128) >> 8;

  void _storeMaxDelta(_SegmentInfo dqm, Int16List dcs) {
    final v0 = dcs[1].abs();
    final v1 = dcs[2].abs();
    final v2 = dcs[4].abs();
    var maxV = v1 > v0 ? v1 : v0;
    maxV = v2 > maxV ? v2 : maxV;
    if (maxV > dqm.maxEdge) dqm.maxEdge = maxV;
  }

  final _rdTmp = _ModeScore();

  void _pickBestIntra16(_Iterator it, _ModeScore rd) {
    const kNumBlocks = 16;
    final dqm = _dqm[it.mb.segment];
    final lambda = dqm.lambdaI16;
    final tlambda = dqm.tlambda;
    var rdCur = _rdTmp;
    var rdBest = rd;
    var isFlat = _isFlatSource16(it.yuvIn, yOffEnc);
    rd.modeI16 = -1;
    for (var mode = 0; mode < numPredModes; mode++) {
      rdCur.modeI16 = mode;
      // Reconstruct into yuvOut2 (scratch).
      rdCur.nz = _reconstructIntra16Into(it, rdCur, it.yuvOut2, yOffEnc, mode);
      rdCur.d = sse16x16(it.yuvIn, yOffEnc, it.yuvOut2, yOffEnc);
      rdCur.sd = tlambda != 0
          ? _mult8b(
              tlambda,
              disto16x16(it.yuvIn, yOffEnc, it.yuvOut2, yOffEnc, _kWeightY),
            )
          : 0;
      rdCur.h = fixedCostsI16[mode];
      rdCur.r = _getCostLuma16(it, rdCur);
      if (isFlat) {
        isFlat = _isFlat(rdCur.yAcLevels, 0, kNumBlocks, _flatnessLimitI16);
        if (isFlat) {
          rdCur.d *= 2;
          rdCur.sd *= 2;
        }
      }
      rdCur.setRdScore(lambda);
      if (mode == 0 || rdCur.score < rdBest.score) {
        final tmp = rdCur;
        rdCur = rdBest;
        rdBest = tmp;
        it.swapOut();
      }
    }
    if (!identical(rdBest, rd)) {
      _copyModeScore(rdBest, rd);
    }
    rd.setRdScore(dqm.lambdaMode);
    it.setIntra16Mode(rd.modeI16);
    if ((rd.nz & 0x100ffff) == 0x1000000 && rd.d > dqm.minDisto) {
      _storeMaxDelta(dqm, rd.yDcLevels);
    }
  }

  static void _copyModeScore(_ModeScore src, _ModeScore dst) {
    dst.copyScore(src);
    dst.yDcLevels.setAll(0, src.yDcLevels);
    dst.yAcLevels.setAll(0, src.yAcLevels);
    dst.uvLevels.setAll(0, src.uvLevels);
    dst.modeI16 = src.modeI16;
    dst.modesI4.setAll(0, src.modesI4);
    dst.modeUv = src.modeUv;
    dst.derr.setAll(0, src.derr);
  }

  /// Same as [_reconstructIntra16] but writes into an explicit buffer.
  int _reconstructIntra16Into(
    _Iterator it,
    _ModeScore rd,
    Uint8List out,
    int outOff,
    int mode,
  ) {
    final saved = it.yuvOut;
    it.yuvOut = out;
    final nz = _reconstructIntra16(it, rd, outOff, mode);
    it.yuvOut = saved;
    return nz;
  }

  int _getCostModeI4Offset(_Iterator it, Uint8List modes) {
    final x = it.i4 & 3;
    final y = it.i4 >> 2;
    final left = x == 0 ? _preds[it.predsIndex(-1, y)] : modes[it.i4 - 1];
    final top = y == 0 ? _preds[it.predsIndex(x, -1)] : modes[it.i4 - 4];
    return (top * numBModes + left) * numBModes;
  }

  final _rdBestI4 = _ModeScore();
  final _rdI4 = _ModeScore();
  final _rdTmpI4 = _ModeScore();
  final _tmpLevels = Int16List(16);

  bool _pickBestIntra4(_Iterator it, _ModeScore rd) {
    final dqm = _dqm[it.mb.segment];
    final lambda = dqm.lambdaI4;
    final tlambda = dqm.tlambda;
    final bestBlocks = it.yuvOut2;
    var totalHeaderBits = 0;
    final rdBest = _rdBestI4;
    if (_maxI4HeaderBits == 0) return false;
    rdBest.init();
    rdBest.h = 211;
    rdBest.setRdScore(dqm.lambdaMode);
    it.startI4();
    do {
      const kNumBlocks = 1;
      final rdI4 = _rdI4;
      var bestMode = -1;
      final src = yOffEnc + scan[it.i4];
      final modeCostsOff = _getCostModeI4Offset(it, rd.modesI4);
      var bestBlock = bestBlocks;
      var bestBlockOff = yOffEnc + scan[it.i4];
      var tmpDst = it.yuvP;
      var tmpDstOff = i4Tmp;
      rdI4.init();
      it.makeIntra4Preds();
      for (var mode = 0; mode < numBModes; mode++) {
        final rdTmp = _rdTmpI4;
        final tmpLevels = _tmpLevels;
        rdTmp.nz =
            _reconstructIntra4(
              it,
              tmpLevels,
              0,
              src,
              tmpDst,
              tmpDstOff,
              mode,
            ) <<
            it.i4;
        rdTmp.d = sse4x4(it.yuvIn, src, tmpDst, tmpDstOff);
        rdTmp.sd = tlambda != 0
            ? _mult8b(
                tlambda,
                disto4x4(it.yuvIn, src, tmpDst, tmpDstOff, _kWeightY),
              )
            : 0;
        rdTmp.h = fixedCostsI4[modeCostsOff + mode];
        if (mode > 0 && _isFlat(tmpLevels, 0, kNumBlocks, _flatnessLimitI4)) {
          rdTmp.r = _flatnessPenalty * kNumBlocks;
        } else {
          rdTmp.r = 0;
        }
        rdTmp.setRdScore(lambda);
        if (bestMode >= 0 && rdTmp.score >= rdI4.score) continue;
        rdTmp.r += _getCostLuma4(it, tmpLevels);
        rdTmp.setRdScore(lambda);
        if (bestMode < 0 || rdTmp.score < rdI4.score) {
          rdI4.copyScore(rdTmp);
          bestMode = mode;
          // Swap tmpDst and bestBlock.
          final tb = tmpDst;
          final to = tmpDstOff;
          tmpDst = bestBlock;
          tmpDstOff = bestBlockOff;
          bestBlock = tb;
          bestBlockOff = to;
          rdBest.yAcLevels.setRange(it.i4 * 16, it.i4 * 16 + 16, tmpLevels);
        }
      }
      rdI4.setRdScore(dqm.lambdaMode);
      rdBest.addScore(rdI4);
      if (rdBest.score >= rd.score) return false;
      totalHeaderBits += rdI4.h;
      if (totalHeaderBits > _maxI4HeaderBits) return false;
      // Copy selected samples if not in the right place already.
      if (!identical(bestBlock, bestBlocks) ||
          bestBlockOff != yOffEnc + scan[it.i4]) {
        final dst = yOffEnc + scan[it.i4];
        for (var y = 0; y < 4; y++) {
          bestBlocks.setRange(
            dst + y * bps,
            dst + y * bps + 4,
            bestBlock,
            bestBlockOff + y * bps,
          );
        }
      }
      rd.modesI4[it.i4] = bestMode;
      it.topNz[it.i4 & 3] = it.leftNz[it.i4 >> 2] = rdI4.nz != 0 ? 1 : 0;
    } while (it.rotateI4(bestBlocks));
    rd.copyScore(rdBest);
    it.setIntra4Mode(rd.modesI4);
    it.swapOut();
    rd.yAcLevels.setAll(0, rdBest.yAcLevels);
    return true;
  }

  final _rdUv = _ModeScore();
  final _rdBestUv = _ModeScore();

  void _pickBestUv(_Iterator it, _ModeScore rd) {
    const kNumBlocks = 8;
    final dqm = _dqm[it.mb.segment];
    final lambda = dqm.lambdaUv;
    final rdBest = _rdBestUv;
    var tmpDst = it.yuvOut2;
    final dst0 = it.yuvOut;
    var dst = dst0;
    rd.modeUv = -1;
    rdBest.init();
    for (var mode = 0; mode < numPredModes; mode++) {
      final rdUv = _rdUv;
      // Reconstruct into tmpDst.
      final saved = it.yuvOut;
      it.yuvOut = tmpDst;
      rdUv.nz = _reconstructUv(it, rdUv, uOffEnc, mode);
      it.yuvOut = saved;
      rdUv.d = sse16x8(it.yuvIn, uOffEnc, tmpDst, uOffEnc);
      rdUv.sd = 0;
      rdUv.h = fixedCostsUv[mode];
      rdUv.r = _getCostUv(it, rdUv);
      if (mode > 0 && _isFlat(rdUv.uvLevels, 0, kNumBlocks, _flatnessLimitUv)) {
        rdUv.r += _flatnessPenalty * kNumBlocks;
      }
      rdUv.setRdScore(lambda);
      if (mode == 0 || rdUv.score < rdBest.score) {
        rdBest.copyScore(rdUv);
        rd.modeUv = mode;
        rd.uvLevels.setAll(0, rdUv.uvLevels);
        if (_topDerr != null) rd.derr.setAll(0, rdUv.derr);
        final t = dst;
        dst = tmpDst;
        tmpDst = t;
      }
    }
    it.setIntraUvMode(rd.modeUv);
    rd.addScore(rdBest);
    if (!identical(dst, dst0)) {
      for (var y = 0; y < 8; y++) {
        dst0.setRange(
          uOffEnc + y * bps,
          uOffEnc + y * bps + 16,
          dst,
          uOffEnc + y * bps,
        );
      }
    }
    if (_topDerr != null) _storeDiffusionErrors(it, rd);
  }

  void _simpleQuantize(_Iterator it, _ModeScore rd) {
    final isI16 = it.mb.type == 1;
    var nz = 0;
    if (isI16) {
      nz = _reconstructIntra16(it, rd, yOffEnc, _preds[it.predsIndex(0, 0)]);
    } else {
      it.startI4();
      do {
        final mode = _preds[it.predsIndex(it.i4 & 3, it.i4 >> 2)];
        final src = yOffEnc + scan[it.i4];
        final dst = yOffEnc + scan[it.i4];
        it.makeIntra4Preds();
        nz |=
            _reconstructIntra4(
              it,
              rd.yAcLevels,
              it.i4 * 16,
              src,
              it.yuvOut,
              dst,
              mode,
            ) <<
            it.i4;
      } while (it.rotateI4(it.yuvOut));
    }
    nz |= _reconstructUv(it, rd, uOffEnc, it.mb.uvMode);
    rd.nz = nz;
  }

  void _refineUsingDistortion(
    _Iterator it,
    bool tryBothModes,
    bool refineUvMode,
    _ModeScore rd,
  ) {
    var bestScore = _maxCost;
    var nz = 0;
    var isI16 = tryBothModes || it.mb.type == 1;
    final dqm = _dqm[it.mb.segment];
    const lambdaDI16 = 106;
    const lambdaDI4 = 11;
    const lambdaDUv = 120;
    var scoreI4 = dqm.i4Penalty;
    var i4BitSum = 0;
    final bitLimit = tryBothModes ? _mbHeaderLimit : _maxCost;
    if (isI16) {
      var bestMode = -1;
      for (var mode = 0; mode < numPredModes; mode++) {
        final ref = i16ModeOffsets[mode];
        final score =
            sse16x16(it.yuvIn, yOffEnc, it.yuvP, ref) * _rdDistoMult +
            fixedCostsI16[mode] * lambdaDI16;
        if (mode > 0 && fixedCostsI16[mode] > bitLimit) continue;
        if (score < bestScore) {
          bestMode = mode;
          bestScore = score;
        }
      }
      if (it.x == 0 || it.y == 0) {
        if (_isFlatSource16(it.yuvIn, yOffEnc)) {
          bestMode = it.x == 0 ? 0 : 2;
          tryBothModes = false;
        }
      }
      it.setIntra16Mode(bestMode);
    }
    if (tryBothModes || !isI16) {
      isI16 = false;
      it.startI4();
      do {
        var bestI4Mode = -1;
        var bestI4Score = _maxCost;
        final src = yOffEnc + scan[it.i4];
        final modeCostsOff = _getCostModeI4Offset(it, rd.modesI4);
        it.makeIntra4Preds();
        for (var mode = 0; mode < numBModes; mode++) {
          final ref = i4ModeOffsets[mode];
          final score =
              sse4x4(it.yuvIn, src, it.yuvP, ref) * _rdDistoMult +
              fixedCostsI4[modeCostsOff + mode] * lambdaDI4;
          if (score < bestI4Score) {
            bestI4Mode = mode;
            bestI4Score = score;
          }
        }
        i4BitSum += fixedCostsI4[modeCostsOff + bestI4Mode];
        rd.modesI4[it.i4] = bestI4Mode;
        scoreI4 += bestI4Score;
        if (scoreI4 >= bestScore || i4BitSum > bitLimit) {
          isI16 = true;
          break;
        } else {
          final tmpDst = yOffEnc + scan[it.i4];
          nz |=
              _reconstructIntra4(
                it,
                rd.yAcLevels,
                it.i4 * 16,
                src,
                it.yuvOut2,
                tmpDst,
                bestI4Mode,
              ) <<
              it.i4;
        }
      } while (it.rotateI4(it.yuvOut2));
    }
    if (!isI16) {
      it.setIntra4Mode(rd.modesI4);
      it.swapOut();
      bestScore = scoreI4;
    } else {
      nz = _reconstructIntra16(it, rd, yOffEnc, _preds[it.predsIndex(0, 0)]);
    }
    if (refineUvMode) {
      var bestMode = -1;
      var bestUvScore = _maxCost;
      for (var mode = 0; mode < numPredModes; mode++) {
        final ref = uvModeOffsets[mode];
        final score =
            sse16x8(it.yuvIn, uOffEnc, it.yuvP, ref) * _rdDistoMult +
            fixedCostsUv[mode] * lambdaDUv;
        if (score < bestUvScore) {
          bestMode = mode;
          bestUvScore = score;
        }
      }
      it.setIntraUvMode(bestMode);
    }
    nz |= _reconstructUv(it, rd, uOffEnc, it.mb.uvMode);
    rd.nz = nz;
    rd.score = bestScore;
  }

  bool _decimate(_Iterator it, _ModeScore rd, _RdOpt rdOpt) {
    rd.init();
    it.makeLuma16Preds();
    it.makeChroma8Preds();
    if (rdOpt != _RdOpt.none) {
      it.doTrellis = rdOpt == _RdOpt.trellisAll;
      _pickBestIntra16(it, rd);
      if (_method >= 2) {
        _pickBestIntra4(it, rd);
      }
      _pickBestUv(it, rd);
      if (rdOpt == _RdOpt.trellis) {
        it.doTrellis = true;
        _simpleQuantize(it, rd);
      }
    } else {
      _refineUsingDistortion(it, _method >= 2, _method >= 1, rd);
    }
    final isSkipped = rd.nz == 0;
    it.setSkip(isSkipped);
    return isSkipped;
  }

  //----------------------------------------------------------------------------
  // Costs

  final _res = Vp8Residual();

  int _getCostLuma4(_Iterator it, Int16List levels) {
    final x = it.i4 & 3;
    final y = it.i4 >> 2;
    final res = _res;
    res.first = 0;
    res.coeffType = 3;
    final ctx = it.topNz[x] + it.leftNz[y];
    res.setCoeffs(levels, 0);
    return getResidualCost(proba, ctx, res);
  }

  int _getCostLuma16(_Iterator it, _ModeScore rd) {
    final res = _res;
    var r = 0;
    it.nzToBytes();
    res.first = 0;
    res.coeffType = 1;
    res.setCoeffs(rd.yDcLevels, 0);
    r += getResidualCost(proba, it.topNz[8] + it.leftNz[8], res);
    res.first = 1;
    res.coeffType = 0;
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final ctx = it.topNz[x] + it.leftNz[y];
        res.setCoeffs(rd.yAcLevels, (x + y * 4) * 16);
        r += getResidualCost(proba, ctx, res);
        it.topNz[x] = it.leftNz[y] = res.last >= 0 ? 1 : 0;
      }
    }
    return r;
  }

  int _getCostUv(_Iterator it, _ModeScore rd) {
    final res = _res;
    var r = 0;
    it.nzToBytes();
    res.first = 0;
    res.coeffType = 2;
    for (var ch = 0; ch <= 2; ch += 2) {
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          final ctx = it.topNz[4 + ch + x] + it.leftNz[4 + ch + y];
          res.setCoeffs(rd.uvLevels, (ch * 2 + x + y * 2) * 16);
          r += getResidualCost(proba, ctx, res);
          it.topNz[4 + ch + x] = it.leftNz[4 + ch + y] = res.last >= 0 ? 1 : 0;
        }
      }
    }
    return r;
  }

  //----------------------------------------------------------------------------
  // Token coding (frame_enc.c)

  int _putCoeffs(Vp8BoolWriter bw, int ctx, Vp8Residual res) {
    var n = res.first;
    final type = res.coeffType;
    final p = proba.coeffs;
    var po = Vp8EncProba.probaOffset(type, bands[n], ctx);
    if (bw.putBit(res.last >= 0 ? 1 : 0, p[po]) == 0) return 0;
    while (n < 16) {
      final c = res.coeffs[res.coeffsOff + n++];
      final sign = c < 0;
      var v = sign ? -c : c;
      if (bw.putBit(v != 0 ? 1 : 0, p[po + 1]) == 0) {
        po = Vp8EncProba.probaOffset(type, bands[n], 0);
        continue;
      }
      if (bw.putBit(v > 1 ? 1 : 0, p[po + 2]) == 0) {
        po = Vp8EncProba.probaOffset(type, bands[n], 1);
      } else {
        if (bw.putBit(v > 4 ? 1 : 0, p[po + 3]) == 0) {
          if (bw.putBit(v != 2 ? 1 : 0, p[po + 4]) != 0) {
            bw.putBit(v == 4 ? 1 : 0, p[po + 5]);
          }
        } else if (bw.putBit(v > 10 ? 1 : 0, p[po + 6]) == 0) {
          if (bw.putBit(v > 6 ? 1 : 0, p[po + 7]) == 0) {
            bw.putBit(v == 6 ? 1 : 0, 159);
          } else {
            bw.putBit(v >= 9 ? 1 : 0, 165);
            bw.putBit((v & 1) == 0 ? 1 : 0, 145);
          }
        } else {
          int mask;
          List<int> tab;
          if (v < 3 + (8 << 1)) {
            bw.putBit(0, p[po + 8]);
            bw.putBit(0, p[po + 9]);
            v -= 3 + (8 << 0);
            mask = 1 << 2;
            tab = cat3;
          } else if (v < 3 + (8 << 2)) {
            bw.putBit(0, p[po + 8]);
            bw.putBit(1, p[po + 9]);
            v -= 3 + (8 << 1);
            mask = 1 << 3;
            tab = cat4;
          } else if (v < 3 + (8 << 3)) {
            bw.putBit(1, p[po + 8]);
            bw.putBit(0, p[po + 10]);
            v -= 3 + (8 << 2);
            mask = 1 << 4;
            tab = cat5;
          } else {
            bw.putBit(1, p[po + 8]);
            bw.putBit(1, p[po + 10]);
            v -= 3 + (8 << 3);
            mask = 1 << 10;
            tab = cat6;
          }
          var ti = 0;
          while (mask != 0) {
            bw.putBit((v & mask) != 0 ? 1 : 0, tab[ti++]);
            mask >>= 1;
          }
        }
        po = Vp8EncProba.probaOffset(type, bands[n], 2);
      }
      bw.putBitUniform(sign ? 1 : 0);
      if (n == 16 || bw.putBit(n <= res.last ? 1 : 0, p[po]) == 0) {
        return 1;
      }
    }
    return 1;
  }

  void _codeResiduals(Vp8BoolWriter bw, _Iterator it, _ModeScore rd) {
    final res = _res;
    final i16 = it.mb.type == 1;
    it.nzToBytes();
    if (i16) {
      res.first = 0;
      res.coeffType = 1;
      res.setCoeffs(rd.yDcLevels, 0);
      it.topNz[8] = it.leftNz[8] = _putCoeffs(
        bw,
        it.topNz[8] + it.leftNz[8],
        res,
      );
      res.first = 1;
      res.coeffType = 0;
    } else {
      res.first = 0;
      res.coeffType = 3;
    }
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final ctx = it.topNz[x] + it.leftNz[y];
        res.setCoeffs(rd.yAcLevels, (x + y * 4) * 16);
        it.topNz[x] = it.leftNz[y] = _putCoeffs(bw, ctx, res);
      }
    }
    res.first = 0;
    res.coeffType = 2;
    for (var ch = 0; ch <= 2; ch += 2) {
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          final ctx = it.topNz[4 + ch + x] + it.leftNz[4 + ch + y];
          res.setCoeffs(rd.uvLevels, (ch * 2 + x + y * 2) * 16);
          it.topNz[4 + ch + x] = it.leftNz[4 + ch + y] = _putCoeffs(
            bw,
            ctx,
            res,
          );
        }
      }
    }
    it.bytesToNz();
  }

  void _recordResiduals(_Iterator it, _ModeScore rd) {
    final res = _res;
    it.nzToBytes();
    if (it.mb.type == 1) {
      res.first = 0;
      res.coeffType = 1;
      res.setCoeffs(rd.yDcLevels, 0);
      it.topNz[8] = it.leftNz[8] = recordCoeffs(
        proba,
        it.topNz[8] + it.leftNz[8],
        res,
      );
      res.first = 1;
      res.coeffType = 0;
    } else {
      res.first = 0;
      res.coeffType = 3;
    }
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final ctx = it.topNz[x] + it.leftNz[y];
        res.setCoeffs(rd.yAcLevels, (x + y * 4) * 16);
        it.topNz[x] = it.leftNz[y] = recordCoeffs(proba, ctx, res);
      }
    }
    res.first = 0;
    res.coeffType = 2;
    for (var ch = 0; ch <= 2; ch += 2) {
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          final ctx = it.topNz[4 + ch + x] + it.leftNz[4 + ch + y];
          res.setCoeffs(rd.uvLevels, (ch * 2 + x + y * 2) * 16);
          it.topNz[4 + ch + x] = it.leftNz[4 + ch + y] = recordCoeffs(
            proba,
            ctx,
            res,
          );
        }
      }
    }
    it.bytesToNz();
  }

  //----------------------------------------------------------------------------
  // Probabilities

  static int _calcSkipProba(int nb, int total) =>
      total != 0 ? (total - nb) * 255 ~/ total : 255;

  int _finalizeSkipProba() {
    const skipProbaThreshold = 250;
    final nbMbs = mbW * mbH;
    final nbEvents = proba.nbSkip;
    proba.skipProba = _calcSkipProba(nbEvents, nbMbs);
    proba.useSkipProba = proba.skipProba < skipProbaThreshold;
    var size = 256;
    if (proba.useSkipProba) {
      size +=
          nbEvents * bitCost(1, proba.skipProba) +
          (nbMbs - nbEvents) * bitCost(0, proba.skipProba);
      size += 8 * 256;
    }
    return size;
  }

  static int _calcTokenProba(int nb, int total) =>
      nb != 0 ? (255 - nb * 255 ~/ total) : 255;

  static int _branchCost(int nb, int total, int p) =>
      nb * bitCost(1, p) + (total - nb) * bitCost(0, p);

  int _finalizeTokenProbas() {
    var hasChanged = false;
    var size = 0;
    final n = proba.coeffs.length;
    for (var i = 0; i < n; i++) {
      final stats = proba.stats[i];
      final nb = stats & 0xffff;
      final total = (stats >> 16) & 0xffff;
      final updateProba = coeffsUpdateProba[i];
      final oldP = coeffsProba0[i];
      final newP = _calcTokenProba(nb, total);
      final oldCost = _branchCost(nb, total, oldP) + bitCost(0, updateProba);
      final newCost =
          _branchCost(nb, total, newP) + bitCost(1, updateProba) + 8 * 256;
      final useNewP = oldCost > newCost;
      size += bitCost(useNewP ? 1 : 0, updateProba);
      if (useNewP) {
        proba.coeffs[i] = newP;
        hasChanged |= newP != oldP;
        size += 8 * 256;
      } else {
        proba.coeffs[i] = oldP;
      }
    }
    proba.dirty = hasChanged;
    return size;
  }

  static int _getProba(int a, int b) {
    final total = a + b;
    return total == 0 ? 255 : (255 * a + total ~/ 2) ~/ total;
  }

  void _setSegmentProbas() {
    final p = [0, 0, 0, 0];
    for (final mb in _mbInfo) {
      p[mb.segment]++;
    }
    if (_numSegments > 1) {
      final probas = proba.segments;
      probas[0] = _getProba(p[0] + p[1], p[2] + p[3]);
      probas[1] = _getProba(p[0], p[1]);
      probas[2] = _getProba(p[2], p[3]);
      _updateMap = probas[0] != 255 || probas[1] != 255 || probas[2] != 255;
      if (!_updateMap) {
        for (final mb in _mbInfo) {
          mb.segment = 0;
        }
      }
      _segmentHdrSize =
          p[0] * (bitCost(0, probas[0]) + bitCost(0, probas[1])) +
          p[1] * (bitCost(0, probas[0]) + bitCost(1, probas[1])) +
          p[2] * (bitCost(1, probas[0]) + bitCost(0, probas[2])) +
          p[3] * (bitCost(1, probas[0]) + bitCost(1, probas[2]));
    } else {
      _updateMap = false;
      _segmentHdrSize = 0;
    }
  }

  //----------------------------------------------------------------------------
  // Main loops

  void _setLoopParams(double q) {
    q = q.clamp(0.0, 100.0);
    _setSegmentParams(q);
    _setSegmentProbas();
    proba.calculateLevelCosts();
    proba.nbSkip = 0;
  }

  final _info = _ModeScore();

  /// Statistics-only pass; returns the partition 0 size estimate.
  int _oneStatPass(_RdOpt rdOpt, int nbMbs, double q) {
    final it = _it;
    var p0 = 0;
    it.reset();
    _setLoopParams(q);
    do {
      final info = _info;
      it.import(null);
      if (_decimate(it, info, rdOpt)) {
        proba.nbSkip++;
      }
      _recordResiduals(it, info);
      p0 += info.h;
      it.saveBoundary();
    } while (it.next() && --nbMbs > 0);
    p0 += _segmentHdrSize;
    return p0;
  }

  void _statLoop() {
    final method = _method;
    final fastProbe = method == 0 || method == 3;
    // Methods >= 3 refine the probabilities with an extra statistics pass
    // (libwebp's token loop refreshes them continuously).
    var numPassLeft = config.pass.clamp(1, 10) + (method >= 3 ? 1 : 0);
    final rdOpt = method >= 3 ? _RdOpt.basic : _RdOpt.none;
    var nbMbs = mbW * mbH;
    proba.stats.fillRange(0, proba.stats.length, 0);
    if (fastProbe) {
      if (method == 3) {
        nbMbs = nbMbs > 200 ? nbMbs >> 1 : 100;
      } else {
        nbMbs = nbMbs > 200 ? nbMbs >> 2 : 50;
      }
    }
    const partition0SizeLimit = ((1 << 19) - 2048) << 11;
    while (numPassLeft-- > 0) {
      final isLastPass = numPassLeft == 0 || _maxI4HeaderBits == 0;
      final sizeP0 = _oneStatPass(rdOpt, nbMbs, config.quality);
      if (_maxI4HeaderBits > 0 && sizeP0 > partition0SizeLimit) {
        numPassLeft++;
        _maxI4HeaderBits >>= 1;
        continue;
      }
      if (isLastPass) break;
    }
    _finalizeSkipProba();
    _finalizeTokenProbas();
    proba.calculateLevelCosts();
  }

  void _adjustFilterStrength() {
    if (config.filterStrength > 0) {
      var maxLevel = 0;
      for (var s = 0; s < numMbSegments; s++) {
        final dqm = _dqm[s];
        final delta = (dqm.maxEdge * dqm.y2.q[1]) >> 3;
        final level = _filterStrengthFromDelta(_filterSharpness, delta);
        if (level > dqm.fstrength) dqm.fstrength = level;
        if (maxLevel < dqm.fstrength) maxLevel = dqm.fstrength;
      }
      _filterLevel = maxLevel;
    }
  }

  static const _kAverageBytesPerMb = [50, 24, 16, 9, 7, 5, 3, 2];

  void _encLoop() {
    _statLoop();
    final averageBytesPerMb = _kAverageBytesPerMb[_baseQuant >> 4];
    _part = Vp8BoolWriter(mbW * mbH * averageBytesPerMb);
    final it = _it;
    it.reset();
    do {
      final info = _info;
      final dontUseSkip = !proba.useSkipProba;
      it.import(null);
      if (!_decimate(it, info, _rdOptLevel) || dontUseSkip) {
        _codeResiduals(_part, it, info);
      } else {
        it.resetAfterSkip();
      }
      it.saveBoundary();
    } while (it.next());
    _adjustFilterStrength();
  }

  //----------------------------------------------------------------------------
  // Syntax (syntax_enc.c, tree_enc.c)

  void _putSegmentHeader(Vp8BoolWriter bw) {
    if (bw.putBitUniform(_numSegments > 1 ? 1 : 0) != 0) {
      const updateData = 1;
      bw.putBitUniform(_updateMap ? 1 : 0);
      if (bw.putBitUniform(updateData) != 0) {
        bw.putBitUniform(1); // absolute values
        for (var s = 0; s < numMbSegments; s++) {
          bw.putSignedBits(_dqm[s].quant, 7);
        }
        for (var s = 0; s < numMbSegments; s++) {
          bw.putSignedBits(_dqm[s].fstrength, 6);
        }
      }
      if (_updateMap) {
        for (var s = 0; s < 3; s++) {
          if (bw.putBitUniform(proba.segments[s] != 255 ? 1 : 0) != 0) {
            bw.putBits(proba.segments[s], 8);
          }
        }
      }
    }
  }

  void _putFilterHeader(Vp8BoolWriter bw) {
    const i4x4LfDelta = 0;
    const useLfDelta = i4x4LfDelta != 0;
    bw.putBitUniform(_filterSimple ? 1 : 0);
    bw.putBits(_filterLevel, 6);
    bw.putBits(_filterSharpness, 3);
    if (bw.putBitUniform(useLfDelta ? 1 : 0) != 0) {
      // Not used.
    }
  }

  void _putQuant(Vp8BoolWriter bw) {
    bw.putBits(_baseQuant, 7);
    bw.putSignedBits(_dqY1Dc, 4);
    bw.putSignedBits(_dqY2Dc, 4);
    bw.putSignedBits(_dqY2Ac, 4);
    bw.putSignedBits(_dqUvDc, 4);
    bw.putSignedBits(_dqUvAc, 4);
  }

  void _writeProbas(Vp8BoolWriter bw) {
    final n = proba.coeffs.length;
    for (var i = 0; i < n; i++) {
      final p0 = proba.coeffs[i];
      final update = p0 != coeffsProba0[i];
      if (bw.putBit(update ? 1 : 0, coeffsUpdateProba[i]) != 0) {
        bw.putBits(p0, 8);
      }
    }
    if (bw.putBitUniform(proba.useSkipProba ? 1 : 0) != 0) {
      bw.putBits(proba.skipProba, 8);
    }
  }

  static int _putI4Mode(Vp8BoolWriter bw, int mode, int po) {
    final prob = bModesProba;
    if (bw.putBit(mode != bDcPred ? 1 : 0, prob[po]) != 0) {
      if (bw.putBit(mode != bTmPred ? 1 : 0, prob[po + 1]) != 0) {
        if (bw.putBit(mode != bVePred ? 1 : 0, prob[po + 2]) != 0) {
          if (bw.putBit(mode >= bLdPred ? 1 : 0, prob[po + 3]) == 0) {
            if (bw.putBit(mode != bHePred ? 1 : 0, prob[po + 4]) != 0) {
              bw.putBit(mode != bRdPred ? 1 : 0, prob[po + 5]);
            }
          } else {
            if (bw.putBit(mode != bLdPred ? 1 : 0, prob[po + 6]) != 0) {
              if (bw.putBit(mode != bVlPred ? 1 : 0, prob[po + 7]) != 0) {
                bw.putBit(mode != bHdPred ? 1 : 0, prob[po + 8]);
              }
            }
          }
        }
      }
    }
    return mode;
  }

  static void _putI16Mode(Vp8BoolWriter bw, int mode) {
    if (bw.putBit((mode == tmPred || mode == hPred) ? 1 : 0, 156) != 0) {
      bw.putBit(mode == tmPred ? 1 : 0, 128);
    } else {
      bw.putBit(mode == vPred ? 1 : 0, 163);
    }
  }

  static void _putUvMode(Vp8BoolWriter bw, int uvMode) {
    if (bw.putBit(uvMode != dcPred ? 1 : 0, 142) != 0) {
      if (bw.putBit(uvMode != vPred ? 1 : 0, 114) != 0) {
        bw.putBit(uvMode != hPred ? 1 : 0, 183);
      }
    }
  }

  void _putSegment(Vp8BoolWriter bw, int s) {
    final p = proba.segments;
    if (bw.putBit(s >= 2 ? 1 : 0, p[0]) != 0) {
      bw.putBit(s & 1, p[2]);
    } else {
      bw.putBit(s & 1, p[1]);
    }
  }

  void _codeIntraModes(Vp8BoolWriter bw) {
    final it = _it;
    it.reset();
    do {
      final mb = it.mb;
      if (_updateMap) _putSegment(bw, mb.segment);
      if (proba.useSkipProba) bw.putBit(mb.skip ? 1 : 0, proba.skipProba);
      if (bw.putBit(mb.type != 0 ? 1 : 0, 145) != 0) {
        _putI16Mode(bw, _preds[it.predsIndex(0, 0)]);
      } else {
        for (var y = 0; y < 4; y++) {
          var left = _preds[it.predsIndex(-1, y)];
          for (var x = 0; x < 4; x++) {
            final top = _preds[it.predsIndex(x, y - 1)];
            final po = (top * numBModes + left) * (numBModes - 1);
            left = _putI4Mode(bw, _preds[it.predsIndex(x, y)], po);
          }
        }
      }
      _putUvMode(bw, mb.uvMode);
    } while (it.next());
  }

  Uint8List _generatePartition0() {
    final bw = Vp8BoolWriter(mbW * mbH * 7 ~/ 8 + 256);
    bw.putBitUniform(0); // colorspace
    bw.putBitUniform(0); // clamp type
    _putSegmentHeader(bw);
    _putFilterHeader(bw);
    bw.putBits(0, 2); // 1 partition
    _putQuant(bw);
    bw.putBitUniform(0); // no proba update
    _writeProbas(bw);
    _codeIntraModes(bw);
    return bw.finish();
  }

  /// Encodes the picture and returns the `VP8 ` chunk payload.
  Uint8List encode() {
    _analyze();
    _encLoop();
    final part0 = _generatePartition0();
    final part1 = _part.finish();
    final size0 = part0.length;
    if (size0 >= (1 << 19)) {
      throw StateError('VP8 partition 0 overflow');
    }
    final out = Uint8List(10 + size0 + part1.length);
    final bits = 0 | (_profile << 1) | (1 << 4) | (size0 << 5);
    out[0] = bits & 0xff;
    out[1] = (bits >> 8) & 0xff;
    out[2] = (bits >> 16) & 0xff;
    out[3] = 0x9d;
    out[4] = 0x01;
    out[5] = 0x2a;
    out[6] = width & 0xff;
    out[7] = width >> 8;
    out[8] = height & 0xff;
    out[9] = height >> 8;
    out.setRange(10, 10 + size0, part0);
    out.setRange(10 + size0, out.length, part1);
    return out;
  }
}

/// Macroblock iterator (iterator_enc.c).
class _Iterator {
  final Vp8Encoder enc;
  int x = 0;
  int y = 0;
  final Uint8List yuvIn = Uint8List(yuvSizeEnc);
  Uint8List yuvOut = Uint8List(yuvSizeEnc);
  Uint8List yuvOut2 = Uint8List(yuvSizeEnc);
  final Uint8List yuvP = Uint8List(predSizeEnc);
  late _MbInfo mb;
  final i4Boundary = Uint8List(37);
  int i4Top = 0;
  int i4 = 0;
  final topNz = List<int>.filled(9, 0);
  final leftNz = List<int>.filled(9, 0);
  bool doTrellis = false;
  int countDown = 0;
  final Int8List leftDerr = Int8List(4);

  /// Left samples: yLeft at offset 1 (index 0 = top-left), 16 entries;
  /// uLeft at 17 + 1, vLeft at 17 + 16 + 1.
  final Uint8List leftMem = Uint8List(1 + 16 + 1 + 16 + 1 + 8 + 8);
  static const yLeftOff = 1;
  static const uLeftOff = 1 + 16 + 1;
  static const vLeftOff = uLeftOff + 16;

  // Top samples (borrowed from the encoder, per x).
  int yTopOff = 0;
  int uvTopOff = 0;
  Uint8List? tmp32; // when non-null, top samples come from this scratch

  _Iterator(this.enc) {
    reset();
  }

  static const _kTopLeftI4 = [
    17,
    21,
    25,
    29,
    13,
    17,
    21,
    25,
    9,
    13,
    17,
    21,
    5,
    9,
    13,
    17,
  ];

  void _initLeft() {
    final v = y > 0 ? 129 : 127;
    leftMem[yLeftOff - 1] = v;
    leftMem[uLeftOff - 1] = v;
    leftMem[vLeftOff - 1] = v;
    leftMem.fillRange(yLeftOff, yLeftOff + 16, 129);
    leftMem.fillRange(uLeftOff, uLeftOff + 8, 129);
    leftMem.fillRange(vLeftOff, vLeftOff + 8, 129);
    leftNz[8] = 0;
    if (enc._topDerr != null) leftDerr.fillRange(0, 4, 0);
  }

  void _initTop() {
    enc._yTop.fillRange(0, enc._yTop.length, 127);
    enc._uvTop.fillRange(0, enc._uvTop.length, 127);
    enc._nz.fillRange(0, enc._nz.length, 0);
    enc._topDerr?.fillRange(0, enc._topDerr!.length, 0);
  }

  void setRow(int yy) {
    x = 0;
    y = yy;
    if (yy < enc.mbH) mb = enc._mbInfo[yy * enc.mbW];
    yTopOff = 0;
    uvTopOff = 0;
    tmp32 = null;
    _initLeft();
  }

  void reset() {
    setRow(0);
    countDown = enc.mbW * enc.mbH;
    _initTop();
    doTrellis = false;
  }

  int predsIndex(int dx, int dy) => enc._predIndex(x * 4 + dx, y * 4 + dy);

  Uint8List get yTop => tmp32 ?? enc._yTop;
  int get yTopIndex => tmp32 != null ? 0 : yTopOff;
  Uint8List get uvTop => tmp32 ?? enc._uvTop;
  int get uvTopIndex => tmp32 != null ? 16 : uvTopOff;

  static void _importBlock(
    Uint8List src,
    int srcOff,
    int srcStride,
    Uint8List dst,
    int dstOff,
    int w,
    int h,
    int size,
  ) {
    for (var i = 0; i < h; i++) {
      dst.setRange(dstOff, dstOff + w, src, srcOff);
      if (w < size) {
        dst.fillRange(dstOff + w, dstOff + size, dst[dstOff + w - 1]);
      }
      dstOff += bps;
      srcOff += srcStride;
    }
    for (var i = h; i < size; i++) {
      dst.setRange(dstOff, dstOff + size, dst, dstOff - bps);
      dstOff += bps;
    }
  }

  static void _importLine(
    Uint8List src,
    int srcOff,
    int srcStride,
    Uint8List dst,
    int dstOff,
    int len,
    int totalLen,
  ) {
    var i = 0;
    for (; i < len; i++, srcOff += srcStride) {
      dst[dstOff + i] = src[srcOff];
    }
    for (; i < totalLen; i++) {
      dst[dstOff + i] = dst[dstOff + len - 1];
    }
  }

  /// Imports source samples; if [scratch] is given, also imports the
  /// (uncompressed) boundary samples into it.
  void import(Uint8List? scratch) {
    final pic = enc.pic;
    final w0 = pic.width;
    final ysrc = (y * w0 + x) * 16;
    final uvw = pic.uvWidth;
    final usrc = (y * uvw + x) * 8;
    final w = math.min(w0 - x * 16, 16);
    final h = math.min(pic.height - y * 16, 16);
    final uvW = (w + 1) >> 1;
    final uvH = (h + 1) >> 1;
    _importBlock(pic.y, ysrc, w0, yuvIn, yOffEnc, w, h, 16);
    _importBlock(pic.u, usrc, uvw, yuvIn, uOffEnc, uvW, uvH, 8);
    _importBlock(pic.v, usrc, uvw, yuvIn, vOffEnc, uvW, uvH, 8);
    if (scratch == null) return;
    if (x == 0) {
      _initLeft();
    } else {
      if (y == 0) {
        leftMem[yLeftOff - 1] = 127;
        leftMem[uLeftOff - 1] = 127;
        leftMem[vLeftOff - 1] = 127;
      } else {
        leftMem[yLeftOff - 1] = pic.y[ysrc - 1 - w0];
        leftMem[uLeftOff - 1] = pic.u[usrc - 1 - uvw];
        leftMem[vLeftOff - 1] = pic.v[usrc - 1 - uvw];
      }
      _importLine(pic.y, ysrc - 1, w0, leftMem, yLeftOff, h, 16);
      _importLine(pic.u, usrc - 1, uvw, leftMem, uLeftOff, uvH, 8);
      _importLine(pic.v, usrc - 1, uvw, leftMem, vLeftOff, uvH, 8);
    }
    tmp32 = scratch;
    if (y == 0) {
      scratch.fillRange(0, 32, 127);
    } else {
      _importLine(pic.y, ysrc - w0, 1, scratch, 0, w, 16);
      _importLine(pic.u, usrc - uvw, 1, scratch, 16, uvW, 8);
      _importLine(pic.v, usrc - uvw, 1, scratch, 24, uvW, 8);
    }
  }

  void nzToBytes() {
    final tnz = enc._nz[x + 1];
    final lnz = enc._nz[x];
    int bit(int v, int n) => (v >> n) & 1;
    topNz[0] = bit(tnz, 12);
    topNz[1] = bit(tnz, 13);
    topNz[2] = bit(tnz, 14);
    topNz[3] = bit(tnz, 15);
    topNz[4] = bit(tnz, 18);
    topNz[5] = bit(tnz, 19);
    topNz[6] = bit(tnz, 22);
    topNz[7] = bit(tnz, 23);
    topNz[8] = bit(tnz, 24);
    leftNz[0] = bit(lnz, 3);
    leftNz[1] = bit(lnz, 7);
    leftNz[2] = bit(lnz, 11);
    leftNz[3] = bit(lnz, 15);
    leftNz[4] = bit(lnz, 17);
    leftNz[5] = bit(lnz, 19);
    leftNz[6] = bit(lnz, 21);
    leftNz[7] = bit(lnz, 23);
  }

  void bytesToNz() {
    var nz = 0;
    nz |= (topNz[0] << 12) | (topNz[1] << 13);
    nz |= (topNz[2] << 14) | (topNz[3] << 15);
    nz |= (topNz[4] << 18) | (topNz[5] << 19);
    nz |= (topNz[6] << 22) | (topNz[7] << 23);
    nz |= topNz[8] << 24;
    nz |= (leftNz[0] << 3) | (leftNz[1] << 7);
    nz |= leftNz[2] << 11;
    nz |= (leftNz[4] << 17) | (leftNz[6] << 21);
    enc._nz[x + 1] = nz;
  }

  void saveBoundary() {
    final ysrc = yOffEnc;
    final uvsrc = uOffEnc;
    if (x < enc.mbW - 1) {
      for (var i = 0; i < 16; i++) {
        leftMem[yLeftOff + i] = yuvOut[ysrc + 15 + i * bps];
      }
      for (var i = 0; i < 8; i++) {
        leftMem[uLeftOff + i] = yuvOut[uvsrc + 7 + i * bps];
        leftMem[vLeftOff + i] = yuvOut[uvsrc + 15 + i * bps];
      }
      leftMem[yLeftOff - 1] = enc._yTop[yTopOff + 15];
      leftMem[uLeftOff - 1] = enc._uvTop[uvTopOff + 7];
      leftMem[vLeftOff - 1] = enc._uvTop[uvTopOff + 8 + 7];
    }
    if (y < enc.mbH - 1) {
      enc._yTop.setRange(yTopOff, yTopOff + 16, yuvOut, ysrc + 15 * bps);
      enc._uvTop.setRange(uvTopOff, uvTopOff + 16, yuvOut, uvsrc + 7 * bps);
    }
  }

  bool next() {
    if (++x == enc.mbW) {
      setRow(++y);
    } else {
      mb = enc._mbInfo[y * enc.mbW + x];
      yTopOff += 16;
      uvTopOff += 16;
    }
    return 0 < --countDown;
  }

  void setIntra16Mode(int mode) {
    for (var yy = 0; yy < 4; yy++) {
      final base = predsIndex(0, yy);
      enc._preds.fillRange(base, base + 4, mode);
    }
    mb.type = 1;
  }

  void setIntra4Mode(Uint8List modes) {
    for (var yy = 0; yy < 4; yy++) {
      final base = predsIndex(0, yy);
      enc._preds.setRange(base, base + 4, modes, yy * 4);
    }
    mb.type = 0;
  }

  void setIntraUvMode(int mode) => mb.uvMode = mode;
  void setSkip(bool skip) => mb.skip = skip;
  void setSegment(int segment) => mb.segment = segment;

  void swapOut() {
    final tmp = yuvOut;
    yuvOut = yuvOut2;
    yuvOut2 = tmp;
  }

  void resetAfterSkip() {
    if (mb.type == 1) {
      enc._nz[x + 1] = 0;
      leftNz[8] = 0;
    } else {
      enc._nz[x + 1] &= 1 << 24;
    }
  }

  void makeLuma16Preds() {
    intra16Preds(
      yuvP,
      x != 0 ? leftMem : null,
      yLeftOff,
      y != 0 ? yTop : null,
      yTopIndex,
    );
  }

  void makeChroma8Preds() {
    intraChromaPreds(
      yuvP,
      x != 0 ? leftMem : null,
      uLeftOff,
      y != 0 ? uvTop : null,
      uvTopIndex,
    );
  }

  void makeIntra4Preds() {
    intra4Preds(yuvP, i4Boundary, i4Top);
  }

  void startI4() {
    i4 = 0;
    i4Top = _kTopLeftI4[0];
    for (var i = 0; i < 17; i++) {
      i4Boundary[i] = leftMem[yLeftOff + 15 - i];
    }
    final top = yTop;
    final to = yTopIndex;
    for (var i = 0; i < 16; i++) {
      i4Boundary[17 + i] = top[to + i];
    }
    if (x < enc.mbW - 1) {
      for (var i = 16; i < 16 + 4; i++) {
        i4Boundary[17 + i] = top[to + i];
      }
    } else {
      for (var i = 16; i < 16 + 4; i++) {
        i4Boundary[17 + i] = i4Boundary[17 + 15];
      }
    }
    nzToBytes();
  }

  bool rotateI4(Uint8List yuvOutBuf) {
    final blk = scan[i4];
    final top = i4Top;
    for (var i = 0; i <= 3; i++) {
      i4Boundary[top - 4 + i] = yuvOutBuf[blk + i + 3 * bps];
    }
    if ((i4 & 3) != 3) {
      for (var i = 0; i <= 2; i++) {
        i4Boundary[top + i] = yuvOutBuf[blk + 3 + (2 - i) * bps];
      }
    } else {
      for (var i = 0; i <= 3; i++) {
        i4Boundary[top + i] = i4Boundary[top + i + 4];
      }
    }
    i4++;
    if (i4 == 16) return false;
    i4Top = _kTopLeftI4[i4];
    return true;
  }
}

/// Smooths transparent areas of the YUV planes to help compression
/// (libwebp's `WebPCleanupTransparentArea`).
void cleanupTransparentArea(YuvaPlanes pic) {
  final a = pic.a;
  if (a == null) return;
  const size = 8;
  const size2 = size ~/ 2;
  final width = pic.width;
  final height = pic.height;
  final uvw = pic.uvWidth;
  bool smoothenBlock(int ax, int ay, int w, int h) {
    var sum = 0;
    var count = 0;
    for (var yy = 0; yy < h; yy++) {
      for (var xx = 0; xx < w; xx++) {
        if (a[(ay + yy) * width + ax + xx] != 0) {
          count++;
          sum += pic.y[(ay + yy) * width + ax + xx];
        }
      }
    }
    if (count > 0 && count < w * h) {
      final avg = sum ~/ count;
      for (var yy = 0; yy < h; yy++) {
        for (var xx = 0; xx < w; xx++) {
          if (a[(ay + yy) * width + ax + xx] == 0) {
            pic.y[(ay + yy) * width + ax + xx] = avg;
          }
        }
      }
    }
    return count == 0;
  }

  void flatten(Uint8List p, int off, int v, int stride, int n) {
    for (var yy = 0; yy < n; yy++) {
      p.fillRange(off + yy * stride, off + yy * stride + n, v);
    }
  }

  final values = [0, 0, 0];
  var yy = 0;
  for (; yy + size <= height; yy += size) {
    var needReset = true;
    var xx = 0;
    for (; xx + size <= width; xx += size) {
      if (smoothenBlock(xx, yy, size, size)) {
        if (needReset) {
          values[0] = pic.y[yy * width + xx];
          values[1] = pic.u[(yy >> 1) * uvw + (xx >> 1)];
          values[2] = pic.v[(yy >> 1) * uvw + (xx >> 1)];
          needReset = false;
        }
        flatten(pic.y, yy * width + xx, values[0], width, size);
        flatten(pic.u, (yy >> 1) * uvw + (xx >> 1), values[1], uvw, size2);
        flatten(pic.v, (yy >> 1) * uvw + (xx >> 1), values[2], uvw, size2);
      } else {
        needReset = true;
      }
    }
    if (xx < width) smoothenBlock(xx, yy, width - xx, size);
  }
  if (yy < height) {
    final subHeight = height - yy;
    var xx = 0;
    for (; xx + size <= width; xx += size) {
      smoothenBlock(xx, yy, size, subHeight);
    }
    if (xx < width) smoothenBlock(xx, yy, width - xx, subHeight);
  }
}
