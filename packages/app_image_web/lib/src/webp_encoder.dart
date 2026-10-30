import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';

/// Encodes canvas pixels as webp, instead of the browser.
typedef AppImageWebpEncoder =
    Future<Uint8List> Function(WebpImage image, WebpEncodeOptions options);

/// The webp encoder of the web image composer (`OffscreenCanvas.toBlob`):
/// when set, webp is always encoded with it instead of the browser.
///
/// Null by default: the browser encodes webp, and when it cannot (Safari),
/// the pure Dart encoder of tekartik_app_image_webp does, on the main
/// thread, loaded on demand (a deferred library, not in `main.dart.js`).
///
/// Set it to [WebpWorker.encode] of tekartik_app_image_webp_web_worker when
/// the browser cannot encode webp (the encoder in `webp_worker.js`, loaded
/// on demand off the main thread), or to `encodeWebp` itself (in
/// `main.dart.js`).
AppImageWebpEncoder? appImageWebpEncoder;
