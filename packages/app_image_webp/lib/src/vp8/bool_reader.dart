import 'dart:typed_data';

import '../vp8l/lossless_dsp.dart' show bitsLog2Floor;

/// Boolean (arithmetic) decoder of the VP8 bitstream (RFC 6386 section 7).
class Vp8BoolReader {
  final Uint8List _buf;
  int _pos;
  final int _end;

  /// Current range minus one, in [127, 254].
  int _range = 254;

  /// Current value window.
  int _value = 0;

  /// Number of valid bits left in [_value] (minus 8).
  int _bits = -8;

  /// Set when reading past the end of the partition.
  bool eof = false;

  /// Creates a reader over `buf[start, start + size)`.
  Vp8BoolReader(this._buf, int start, int size)
    : _pos = start,
      _end = start + size {
    _loadNewBytes();
  }

  void _loadNewBytes() {
    if (_pos < _end) {
      _bits += 8;
      _value = _buf[_pos++] | (_value << 8);
    } else if (!eof) {
      _value <<= 8;
      _bits += 8;
      eof = true;
    } else {
      _bits = 0;
    }
  }

  /// Decodes one boolean with probability [prob] (0..255) of being 0.
  int getBit(int prob) {
    var range = _range;
    if (_bits < 0) _loadNewBytes();
    final pos = _bits;
    final split = (range * prob) >> 8;
    final value = _value >> pos;
    int bit;
    if (value > split) {
      range -= split;
      _value -= (split + 1) << pos;
      bit = 1;
    } else {
      range = split + 1;
      bit = 0;
    }
    final shift = 7 ^ bitsLog2Floor(range);
    range <<= shift;
    _bits -= shift;
    _range = range - 1;
    return bit;
  }

  /// Reads a bit with even probability.
  int getBitUniform() => getBit(0x80);

  /// Reads [bits] bits, most significant first, with even probability.
  int getValue(int bits) {
    var v = 0;
    while (bits-- > 0) {
      v |= getBit(0x80) << bits;
    }
    return v;
  }

  /// Reads a magnitude of [bits] bits followed by a sign bit.
  int getSignedValue(int bits) {
    final value = getValue(bits);
    return getBit(0x80) != 0 ? -value : value;
  }

  /// Reads the sign of [v] (uniform probability) and applies it.
  int getSigned(int v) => getBit(0x80) != 0 ? -v : v;
}
