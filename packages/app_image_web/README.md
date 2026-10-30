Image manipulation on the web

## Features

Image resizing, cropping and encoding

## Getting started

In pubspec.yaml

```yaml
dependencies:
  tekartik_app_image_web:
    git:
      url: https://github.com/tekartik/app_image.dart
      path: packages/app_image_web
    version: '>=0.1.0'
...

## Usage

```dart
  import 'package:tekartik_app_image/app_image.dart';
```

## WebP

The browser encodes webp (`ImageEncodingWebp`). When it cannot (Safari),
the pure Dart encoder of tekartik_app_image_webp does, on the main thread,
loaded on demand (a deferred library, not in `main.dart.js`).

`appImageWebpEncoder` (in `app_image_web.dart`) replaces the browser: set it
to the web worker of tekartik_app_image_webp_web_worker when the browser
cannot encode webp (off the main thread, `webp_worker.js` loaded on demand),
or to `encodeWebp` itself (in `main.dart.js`). See the two mains of
`example/app_pick_crop_image_demo`.
