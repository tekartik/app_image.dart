# tekartik_app_pick_crop_image_flutter

Pick an image (gallery, camera, desktop file dialog, asset or bytes), let
the user crop it on a full screen editor, get it resized and encoded (png,
jpg or webp): one call, `pickCropImage(context)`.

Platforms: Android, iOS (`image_picker`), macOS, Linux, Windows (file
dialog), web (browser file input, canvas resize).

## Getting started

```yaml
dependencies:
  tekartik_app_pick_crop_image_flutter:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_pick_crop_image_flutter
  material_ui: '>=1.5.0'
```

```dart
import 'package:material_ui/material_ui.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';

/// Pick from the gallery, crop as a square, get a 1024x1024 jpeg.
Future<ImageData?> pickSquarePhoto(BuildContext context) => pickCropImage(
  context,
  options: PickCropImageOptions(
    width: 1024,
    height: 1024,
    encoding: ImageEncodingJpg(quality: 75),
    title: 'Crop the photo',
  ),
);
```

The result (null when cancelled) holds `bytes`, `width`, `height` and
`encoding` (`encoding.mimeType`, `encoding.extension`). Without options it
picks from the gallery, crops freely and encodes a png.

A complete app: [the demo](../../example/app_pick_crop_image_demo).

## Options

- `source`: `PickCropImageSourceGallery()` (default),
  `PickCropImageSourceCamera(preferredCameraDevice: SourceCameraDevice.front)`,
  `ImageSourceAsset(name: 'assets/x.jpg')`, `PickCropImageSourceMemory(bytes:)`.
- `width`, `height`: the output size (both set: the crop ratio too);
  `aspectRatio` alone constrains the crop only.
- `encoding`: `ImageEncodingPng()` (default), `ImageEncodingJpg(quality:)`,
  `ImageEncodingWebp(quality:)`.
- `ovalCropMask: true`: a round mask in the editor (the image stays a
  rectangle: clip it when shown).
- `autoCrop: true`: no editor, a centered crop.
- `title`, `hint`, `confirmLabel`: an app bar and a hint on the crop page.

`saveImageFile(bytes:, mimeType:, filename:)` saves the result (a download
on the web, a save dialog elsewhere).

## Pitfalls

- The pages use `package:material_ui`: the app does too, not
  `package:flutter/material.dart` (the two Material libraries do not mix).
- Web: call it from a user gesture; if the user cancels the browser file
  dialog, the future may never complete.
- Linux, Windows, macOS: the camera source opens the file dialog too.
- Android, iOS: the `image_picker` setup (camera and photo library usage
  descriptions in `Info.plist`).
- `autoCrop` decodes the whole picture on the UI thread to read its size.
- Check `context.mounted` after awaiting it.

More in the [package skill](skills/tekartik-app-pick-crop-image-flutter-setup/SKILL.md).
