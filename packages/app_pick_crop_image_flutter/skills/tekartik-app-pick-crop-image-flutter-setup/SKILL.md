---
name: tekartik-app-pick-crop-image-flutter-setup
description: >-
  Use when a Flutter app must let the user pick an image (gallery, camera,
  desktop file dialog, asset or memory bytes), crop it and get resized encoded
  bytes with tekartik_app_pick_crop_image_flutter: pickCropImage,
  PickCropImageOptions, PickCropImageSourceGallery, PickCropImageSourceCamera,
  PickCropImageSourceMemory, ImageSourceAsset, SourceCameraDevice,
  ovalCropMask, autoCrop, ImageEncodingJpg / ImageEncodingPng, the returned
  ImageData and saveImageFile.
---

# Pick and crop an image (tekartik_app_pick_crop_image_flutter)

One call, `pickCropImage(context)`, runs the whole flow: pick an image
(gallery, camera, desktop file dialog, asset or in memory bytes), let the user
crop it on a full screen editor page, then resize and encode it. It returns an
`ImageData` (bytes + width + height + encoding) or `null` if the user
cancelled. Works on Android, iOS, desktop and web.

## Guidelines

* Git dependency (not on pub.dev). It transitively pulls `image_picker`,
  `extended_image`, `tekartik_app_image_web` and the `tekaly_file_picker_flutter`
  / `tekaly_file_download` packages from
  `https://github.com/tekartikprj/tekaly`, so that repository must be
  reachable when resolving:

  ```yaml
  dependencies:
    tekartik_app_pick_crop_image_flutter:
      git:
        url: https://github.com/tekartik/app_image.dart
        path: packages/app_pick_crop_image_flutter
      version: '>=0.1.0'
  ```

* A single public entry point, never import `src/...`:

  ```dart
  import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';
  ```

  It re-exports what you need for the result: `ImageData`, `ImageEncoding`,
  `ImageEncodingJpg`, `ImageEncodingPng`, `mimeTypeJpg`, `mimeTypePng`,
  `extensionJpg`, `extensionPng`.
* `Future<ImageData?> pickCropImage(BuildContext context, {PickCropImageOptions? options})`
  pushes its own routes, so call it from a widget callback with a `Navigator`
  in scope, and check `mounted` / `context.mounted` after awaiting it before
  touching the context. `null` means cancelled (pick or crop errors are caught
  internally and also yield `null`).
* `PickCropImageOptions({source, width, height, aspectRatio, encoding, ovalCropMask, autoCrop})`:
  * `source` defaults to `const PickCropImageSourceGallery()`. Others:
    `PickCropImageSourceCamera(preferredCameraDevice: SourceCameraDevice.rear|front)`,
    `PickCropImageSourceMemory(bytes: uint8List)` and
    `ImageSourceAsset(name: 'assets/img/x.jpg')` (loaded with `rootBundle`).
    The last two skip the picker and go straight to the crop page.
  * `width`/`height` are the wanted output size. Setting both also fixes the
    crop ratio (`aspectRatio` is then `width / height`); `aspectRatio` alone
    constrains the crop without forcing an output size; leaving everything
    `null` keeps the cropped size.
  * `encoding` defaults to `const ImageEncodingPng()`; use
    `ImageEncodingJpg(quality: 0..100)` for photos. Webp is not supported here.
  * `ovalCropMask: true` draws a round mask over the crop editor — the
    produced image is still a rectangle, clip it at display time
    (`ClipOval`).
  * `autoCrop: true` skips the interactive crop page: the image is cropped
    centered to `aspectRatio` when there is one, otherwise kept whole.
* The result is an `ImageData`: display with `Image.memory(data.bytes)`, size
  with `data.width`/`data.height`, and use `data.encoding.mimeType` /
  `data.encoding.extension` to name or upload it — never re-sniff the bytes.
* `saveImageFile(bytes:, mimeType:, filename:)` exports the result: a browser
  download on the web, a save dialog elsewhere.
* Platform notes:
  * Web: it must be triggered by a user gesture, and if the user cancels the
    browser file dialog the future may never complete — keep the UI usable
    instead of showing a blocking spinner.
  * Linux/Windows/macOS: picking goes through the `tekaly_file_picker_flutter`
    file dialog (which remembers the last directory), camera or gallery alike.
  * Android/iOS: `image_picker` rules apply, so declare the usual
    `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` entries in
    `Info.plist`.
  * Resizing and encoding run through `compute()`: a background isolate with
    `package:image` on mobile/desktop, the browser canvas on the web.
* `PickCropConvertImageOptions` is exported for the internal conversion
  callback; normal code only needs `PickCropImageOptions`. `CropRect` is not
  re-exported here — import
  `package:tekartik_app_image/app_image_resize.dart` if you really need it.
* Keep `pickCropImage` out of your testable logic: it needs plugins and a
  navigator. Put the handling of the returned `ImageData` in a plain function
  and unit test that instead (the package's own test suite is a placeholder).

## Examples

Pick from the gallery, crop to a 1024x1024 jpeg and show it:

```dart
import 'package:flutter/material.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';

class PickImageBody extends StatefulWidget {
  const PickImageBody({super.key});

  @override
  State<PickImageBody> createState() => _PickImageBodyState();
}

class _PickImageBodyState extends State<PickImageBody> {
  ImageData? _data;

  Future<void> _pick() async {
    var data = await pickCropImage(
      context,
      options: PickCropImageOptions(
        width: 1024,
        height: 1024,
        encoding: ImageEncodingJpg(quality: 75),
      ),
    );
    if (data == null || !mounted) {
      return; // cancelled
    }
    setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    var data = _data;
    return Column(
      children: [
        ElevatedButton(onPressed: _pick, child: const Text('Pick image')),
        if (data != null) ...[
          Text('${data.width}x${data.height} ${data.encoding.mimeType}'),
          Image.memory(data.bytes, fit: BoxFit.contain),
        ],
      ],
    );
  }
}
```

Front camera avatar with a round mask, and a banner cropped automatically:

```dart
import 'package:flutter/material.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';

/// Square jpeg, oval mask in the editor (clip it with ClipOval at display).
Future<ImageData?> pickAvatar(BuildContext context) => pickCropImage(
  context,
  options: PickCropImageOptions(
    source: const PickCropImageSourceCamera(
      preferredCameraDevice: SourceCameraDevice.front,
    ),
    width: 512,
    height: 512,
    ovalCropMask: true,
    encoding: ImageEncodingJpg(quality: 75),
  ),
);

/// No crop page: centered 16/9 crop of the picked image.
Future<ImageData?> pickBanner(BuildContext context) => pickCropImage(
  context,
  options: PickCropImageOptions(
    source: const PickCropImageSourceGallery(),
    width: 1920,
    height: 1080,
    autoCrop: true,
    encoding: ImageEncodingJpg(quality: 85),
  ),
);
```

Crop an asset or bytes you already have, then export the result:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';

/// Straight to the crop page, no picker.
Future<void> cropAssetAndSave(BuildContext context) async {
  var data = await pickCropImage(
    context,
    options: PickCropImageOptions(
      source: ImageSourceAsset(name: 'assets/img/example.jpg'),
      width: 800,
      height: 600,
      encoding: const ImageEncodingPng(),
    ),
  );
  if (data == null) {
    return;
  }
  // Browser download on the web, save dialog on io.
  await saveImageFile(
    bytes: data.bytes,
    mimeType: data.encoding.mimeType,
    filename: 'image${data.encoding.extension}',
  );
}

/// Same thing with bytes already in memory (a download, a database blob...).
Future<ImageData?> cropBytes(BuildContext context, Uint8List bytes) =>
    pickCropImage(
      context,
      options: PickCropImageOptions(
        source: PickCropImageSourceMemory(bytes: bytes),
        aspectRatio: 1,
      ),
    );
```
