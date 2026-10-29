import 'package:tekartik_app_image_webp_web_worker/setup.dart';

/// Builds web/webp_worker.js, the webp encoder of Safari (run_ci runs this
/// before the tests and the build).
Future<void> main() => setupWebpWorker();
