/// Packs [a], [r], [g], [b] (0 to 255 each) into a `0xAARRGGBB` color, the
/// layout read by `generatePlaceholderImage(color:)` (and Flutter's `Color`).
///
/// The result is a positive int on every platform, the web included.
int argbToColorUint32(int a, int r, int g, int b) {
  // No `a << 24`: on the web it gives a negative int when a >= 128.
  return (a & 0xFF) * 0x1000000 +
      ((r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF));
}
