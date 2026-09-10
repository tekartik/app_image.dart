import 'dart:typed_data';

import '../int_utils.dart';

/// Boolean (arithmetic) encoder of the VP8 bitstream.
class Vp8BoolWriter {
  int _range = 254; // range - 1
  int _value = 0;
  int _run = 0; // number of outstanding 0xff bytes
  int _nbBits = -8; // number of pending bits
  Uint8List _buf;
  int _pos = 0;

  /// Creates a writer with an initial capacity hint.
  Vp8BoolWriter([int expectedSize = 1024])
    : _buf = Uint8List(expectedSize < 64 ? 64 : expectedSize);

  /// Number of bytes written so far.
  int get size => _pos;

  /// Approximate write position, in bits.
  int get bitPos => (_pos + _run) * 8 + 8 + _nbBits;

  static const _kNorm = [
    7, 6, 6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, //
    3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, //
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, //
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, //
  ];

  static const _kNewRange = [
    127,
    127,
    191,
    127,
    159,
    191,
    223,
    127,
    143,
    159,
    175,
    191,
    207,
    223,
    239, //
    127,
    135,
    143,
    151,
    159,
    167,
    175,
    183,
    191,
    199,
    207,
    215,
    223,
    231,
    239, //
    247,
    127,
    131,
    135,
    139,
    143,
    147,
    151,
    155,
    159,
    163,
    167,
    171,
    175,
    179, //
    183,
    187,
    191,
    195,
    199,
    203,
    207,
    211,
    215,
    219,
    223,
    227,
    231,
    235,
    239, //
    243,
    247,
    251,
    127,
    129,
    131,
    133,
    135,
    137,
    139,
    141,
    143,
    145,
    147,
    149, //
    151,
    153,
    155,
    157,
    159,
    161,
    163,
    165,
    167,
    169,
    171,
    173,
    175,
    177,
    179, //
    181,
    183,
    185,
    187,
    189,
    191,
    193,
    195,
    197,
    199,
    201,
    203,
    205,
    207,
    209, //
    211,
    213,
    215,
    217,
    219,
    221,
    223,
    225,
    227,
    229,
    231,
    233,
    235,
    237,
    239, //
    241, 243, 245, 247, 249, 251, 253, 127, //
  ];

  void _ensure(int extra) {
    if (_pos + extra > _buf.length) {
      var n = _buf.length * 2;
      if (n < _pos + extra) n = _pos + extra;
      final nb = Uint8List(n);
      nb.setRange(0, _pos, _buf);
      _buf = nb;
    }
  }

  void _flush() {
    final s = 8 + _nbBits;
    final bits = sar(_value, s);
    _value -= bits << s;
    _nbBits -= 8;
    if ((bits & 0xff) != 0xff) {
      _ensure(_run + 1);
      var pos = _pos;
      if ((bits & 0x100) != 0) {
        if (pos > 0) _buf[pos - 1]++;
      }
      if (_run > 0) {
        final value = (bits & 0x100) != 0 ? 0x00 : 0xff;
        for (; _run > 0; _run--) {
          _buf[pos++] = value;
        }
      }
      _buf[pos++] = bits & 0xff;
      _pos = pos;
    } else {
      _run++;
    }
  }

  /// Codes [bit] with probability [prob] (0..255) of being 0. Returns [bit].
  int putBit(int bit, int prob) {
    final split = (_range * prob) >> 8;
    if (bit != 0) {
      _value += split + 1;
      _range -= split + 1;
    } else {
      _range = split;
    }
    if (_range < 127) {
      final shift = _kNorm[_range];
      _range = _kNewRange[_range];
      _value <<= shift;
      _nbBits += shift;
      if (_nbBits > 0) _flush();
    }
    return bit;
  }

  /// Codes [bit] with even probability. Returns [bit].
  int putBitUniform(int bit) {
    final split = _range >> 1;
    if (bit != 0) {
      _value += split + 1;
      _range -= split + 1;
    } else {
      _range = split;
    }
    if (_range < 127) {
      _range = _kNewRange[_range];
      _value <<= 1;
      _nbBits += 1;
      if (_nbBits > 0) _flush();
    }
    return bit;
  }

  /// Codes the [nbBits] low bits of [value], most significant first.
  void putBits(int value, int nbBits) {
    for (var mask = 1 << (nbBits - 1); mask != 0; mask >>= 1) {
      putBitUniform((value & mask) != 0 ? 1 : 0);
    }
  }

  /// Codes a flag, then magnitude and sign of [value] if non-zero.
  void putSignedBits(int value, int nbBits) {
    if (putBitUniform(value != 0 ? 1 : 0) == 0) return;
    if (value < 0) {
      putBits(((-value) << 1) | 1, nbBits + 1);
    } else {
      putBits(value << 1, nbBits + 1);
    }
  }

  /// Flushes pending bits and returns the coded bytes.
  Uint8List finish() {
    putBits(0, 9 - _nbBits);
    _nbBits = 0;
    _flush();
    return Uint8List.sublistView(_buf, 0, _pos);
  }
}
