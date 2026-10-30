import 'package:flutter/foundation.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:tekartik_app_image_webp_web_worker/webp_worker.dart';
import 'package:tekartik_pick_crop_image_demo/app.dart';
import 'package:tekartik_pick_crop_image_demo/src/webp_support.dart';

/// True when the platform encodes webp itself: the browser (Chrome, Firefox),
/// or io (the pure Dart encoder in an isolate). False in Safari.
bool isWebpEncodingSupported() => platformWebpEncodingSupported();

/// The demo, webp encoded by the browser (tekartik_app_image_web) when it
/// can, else by the web worker (web/webp_worker.js, loaded on the first
/// encoding): the encoder is not in main.dart.js.
///
/// See main_webp_direct.dart for the pure Dart encoder on the main thread.
Future<void> main() async {
  String webpEncoder;
  if (isWebpEncodingSupported()) {
    webpEncoder = kIsWeb ? 'browser' : 'pure Dart (isolate)';
  } else {
    appImageWebpEncoder = (image, options) =>
        webpWorker.encode(image, options: options, transfer: true);
    webpEncoder = 'web worker ($webpWorkerJsFilename)';
  }
  await runPickCropDemo(webpEncoder: webpEncoder);
}
