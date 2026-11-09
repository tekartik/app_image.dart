# tekartik_app_image

The image vocabulary shared by the tekartik image packages, in pure Dart:
encodings (jpg, png, webp, with their mime type and extension), image
metadata and bytes (`ImageMeta`, `ImageData`), sources, resize options, plus
encoding/decoding helpers on [package:image](https://pub.dev/packages/image)
(webp through the pure Dart `tekartik_app_image_webp` codec), a layer
composer, a placeholder generator and a `cwebp` file converter.

## Getting started

Not on pub.dev, add it as a git dependency:

```yaml
dependencies:
  tekartik_app_image:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_image
```

```dart
import 'package:tekartik_app_image/app_image_bytes_utils.dart';
import 'package:tekartik_app_image/app_image_placeholder.dart';
import 'package:tekartik_app_image/image_decoder/image_decoder.dart';

Future<void> main() async {
  // A 64x64 opaque red png (color read as 0xAARRGGBB).
  var data = await generatePlaceholderImage(
    encoding: const ImageEncodingPng(),
    width: 64,
    height: 64,
    color: 0xFFFF0000,
  );
  print('${data.encoding} ${data.width}x${data.height}'); // Png 64x64
  print(isPng(data.bytes)); // true
  var meta = await getImageMetaFromBytes(data.bytes);
  print(meta); // {width: 64, height: 64, encoding: Png}
}
```

Platforms: every platform (Dart VM, Flutter, web), except
`webp_io.dart`, which needs `dart:io` and the `cwebp` command.

## Libraries

| Import (`package:tekartik_app_image/...`) | Gives |
|---|---|
| `app_image.dart` | `ImageEncodingJpg/Png/Webp`, mime type and extension constants, `ImageMeta`, `ImageData`, `ImageSource` |
| `app_image_bytes_utils.dart` | `isJpg`, `isPng`, `isWebp` (magic numbers, no decoding) |
| `image_decoder/image_decoder.dart` | `getImageEncodingFromBytes`, `getImageMetaFromBytes` (full decode) |
| `image_composer/image_composer.dart` | `composeImage`: layers (source, crop, destination) into one encoded image |
| `app_image_placeholder.dart` | `generatePlaceholderImage` (single color) |
| `app_color.dart` | `argbToColorUint32(a, r, g, b)`, packs `0xAARRGGBB` |
| `app_image_resize.dart` | `ResizeOptions`, `CropRect` (data holders) |
| `webp_io.dart` | `fileCopyToWebp` (crop, resize, then `cwebp`), io only |

## Common pitfalls

- `getImageMetaFromBytes` decodes the whole image to read its size: use
  `getImageEncodingFromBytes` when only the format matters.
- A decoder reports an unknown quality (`-1`): re-encoding a jpeg with that
  encoding uses quality 1; give a quality.
- The placeholder has no alpha channel: a translucent color comes out
  opaque.

More in the package skills (`skills/`).
