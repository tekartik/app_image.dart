import 'dart:typed_data';

import 'lossless_dsp.dart';

/// Hash-addressed cache of recently seen ARGB colors.
class ColorCache {
  /// Cached colors, `1 << hashBits` entries.
  final Uint32List colors;

  /// Shift applied to the multiplicative hash (`32 - hashBits`).
  final int hashShift;

  /// Number of index bits.
  final int hashBits;

  /// Creates a cache with `2^hashBits` entries.
  ColorCache(this.hashBits)
    : colors = Uint32List(1 << hashBits),
      hashShift = 32 - hashBits;

  /// Index of [argb] in the cache.
  int index(int argb) => hashPix(argb, hashShift);

  /// Stores [argb] at its hashed slot.
  void insert(int argb) {
    colors[hashPix(argb, hashShift)] = argb;
  }

  /// Returns the color at slot [key].
  int lookup(int key) => colors[key];

  /// Stores [argb] at slot [key].
  void set(int key, int argb) {
    colors[key] = argb;
  }

  /// Returns the slot of [argb] if present, -1 otherwise.
  int contains(int argb) {
    final key = hashPix(argb, hashShift);
    return colors[key] == argb ? key : -1;
  }
}
