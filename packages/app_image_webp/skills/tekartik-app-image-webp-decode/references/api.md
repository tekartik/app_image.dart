# Decoding API reference (`package:tekartik_app_image_webp/webp.dart`)

## Functions

| Function | Returns | Notes |
| --- | --- | --- |
| `webpInfo(Uint8List bytes)` | `WebpInfo` | Header only; throws `WebpFormatException` |
| `decodeWebp(Uint8List bytes)` | `WebpImage` | Full decode; throws `WebpFormatException` (also for animations) |

`package:tekartik_app_image_webp/image_web.dart`:

| Function | Returns | Notes |
| --- | --- | --- |
| `decodeImageWebp(Uint8List bytes)` | `img.Image?` | null on invalid data |
| `webpImageToImage(WebpImage)` | `img.Image` | 8-bit RGBA, copied buffer |
| `imageToWebpImage(img.Image)` | `WebpImage` | any format converted to 8-bit RGBA |

## `WebpInfo`

| Field | Type | Meaning |
| --- | --- | --- |
| `width`, `height` | `int` | canvas size (VP8X) or bitstream size |
| `format` | `WebpFormat?` | `lossy` (`VP8 `) or `lossless` (`VP8L`) |
| `isLossless` | `bool` | `format == WebpFormat.lossless` |
| `hasAlpha` | `bool` | VP8X alpha flag, `ALPH` chunk present, or VP8L alpha hint |
| `hasAnimation` | `bool` | `ANIM`/`ANMF` file (not decodable) |
| `isExtended` | `bool` | uses the `VP8X` container |
| `hasIccProfile`, `hasExif`, `hasXmp` | `bool` | metadata chunks present |

## `WebpImage`

| Member | Meaning |
| --- | --- |
| `width`, `height` | pixel size (1..16383) |
| `rgba` | `Uint8List`, `width * height * 4`, RGBA, straight alpha |
| `pixelCount` | `width * height` |
| `hasAlpha` | true if any alpha byte differs from 255 (scans the pixels) |
| `getPixel(x, y)` | `0xAARRGGBB` int |
| `setPixel(x, y, argb)`, `setRgba(x, y, r, g, b, [a])` | write pixels |
| `toArgb()` / `WebpImage.fromArgb(w, h, list)` | packed 32-bit conversions |
| `WebpImage.blank(w, h)` | opaque black |
| `WebpImage.fromRgb(w, h, rgb)` | from 3 bytes per pixel |
| `clone()` | deep copy |

## `WebpFormatException`

Implements `FormatException`; `message` describes the problem (truncated
data, bad signature, invalid Huffman tree, animation not supported, ...).
