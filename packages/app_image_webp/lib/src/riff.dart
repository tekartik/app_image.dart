import 'dart:typed_data';

import 'webp_image.dart';

/// A chunk of a RIFF container: a 4 character tag and a payload view.
class RiffChunk {
  /// Four character code (e.g. `VP8 `, `VP8L`, `ALPH`, `VP8X`).
  final String tag;

  /// Payload bytes (without padding byte).
  final Uint8List data;

  /// Creates a chunk.
  RiffChunk(this.tag, this.data);

  @override
  String toString() => 'RiffChunk($tag, ${data.length} bytes)';
}

int _le32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

int _le24(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);

/// Parsed WebP container.
class WebpContainer {
  /// Chunks in file order.
  final List<RiffChunk> chunks;

  /// The `VP8X` chunk flags, or 0 if absent.
  final int vp8xFlags;

  /// Canvas width from `VP8X`, or 0 if absent.
  final int canvasWidth;

  /// Canvas height from `VP8X`, or 0 if absent.
  final int canvasHeight;

  WebpContainer._(
    this.chunks,
    this.vp8xFlags,
    this.canvasWidth,
    this.canvasHeight,
  );

  /// True if a `VP8X` chunk is present.
  bool get isExtended => canvasWidth > 0;

  /// Returns the first chunk with the given [tag], or null.
  RiffChunk? find(String tag) {
    for (final c in chunks) {
      if (c.tag == tag) return c;
    }
    return null;
  }

  /// Parses the RIFF/WEBP structure of [bytes].
  ///
  /// Throws [WebpFormatException] if the header is invalid. Truncated
  /// trailing chunks are tolerated (clamped to the available bytes).
  static WebpContainer parse(Uint8List bytes) {
    if (bytes.length < 12) {
      throw WebpFormatException('Data too short for a WebP file');
    }
    if (bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46 ||
        bytes[8] != 0x57 ||
        bytes[9] != 0x45 ||
        bytes[10] != 0x42 ||
        bytes[11] != 0x50) {
      throw WebpFormatException('Missing RIFF/WEBP signature');
    }
    var riffSize = _le32(bytes, 4);
    var end = 8 + riffSize;
    if (end > bytes.length) end = bytes.length;
    if (end.isOdd && end < bytes.length) end++;
    final chunks = <RiffChunk>[];
    var pos = 12;
    var flags = 0;
    var cw = 0;
    var ch = 0;
    while (pos + 8 <= end) {
      final tag = String.fromCharCodes(bytes, pos, pos + 4);
      var size = _le32(bytes, pos + 4);
      pos += 8;
      if (size > end - pos) size = end - pos;
      final data = Uint8List.sublistView(bytes, pos, pos + size);
      chunks.add(RiffChunk(tag, data));
      if (tag == 'VP8X' && size >= 10) {
        flags = data[0];
        cw = _le24(data, 4) + 1;
        ch = _le24(data, 7) + 1;
      }
      pos += size + (size & 1);
    }
    return WebpContainer._(chunks, flags, cw, ch);
  }
}

/// Bit flags of the `VP8X` chunk.
class Vp8xFlags {
  /// Animation flag.
  static const animation = 0x02;

  /// XMP metadata flag.
  static const xmp = 0x04;

  /// EXIF metadata flag.
  static const exif = 0x08;

  /// Alpha flag.
  static const alpha = 0x10;

  /// ICC profile flag.
  static const icc = 0x20;
}

/// Helper to assemble a RIFF/WEBP file from chunks.
class RiffBuilder {
  final _chunks = <RiffChunk>[];

  /// Appends a chunk with [tag] and [data].
  void add(String tag, Uint8List data) {
    _chunks.add(RiffChunk(tag, data));
  }

  /// Adds a `VP8X` chunk with the given flags and canvas size.
  void addVp8x(int flags, int width, int height) {
    final d = Uint8List(10);
    d[0] = flags;
    final w = width - 1;
    final h = height - 1;
    d[4] = w & 0xff;
    d[5] = (w >> 8) & 0xff;
    d[6] = (w >> 16) & 0xff;
    d[7] = h & 0xff;
    d[8] = (h >> 8) & 0xff;
    d[9] = (h >> 16) & 0xff;
    add('VP8X', d);
  }

  /// Serializes all chunks into a complete file.
  Uint8List build() {
    var total = 12;
    for (final c in _chunks) {
      total += 8 + c.data.length + (c.data.length & 1);
    }
    final out = Uint8List(total);
    out[0] = 0x52;
    out[1] = 0x49;
    out[2] = 0x46;
    out[3] = 0x46;
    final riffSize = total - 8;
    out[4] = riffSize & 0xff;
    out[5] = (riffSize >> 8) & 0xff;
    out[6] = (riffSize >> 16) & 0xff;
    out[7] = (riffSize >> 24) & 0xff;
    out[8] = 0x57;
    out[9] = 0x45;
    out[10] = 0x42;
    out[11] = 0x50;
    var pos = 12;
    for (final c in _chunks) {
      for (var i = 0; i < 4; i++) {
        out[pos + i] = c.tag.codeUnitAt(i);
      }
      final n = c.data.length;
      out[pos + 4] = n & 0xff;
      out[pos + 5] = (n >> 8) & 0xff;
      out[pos + 6] = (n >> 16) & 0xff;
      out[pos + 7] = (n >> 24) & 0xff;
      pos += 8;
      out.setRange(pos, pos + n, c.data);
      pos += n + (n & 1);
    }
    return out;
  }
}
