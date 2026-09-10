import 'dart:typed_data';

import '../webp_image.dart';

/// Number of bits of the first-level lookup table.
const huffmanTableBits = 8;

/// Mask for the first-level lookup table.
const huffmanTableMask = (1 << huffmanTableBits) - 1;

/// Number of bits of the code-lengths lookup table.
const lengthsTableBits = 7;

/// Maximum Huffman code length allowed by VP8L.
const maxAllowedCodeLength = 15;

/// A two-level Huffman lookup table.
///
/// Each entry packs `(bits << 16) | value`. For root entries pointing at a
/// second-level table, `bits` is larger than the root bits and `value` is the
/// offset of the sub-table.
class HuffmanTable {
  /// Packed table entries.
  final Int32List table;

  /// Number of bits of the root table.
  final int rootBits;

  HuffmanTable._(this.table, this.rootBits);

  /// Bits of the root entry (0 when the tree has a single symbol).
  int get rootBitsOfEntry0 => table[0] >> 16;

  /// Value of entry 0 (useful for single-symbol trees).
  int get valueOfEntry0 => table[0] & 0xffff;

  /// Builds a table from [codeLengths] (indexed by symbol).
  ///
  /// Throws [WebpFormatException] if the lengths do not describe a valid
  /// (complete) prefix code, unless only one symbol is used.
  static HuffmanTable build(List<int> codeLengths, int rootBits) {
    final n = codeLengths.length;
    final count = List<int>.filled(maxAllowedCodeLength + 1, 0);
    for (var i = 0; i < n; i++) {
      final l = codeLengths[i];
      if (l > maxAllowedCodeLength) {
        throw WebpFormatException('Invalid Huffman code length');
      }
      count[l]++;
    }
    if (count[0] == n) {
      throw WebpFormatException('Empty Huffman tree');
    }
    // Sort symbols by length.
    final offset = List<int>.filled(maxAllowedCodeLength + 1, 0);
    for (var l = 1; l < maxAllowedCodeLength; l++) {
      if (count[l] > (1 << l)) {
        throw WebpFormatException('Invalid Huffman tree');
      }
      offset[l + 1] = offset[l] + count[l];
    }
    final sorted = Uint16List(n);
    for (var s = 0; s < n; s++) {
      final l = codeLengths[s];
      if (l > 0) {
        sorted[offset[l]++] = s;
      }
    }
    final totalSize = _tableSize(count, rootBits, offset[maxAllowedCodeLength]);
    if (totalSize == 0) {
      throw WebpFormatException('Invalid Huffman tree');
    }
    final table = Int32List(totalSize);
    // Single symbol.
    if (offset[maxAllowedCodeLength] == 1) {
      final code = sorted[0]; // bits = 0
      for (var i = 0; i < totalSize; i++) {
        table[i] = code;
      }
      return HuffmanTable._(table, rootBits);
    }
    // Recompute the counts (consumed by the sort above via offset).
    for (var i = 0; i <= maxAllowedCodeLength; i++) {
      count[i] = 0;
    }
    for (var i = 0; i < n; i++) {
      count[codeLengths[i]]++;
    }
    var tableOff = 0;
    var tableBits = rootBits;
    var tableSize = 1 << tableBits;
    final mask = tableSize - 1;
    var key = 0;
    var numNodes = 1;
    var numOpen = 1;
    var symbol = 0;
    var low = -1;
    var step = 2;
    for (var l = 1; l <= rootBits; l++, step <<= 1) {
      numOpen <<= 1;
      numNodes += numOpen;
      numOpen -= count[l];
      if (numOpen < 0) throw WebpFormatException('Invalid Huffman tree');
      for (; count[l] > 0; count[l]--) {
        final code = (l << 16) | sorted[symbol++];
        for (var i = key; i < tableSize; i += step) {
          table[i] = code;
        }
        key = _nextKey(key, l);
      }
    }
    step = 2;
    for (var l = rootBits + 1; l <= maxAllowedCodeLength; l++, step <<= 1) {
      numOpen <<= 1;
      numNodes += numOpen;
      numOpen -= count[l];
      if (numOpen < 0) throw WebpFormatException('Invalid Huffman tree');
      for (; count[l] > 0; count[l]--) {
        if ((key & mask) != low) {
          tableOff += tableSize;
          tableBits = _nextTableBitSize(count, l, rootBits);
          tableSize = 1 << tableBits;
          if (tableOff + tableSize > totalSize) {
            throw WebpFormatException('Invalid Huffman tree');
          }
          low = key & mask;
          table[low] = ((tableBits + rootBits) << 16) | tableOff;
        }
        final code = ((l - rootBits) << 16) | sorted[symbol++];
        final start = tableOff + (key >> rootBits);
        for (var i = start; i < tableOff + tableSize; i += step) {
          table[i] = code;
        }
        key = _nextKey(key, l);
      }
    }
    if (numNodes != 2 * offset[maxAllowedCodeLength] - 1) {
      throw WebpFormatException('Incomplete Huffman tree');
    }
    return HuffmanTable._(table, rootBits);
  }

  static int _tableSize(List<int> countIn, int rootBits, int numSymbols) {
    final count = List<int>.from(countIn);
    var totalSize = 1 << rootBits;
    if (numSymbols == 1) return totalSize;
    final mask = totalSize - 1;
    var key = 0;
    var numOpen = 1;
    for (var l = 1; l <= rootBits; l++) {
      numOpen <<= 1;
      numOpen -= count[l];
      if (numOpen < 0) return 0;
      for (; count[l] > 0; count[l]--) {
        key = _nextKey(key, l);
      }
    }
    var low = -1;
    for (var l = rootBits + 1; l <= maxAllowedCodeLength; l++) {
      numOpen <<= 1;
      numOpen -= count[l];
      if (numOpen < 0) return 0;
      for (; count[l] > 0; count[l]--) {
        if ((key & mask) != low) {
          totalSize += 1 << _nextTableBitSize(count, l, rootBits);
          low = key & mask;
        }
        key = _nextKey(key, l);
      }
    }
    return totalSize;
  }

  static int _nextKey(int key, int len) {
    var step = 1 << (len - 1);
    while ((key & step) != 0) {
      step >>= 1;
    }
    return step != 0 ? (key & (step - 1)) + step : key;
  }

  static int _nextTableBitSize(List<int> count, int len, int rootBits) {
    var left = 1 << (len - rootBits);
    while (len < maxAllowedCodeLength) {
      left -= count[len];
      if (left <= 0) break;
      len++;
      left <<= 1;
    }
    return len - rootBits;
  }
}
