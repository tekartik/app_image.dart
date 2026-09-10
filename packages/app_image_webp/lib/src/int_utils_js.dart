/// Arithmetic (sign-preserving) right shift: `floor(v / 2^n)`.
///
/// dart2js maps `>>` to an unsigned result, so negative values need care.
int sar(int v, int n) => v >= 0 ? (v >> n) : -((-v + (1 << n) - 1) >> n);
