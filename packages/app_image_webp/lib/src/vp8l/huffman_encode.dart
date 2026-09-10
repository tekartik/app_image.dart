import 'dart:typed_data';

/// A Huffman code: per-symbol code lengths and (bit-reversed) codes.
class HuffmanTreeCode {
  /// Number of symbols.
  final int numSymbols;

  /// Code length per symbol (0 = unused).
  final Uint8List codeLengths;

  /// Code per symbol, ready to be written LSB first.
  final Uint16List codes;

  /// Creates an empty code for [numSymbols] symbols.
  HuffmanTreeCode(this.numSymbols)
    : codeLengths = Uint8List(numSymbols),
      codes = Uint16List(numSymbols);
}

/// A token of the run-length coded code-lengths sequence.
class HuffmanTreeToken {
  /// Code (0..15 literal length, 16/17/18 repeat codes).
  final int code;

  /// Extra bits for repeat codes.
  final int extraBits;

  /// Creates a token.
  HuffmanTreeToken(this.code, this.extraBits);
}

const _maxAllowedCodeLength = 15;

bool _valuesShouldBeCollapsed(int a, int b) => (a - b).abs() < 4;

/// Changes the population counts so that the RLE-coded Huffman tree is smaller.
void _optimizeHuffmanForRle(
  int length,
  Uint8List goodForRle,
  Uint32List counts,
) {
  for (; length >= 0; length--) {
    if (length == 0) return;
    if (counts[length - 1] != 0) break;
  }
  {
    var symbol = counts[0];
    var stride = 0;
    for (var i = 0; i < length + 1; i++) {
      if (i == length || counts[i] != symbol) {
        if ((symbol == 0 && stride >= 5) || (symbol != 0 && stride >= 7)) {
          for (var k = 0; k < stride; k++) {
            goodForRle[i - k - 1] = 1;
          }
        }
        stride = 1;
        if (i != length) symbol = counts[i];
      } else {
        stride++;
      }
    }
  }
  {
    var stride = 0;
    var limit = counts[0];
    var sum = 0;
    for (var i = 0; i < length + 1; i++) {
      if (i == length ||
          goodForRle[i] != 0 ||
          (i != 0 && goodForRle[i - 1] != 0) ||
          !_valuesShouldBeCollapsed(counts[i], limit)) {
        if (stride >= 4 || (stride >= 3 && sum == 0)) {
          var count = (sum + stride ~/ 2) ~/ stride;
          if (count < 1) count = 1;
          if (sum == 0) count = 0;
          for (var k = 0; k < stride; k++) {
            counts[i - k - 1] = count;
          }
        }
        stride = 0;
        sum = 0;
        if (i < length - 3) {
          limit =
              (counts[i] + counts[i + 1] + counts[i + 2] + counts[i + 3] + 2) ~/
              4;
        } else if (i < length) {
          limit = counts[i];
        } else {
          limit = 0;
        }
      }
      stride++;
      if (i != length) {
        sum += counts[i];
        if (stride >= 4) limit = (sum + stride ~/ 2) ~/ stride;
      }
    }
  }
}

class _Node {
  int totalCount;
  int value;
  int left; // index in pool or -1
  int right;
  _Node(this.totalCount, this.value, this.left, this.right);
}

void _setBitDepths(
  _Node tree,
  List<_Node> pool,
  Uint8List bitDepths,
  int level,
) {
  if (tree.left >= 0) {
    _setBitDepths(pool[tree.left], pool, bitDepths, level + 1);
    _setBitDepths(pool[tree.right], pool, bitDepths, level + 1);
  } else {
    bitDepths[tree.value] = level;
  }
}

/// Computes optimal code lengths limited to [treeDepthLimit] bits.
void _generateOptimalTree(
  Uint32List histogram,
  int histogramSize,
  int treeDepthLimit,
  Uint8List bitDepths,
) {
  var treeSizeOrig = 0;
  for (var i = 0; i < histogramSize; i++) {
    if (histogram[i] != 0) treeSizeOrig++;
  }
  if (treeSizeOrig == 0) return;
  for (var countMin = 1; ; countMin *= 2) {
    var tree = <_Node>[];
    for (var j = 0; j < histogramSize; j++) {
      if (histogram[j] != 0) {
        final count = histogram[j] < countMin ? countMin : histogram[j];
        tree.add(_Node(count, j, -1, -1));
      }
    }
    // Sort by decreasing count, then decreasing value.
    tree.sort((a, b) {
      if (a.totalCount != b.totalCount) return b.totalCount - a.totalCount;
      return a.value - b.value;
    });
    final pool = <_Node>[];
    var treeSize = tree.length;
    if (treeSize > 1) {
      while (treeSize > 1) {
        pool.add(tree[treeSize - 1]);
        pool.add(tree[treeSize - 2]);
        final count =
            pool[pool.length - 1].totalCount + pool[pool.length - 2].totalCount;
        treeSize -= 2;
        var k = 0;
        for (; k < treeSize; k++) {
          if (tree[k].totalCount <= count) break;
        }
        final node = _Node(count, -1, pool.length - 1, pool.length - 2);
        tree.insert(k, node);
        tree.length = treeSize + 1;
        treeSize++;
      }
      _setBitDepths(tree[0], pool, bitDepths, 0);
    } else if (treeSize == 1) {
      bitDepths[tree[0].value] = 1;
    }
    var maxDepth = bitDepths[0];
    for (var j = 1; j < histogramSize; j++) {
      if (maxDepth < bitDepths[j]) maxDepth = bitDepths[j];
    }
    if (maxDepth <= treeDepthLimit) break;
  }
}

void _codeRepeatedValues(
  int repetitions,
  List<HuffmanTreeToken> tokens,
  int value,
  int prevValue,
) {
  if (value != prevValue) {
    tokens.add(HuffmanTreeToken(value, 0));
    repetitions--;
  }
  while (repetitions >= 1) {
    if (repetitions < 3) {
      for (var i = 0; i < repetitions; i++) {
        tokens.add(HuffmanTreeToken(value, 0));
      }
      break;
    } else if (repetitions < 7) {
      tokens.add(HuffmanTreeToken(16, repetitions - 3));
      break;
    } else {
      tokens.add(HuffmanTreeToken(16, 3));
      repetitions -= 6;
    }
  }
}

void _codeRepeatedZeros(int repetitions, List<HuffmanTreeToken> tokens) {
  while (repetitions >= 1) {
    if (repetitions < 3) {
      for (var i = 0; i < repetitions; i++) {
        tokens.add(HuffmanTreeToken(0, 0));
      }
      break;
    } else if (repetitions < 11) {
      tokens.add(HuffmanTreeToken(17, repetitions - 3));
      break;
    } else if (repetitions < 139) {
      tokens.add(HuffmanTreeToken(18, repetitions - 11));
      break;
    } else {
      tokens.add(HuffmanTreeToken(18, 0x7f));
      repetitions -= 138;
    }
  }
}

/// Run-length codes the code lengths of [tree] into tokens.
List<HuffmanTreeToken> createCompressedHuffmanTree(HuffmanTreeCode tree) {
  final tokens = <HuffmanTreeToken>[];
  final depthSize = tree.numSymbols;
  var prevValue = 8;
  var i = 0;
  while (i < depthSize) {
    final value = tree.codeLengths[i];
    var k = i + 1;
    while (k < depthSize && tree.codeLengths[k] == value) {
      k++;
    }
    final runs = k - i;
    if (value == 0) {
      _codeRepeatedZeros(runs, tokens);
    } else {
      _codeRepeatedValues(runs, tokens, value, prevValue);
      prevValue = value;
    }
    i += runs;
  }
  return tokens;
}

const _reversedBits = [
  0x0,
  0x8,
  0x4,
  0xc,
  0x2,
  0xa,
  0x6,
  0xe,
  0x1,
  0x9,
  0x5,
  0xd,
  0x3,
  0xb,
  0x7,
  0xf,
];

int _reverseBits(int numBits, int bits) {
  var retval = 0;
  var i = 0;
  while (i < numBits) {
    i += 4;
    retval |= _reversedBits[bits & 0xf] << (_maxAllowedCodeLength + 1 - i);
    bits >>= 4;
  }
  retval >>= (_maxAllowedCodeLength + 1 - numBits);
  return retval;
}

void _convertBitDepthsToSymbols(HuffmanTreeCode tree) {
  final len = tree.numSymbols;
  final nextCode = List<int>.filled(_maxAllowedCodeLength + 1, 0);
  final depthCount = List<int>.filled(_maxAllowedCodeLength + 1, 0);
  for (var i = 0; i < len; i++) {
    depthCount[tree.codeLengths[i]]++;
  }
  depthCount[0] = 0;
  var code = 0;
  for (var i = 1; i <= _maxAllowedCodeLength; i++) {
    code = (code + depthCount[i - 1]) << 1;
    nextCode[i] = code;
  }
  for (var i = 0; i < len; i++) {
    final codeLength = tree.codeLengths[i];
    tree.codes[i] = _reverseBits(codeLength, nextCode[codeLength]++);
  }
}

/// Builds a length-limited Huffman code for [histogram] (modified in place
/// to be more RLE friendly) into [huffCode].
void createHuffmanTree(
  Uint32List histogram,
  int treeDepthLimit,
  HuffmanTreeCode huffCode,
) {
  final numSymbols = huffCode.numSymbols;
  final bufRle = Uint8List(numSymbols);
  _optimizeHuffmanForRle(numSymbols, bufRle, histogram);
  huffCode.codeLengths.fillRange(0, numSymbols, 0);
  _generateOptimalTree(
    histogram,
    numSymbols,
    treeDepthLimit,
    huffCode.codeLengths,
  );
  _convertBitDepthsToSymbols(huffCode);
}
