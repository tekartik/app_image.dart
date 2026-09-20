---
name: tekartik-app-image-model
description: >-
  Use when Dart or Flutter code needs the shared image model of
  tekartik_app_image: ImageEncoding / ImageEncodingJpg / ImageEncodingPng /
  ImageEncodingWebp, mimeTypeJpg / mimeTypePng / mimeTypeWebp and
  extensionJpg / extensionPng / extensionWebp constants, ImageMeta and
  ImageData (bytes, width, height, encoding), ImageSource / ImageSourceData /
  ImageSourceAsyncData, ResizeOptions and CropRect, or must sniff an image
  format from its bytes with isJpg, isPng, isWebp, getImageEncodingFromBytes
  and getImageMetaFromBytes.
---

# Image model, encodings and format detection (tekartik_app_image)

`tekartik_app_image` holds the small, platform independent image vocabulary
shared by the tekartik image packages: encodings (jpg/png/webp with their mime
type and extension), image metadata and bytes holders, image sources and
resize options. It does almost no image processing itself; the actual pixel
work lives in `tekartik_app_image_web` (canvas), in the composer (see the
sibling skill [../tekartik-app-image-compose/SKILL.md](../tekartik-app-image-compose/SKILL.md))
and in `package:image`.

## Guidelines

* Depend on it from git (it is not published on pub.dev):

  ```yaml
  dependencies:
    tekartik_app_image:
      git:
        url: https://github.com/tekartik/app_image.dart
        path: packages/app_image
      version: '>=0.1.0'
  ```

* Entry points, import only what you need:
  * `package:tekartik_app_image/app_image.dart` — encodings, constants,
    `ImageMeta`, `ImageData`, `ImageSource*`. This is the one to import.
  * `package:tekartik_app_image/app_image_bytes_utils.dart` — `isJpg`,
    `isPng`, `isWebp`.
  * `package:tekartik_app_image/image_decoder/image_decoder.dart` —
    `getImageEncodingFromBytes`, `getImageMetaFromBytes`.
  * `package:tekartik_app_image/app_image_resize.dart` — `ResizeOptions`,
    `CropRect`.
  * `package:tekartik_app_image/app_color.dart` — `argbToColorUint32`.
* `ImageEncoding` is the abstract type with `mimeType` and `extension`.
  Use `const ImageEncodingPng()` and `const ImageEncodingWebp()` (both const
  constructors) and `ImageEncodingJpg(quality: 0..100)`. A quality outside
  `-1..100` throws `ArgumentError`; `imageEncodingJpgQualityUnknown` (`-1`)
  means "jpeg, quality unknown" and is what a decoder reports.
* Switch on the encoding with `is` (`if (encoding is ImageEncodingJpg)`), never
  by comparing `mimeType` strings by hand. Use `encoding.extension` to name
  output files so the extension always matches the bytes.
* `ImageMeta(encoding:, width:, height:)` describes an image; `ImageData`
  extends it with `bytes` (`Uint8List`). Every producer in this ecosystem
  returns `ImageData`, so a result already carries its size and encoding —
  do not re-decode to find them. `toDebugMap()` / `toString()` are for logs.
* `ImageSource` is the input side: `ImageSource.bytes(bytes)` and
  `ImageSourceData(bytes)` both build a value implementing **both**
  `ImageSourceData` (sync `bytes`) and `ImageSourceAsyncData`
  (`Future<Uint8List> getBytes()`). Accept an `ImageSource` in your APIs and
  check with `is` before reading; consumers such as the image composer and
  `tekartik_app_pick_crop_image_flutter` implement `ImageSourceAsyncData` with
  their own lazy source (a picked file, an asset), so always prefer
  `await source.getBytes()` over `source.bytes`.
* Format detection is magic-number based and cheap: `isJpg`, `isPng`,
  `isWebp` take a `Uint8List` and only look at the first bytes (`isWebp`
  checks the `RIFF`/`WEBP` header). They never decode, so a corrupted body
  still returns true.
* `getImageEncodingFromBytes(bytes)` maps those checks to an `ImageEncoding`
  and throws `UnsupportedError` for anything else (gif, bmp, tiff...). A jpeg
  detected this way has `quality == imageEncodingJpgQualityUnknown`.
* `getImageMetaFromBytes(bytes)` is async and **fully decodes** the image with
  `package:image` to get `width`/`height`. Call it only when the size is
  really needed, and not in a tight loop; use `getImageEncodingFromBytes` when
  only the format matters.
* `ResizeOptions(width:, height:, cropRect:, encoding:)` is a plain data
  holder (default encoding `ImageEncodingPng()`); `width` and `height` are
  both required but nullable — pass one of them to keep the aspect ratio, both
  `null` to keep the original size. `CropRect` is `Rect<double>` from
  `package:tekartik_common_utils/size/size.dart`, in source pixels:
  `CropRect.fromLTWH(left, top, width, height)`. The resizing itself is done
  by `tekartik_app_image_web` (`resizeTo`) or by the picker package.
* `argbToColorUint32(a, r, g, b)` packs to `0xAABBGGRR` (red in the low byte),
  which is *not* the `0xAARRGGBB` order read back by
  `generatePlaceholderImage(color:)`. Pass a literal such as `0xFFFF0000`
  (opaque red) when you want a predictable colour.
* Everything here is pure Dart with no `dart:io`/`dart:ui` dependency, so it
  works on the VM, in Flutter and on the web, and it is trivially unit
  testable: build `ImageData` values in tests instead of mocking.

## Examples

Sniff the format, then read the size only when needed:

```dart
import 'dart:io';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/app_image_bytes_utils.dart';
import 'package:tekartik_app_image/image_decoder/image_decoder.dart';

Future<void> main() async {
  var bytes = await File('photo.jpg').readAsBytes();

  // Cheap header checks.
  if (!isJpg(bytes) && !isPng(bytes) && !isWebp(bytes)) {
    stderr.writeln('not a supported image');
    return;
  }

  // Header check -> encoding (throws UnsupportedError otherwise).
  var encoding = getImageEncodingFromBytes(bytes);
  print('${encoding.mimeType} ${encoding.extension}'); // image/jpeg .jpg
  if (encoding is ImageEncodingJpg &&
      encoding.quality == imageEncodingJpgQualityUnknown) {
    print('jpeg, quality not recoverable from the bytes');
  }

  // Full decode, only when the dimensions are needed.
  var meta = await getImageMetaFromBytes(bytes);
  print('${meta.width}x${meta.height} ${meta.encoding}');
}
```

Carry bytes + metadata as a single value:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/image_decoder/image_decoder.dart';

/// Wrap raw bytes, reading the size and encoding once.
Future<ImageData> imageDataFromBytes(Uint8List bytes) async {
  var meta = await getImageMetaFromBytes(bytes);
  return ImageData(
    bytes: bytes,
    encoding: meta.encoding,
    width: meta.width,
    height: meta.height,
  );
}

/// The extension always matches the bytes.
Future<File> writeImageData(String basename, ImageData data) async {
  var file = File('$basename${data.encoding.extension}');
  await file.writeAsBytes(data.bytes);
  print(data.toDebugMap()); // {width: .., height: .., encoding: .., sizeInBytes: ..}
  return file;
}
```

Accept any `ImageSource` in your own API:

```dart
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';

/// Works for in memory bytes and for lazy sources (picked file, asset...).
Future<Uint8List> readImageSource(ImageSource source) async {
  if (source is ImageSourceAsyncData) {
    return await source.getBytes();
  }
  if (source is ImageSourceData) {
    return source.bytes;
  }
  throw UnsupportedError('Unsupported image source $source');
}

Future<void> main() async {
  var bytes = Uint8List.fromList([137, 80, 78, 71]);
  // ImageSource.bytes() and ImageSourceData() both implement the 2 interfaces.
  var source = ImageSource.bytes(bytes);
  print((await readImageSource(source)).length);
}
```

Describe a resize/crop request:

```dart
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/app_image_resize.dart';

/// 256 pixels wide, height computed from the ratio, jpeg output.
ResizeOptions thumbnailOptions() =>
    ResizeOptions(width: 256, height: null, encoding: ImageEncodingJpg(quality: 80));

/// Square png, cropping a 1000x1000 region of the source first.
ResizeOptions squareOptions(int size) => ResizeOptions(
  width: size,
  height: size,
  cropRect: CropRect.fromLTWH(0, 0, 1000, 1000),
  encoding: const ImageEncodingPng(),
);
```
