Helper for picking and cropping an image (Desktop, Mobile and Web support)

## Features

Pick and crop image on Flutter

## Getting started

In pubspec.yaml

```yaml
dependencies:
  tekartik_app_pick_crop_image_flutter:
    git:
      url: git://github.com/tekartik/app_image.dart
      path: packages/app_pick_crop_image_flutter
      ref: null_safety
    version: '>=0.1.0'
```

## Example

See [Demo app](../../example/app_pick_crop_image_demo)
## Usage

Needed import

```dart
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';
```

Simplest exemple that will pick an image from the gallery, allow free cropping and export as jpg

The result is available in the imageData returned
* bytes
* width
* height
* encoding

```dart
var imageData = pickCropImage(context);
```


Example to pick from the camera and crop it manually as a square

```dart
var imageData = await pickCropImage(context,
  options: PickCropImageOptions(
    source: const PickCropImageSourceCamera(
    preferredCameraDevice: SourceCameraDevice.rear),
    width: 1024,
    height: 1024,
    encoding: ImageEncodingJpg(quality: 75)));
```

Example to pick from the gallery with a round mask
The resulting image is still a square though.

```dart
var imageData = await pickCropImage(context,
  options: PickCropImageOptions(
    source: const PickCropImageSourceGallery(),
    width: 1024,
    height: 1024,
    ovalCropMask: true,
    encoding: ImageEncodingJpg(quality: 75)));
```
