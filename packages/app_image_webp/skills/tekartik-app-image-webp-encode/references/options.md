# `WebpEncodeOptions` reference

All fields are optional named constructor parameters with libwebp defaults.

| Field | Default | `cwebp` flag | Effect |
| --- | --- | --- | --- |
| `lossless` | `false` | `-lossless` | VP8L lossless instead of VP8 lossy |
| `quality` | `75` | `-q` | lossy: quantizer (0 smallest .. 100 best); lossless: compression effort |
| `method` | `4` | `-m` | 0 fastest .. 6 smallest output |
| `alphaQuality` | `100` | `-alpha_q` | below 100 quantizes alpha levels (lossy alpha), lossy mode only |
| `alphaCompression` | `1` | `-alpha_method` | 0 raw alpha bytes, 1 lossless compressed alpha |
| `alphaFiltering` | `AlphaFiltering.fast` | `-alpha_filter` | `none`, `fast` (estimate best predictor), `best` (try all) |
| `exact` | `false` | `-exact` | keep RGB of fully transparent pixels |
| `snsStrength` | `50` | `-sns` | spatial noise shaping 0..100 (lossy) |
| `filterStrength` | `60` | `-f` | loop filter 0 (off) .. 100 (lossy) |
| `filterSharpness` | `0` | `-sharpness` | 0..7 (lossy) |
| `filterType` | `1` | `-strong` / `-nostrong` | 1 strong, 0 simple (lossy) |
| `segments` | `4` | `-segments` | 1..4 macroblock segments (lossy) |
| `pass` | `1` | `-pass` | entropy analysis passes 1..10 (lossy) |

`WebpEncodeOptions.preset(WebpPreset p, {double quality = 75})`:

| Preset | sns | sharpness | filter strength | segments |
| --- | --- | --- | --- | --- |
| `defaultPreset` | 50 | 0 | 60 | 4 |
| `picture` | 80 | 4 | 35 | 4 |
| `photo` | 80 | 3 | 30 | 4 |
| `drawing` | 25 | 6 | 10 | 4 |
| `icon` | 0 | 0 | 0 | 4 |
| `text` | 0 | 0 | 0 | 2 |

`copyWith(...)` returns a modified copy.

## Output structure

- Lossless: `RIFF` + `VP8L` chunk (alpha flag inside the bitstream).
- Lossy opaque: `RIFF` + `VP8 ` chunk.
- Lossy with transparency: `RIFF` + `VP8X` (alpha flag) + `ALPH` + `VP8 `.

## Expected sizes (1024x574 photo, method 4)

| Mode | This package | `cwebp` |
| --- | --- | --- |
| lossy q75 | 27.3 KB | 27.3 KB |
| lossless | 188.0 KB | 187.9 KB |
