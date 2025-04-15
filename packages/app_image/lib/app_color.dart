/// Color
int argbToColorUint32(int a, int r, int g, int b) {
  return (a << 24) | (b << 16) | (g << 8) | r;
}
