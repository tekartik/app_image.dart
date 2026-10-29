import 'package:tekartik_app_image_webp_web_worker/setup.dart';

/// Builds web/webp_worker.js: `dart run tekartik_app_image_webp_web_worker:setup`.
Future<void> main(List<String> arguments) =>
    webpWorkerScript.setupMain(arguments);
