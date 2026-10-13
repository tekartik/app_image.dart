/// Token buffer of the VP8 encoder (token_enc.c): the coefficient bits of a
/// pass, coded once the final probabilities are known.
library;

import 'dart:typed_data';

import 'bool_writer.dart';
import 'cost.dart';
import 'tables.dart';

/// Coefficient tokens of one pass, in coding order.
class Vp8TokenBuffer {
  // bit #15: bit value, bit #14: constant probability, bits #0..13: the
  // probability index (or the constant probability).
  static const _fixedProbaBit = 1 << 14;

  var _tokens = Uint16List(8192);
  var _count = 0;

  /// Removes every token.
  void clear() => _count = 0;

  void _add(int token) {
    if (_count == _tokens.length) {
      _tokens = Uint16List(_tokens.length * 2)..setAll(0, _tokens);
    }
    _tokens[_count++] = token;
  }

  /// Adds [bit] coded with the probability at [probaIndex] and records it in
  /// the statistics of [proba]. Returns [bit].
  int addToken(Vp8EncProba proba, int bit, int probaIndex) {
    _add((bit << 15) | probaIndex);
    return proba.recordStats(bit, probaIndex);
  }

  /// Adds [bit] coded with the constant probability [proba].
  void addConstantToken(int bit, int proba) {
    _add((bit << 15) | _fixedProbaBit | proba);
  }

  /// Codes every token with [probas].
  void emit(Vp8BoolWriter bw, Uint8List probas) {
    for (var i = 0; i < _count; i++) {
      final token = _tokens[i];
      final bit = (token >> 15) & 1;
      if ((token & _fixedProbaBit) != 0) {
        bw.putBit(bit, token & 0xff);
      } else {
        bw.putBit(bit, probas[token & 0x3fff]);
      }
    }
  }
}

/// Records the tokens of [res] in context [ctx] (and their statistics);
/// returns 1 if [res] has a non-zero coefficient.
int recordCoeffTokens(
  Vp8EncProba proba,
  Vp8TokenBuffer tokens,
  int ctx,
  Vp8Residual res,
) {
  final coeffs = res.coeffs;
  final off = res.coeffsOff;
  final type = res.coeffType;
  final last = res.last;
  var n = res.first;
  var base = Vp8EncProba.probaOffset(type, bands[n], ctx);
  if (tokens.addToken(proba, last >= 0 ? 1 : 0, base) == 0) {
    return 0;
  }
  while (n < 16) {
    final c = coeffs[off + n++];
    final sign = c < 0;
    final v = sign ? -c : c;
    if (tokens.addToken(proba, v != 0 ? 1 : 0, base + 1) == 0) {
      base = Vp8EncProba.probaOffset(type, bands[n], 0);
      continue;
    }
    if (tokens.addToken(proba, v > 1 ? 1 : 0, base + 2) == 0) {
      base = Vp8EncProba.probaOffset(type, bands[n], 1);
    } else {
      if (tokens.addToken(proba, v > 4 ? 1 : 0, base + 3) == 0) {
        if (tokens.addToken(proba, v != 2 ? 1 : 0, base + 4) != 0) {
          tokens.addToken(proba, v == 4 ? 1 : 0, base + 5);
        }
      } else if (tokens.addToken(proba, v > 10 ? 1 : 0, base + 6) == 0) {
        if (tokens.addToken(proba, v > 6 ? 1 : 0, base + 7) == 0) {
          tokens.addConstantToken(v == 6 ? 1 : 0, 159);
        } else {
          tokens.addConstantToken(v >= 9 ? 1 : 0, 165);
          tokens.addConstantToken((v & 1) == 0 ? 1 : 0, 145);
        }
      } else {
        int mask;
        List<int> tab;
        var residue = v - 3;
        if (residue < (8 << 1)) {
          tokens.addToken(proba, 0, base + 8);
          tokens.addToken(proba, 0, base + 9);
          residue -= 8 << 0;
          mask = 1 << 2;
          tab = cat3;
        } else if (residue < (8 << 2)) {
          tokens.addToken(proba, 0, base + 8);
          tokens.addToken(proba, 1, base + 9);
          residue -= 8 << 1;
          mask = 1 << 3;
          tab = cat4;
        } else if (residue < (8 << 3)) {
          tokens.addToken(proba, 1, base + 8);
          tokens.addToken(proba, 0, base + 10);
          residue -= 8 << 2;
          mask = 1 << 4;
          tab = cat5;
        } else {
          tokens.addToken(proba, 1, base + 8);
          tokens.addToken(proba, 1, base + 10);
          residue -= 8 << 3;
          mask = 1 << 10;
          tab = cat6;
        }
        var ti = 0;
        while (mask != 0) {
          tokens.addConstantToken((residue & mask) != 0 ? 1 : 0, tab[ti++]);
          mask >>= 1;
        }
      }
      base = Vp8EncProba.probaOffset(type, bands[n], 2);
    }
    tokens.addConstantToken(sign ? 1 : 0, 128);
    if (n == 16 || tokens.addToken(proba, n <= last ? 1 : 0, base) == 0) {
      return 1; // EOB
    }
  }
  return 1;
}
