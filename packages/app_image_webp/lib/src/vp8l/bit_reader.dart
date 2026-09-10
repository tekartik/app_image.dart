import 'dart:typed_data';

/// Little-endian bit reader for the VP8L (lossless) bitstream.
///
/// Uses a 32-bit window so that it also works when compiled to JavaScript
/// (where bit operations are 32-bit). At most 24 bits can be read at once.
class Vp8lBitReader {
  final Uint8List _buf;
  int _pos = 0;

  /// Bit accumulator (at most 32 valid bits).
  int _val = 0;

  /// Number of valid bits in [_val].
  int _bits = 0;

  /// Set when a read went past the end of the buffer.
  bool eos = false;

  /// Creates a reader over [buf], starting at byte offset [start].
  Vp8lBitReader(this._buf, [int start = 0]) : _pos = start {
    _fill();
  }

  void _fill() {
    while (_bits <= 24) {
      if (_pos < _buf.length) {
        _val |= _buf[_pos++] << _bits;
        _bits += 8;
      } else {
        break;
      }
    }
  }

  /// True if the reader has consumed more bits than available.
  bool get isEndOfStream => eos;

  /// Returns the next [n] bits (0..24) without consuming them.
  int peekBits(int n) {
    if (_bits < n) _fill();
    return _val & ((1 << n) - 1);
  }

  /// Consumes [n] bits (which must have been peeked/available).
  void skipBits(int n) {
    if (_bits < n) {
      _fill();
      if (_bits < n) {
        eos = true;
        _val = 0;
        _bits = 0;
        return;
      }
    }
    _val = _val >>> n;
    _bits -= n;
  }

  /// Reads [n] bits (0..24) as an unsigned integer.
  int readBits(int n) {
    if (n == 0) return 0;
    if (_bits < n) {
      _fill();
      if (_bits < n) {
        eos = true;
        _val = 0;
        _bits = 0;
        return 0;
      }
    }
    final v = _val & ((1 << n) - 1);
    _val = _val >>> n;
    _bits -= n;
    return v;
  }

  /// Reads a single bit.
  int readBit() => readBits(1);
}
