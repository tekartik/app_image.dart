import 'package:flutter/foundation.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:tekartik_app_image_webp/webp.dart';
import 'package:tekartik_pick_crop_image_demo/app.dart';

/// The demo, webp always encoded by the pure Dart encoder on the main thread,
/// even where the browser can: the encoder is in main.dart.js.
///
/// `flutter run -d chrome -t lib/main_webp_direct.dart`
Future<void> main() async {
  appImageWebpEncoder = (image, options) async =>
      encodeWebp(image, options: options);
  await runPickCropDemo(
    webpEncoder: kIsWeb ? 'pure Dart (main thread)' : 'pure Dart (isolate)',
  );
}
