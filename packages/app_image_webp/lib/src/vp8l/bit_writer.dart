import 'dart:typed_data';

/// Little-endian bit writer for the VP8L bitstream (LSB first).
class Vp8lBitWriter {
  Uint8List _buf;
  int _pos = 0;

  /// Pending bits (fewer than 8 after each write).
  int _bits = 0;
  int _used = 0;

  /// Creates a writer with an initial capacity hint.
  Vp8lBitWriter([int expectedSize = 1024])
    : _buf = Uint8List(expectedSize < 64 ? 64 : expectedSize);

  /// Number of bytes written so far, rounding pending bits up.
  int get numBytes => _pos + ((_used + 7) >> 3);

  /// Number of bits written so far.
  int get numBits => _pos * 8 + _used;

  void _ensure(int extra) {
    if (_pos + extra > _buf.length) {
      var newSize = _buf.length * 2;
      if (newSize < _pos + extra) newSize = _pos + extra;
      final nb = Uint8List(newSize);
      nb.setRange(0, _pos, _buf);
      _buf = nb;
    }
  }

  /// Writes the [n] low bits of [value] (n in 0..32).
  void putBits(int value, int n) {
    if (n == 0) return;
    if (n > 16) {
      putBits(value & 0xffff, 16);
      putBits(value >>> 16, n - 16);
      return;
    }
    _bits |= (value & ((1 << n) - 1)) << _used;
    _used += n;
    if (_used >= 8) {
      _ensure(4);
      while (_used >= 8) {
        _buf[_pos++] = _bits & 0xff;
        _bits >>>= 8;
        _used -= 8;
      }
    }
  }

  /// Returns the written bytes, flushing pending bits (zero padded).
  Uint8List finish() {
    if (_used > 0) {
      _ensure(1);
      _buf[_pos++] = _bits & 0xff;
      _bits = 0;
      _used = 0;
    }
    return Uint8List.sublistView(_buf, 0, _pos);
  }

  /// Appends [data] bytes; pending bits must be byte-aligned.
  void appendBytes(Uint8List data) {
    assert(_used == 0);
    _ensure(data.length);
    _buf.setRange(_pos, _pos + data.length, data);
    _pos += data.length;
  }
}
