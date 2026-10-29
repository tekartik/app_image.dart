import 'package:tekartik_app_image_webp_web_worker/setup.dart';

/// Builds test/webp_worker.js, the worker of the browser tests (run_ci runs
/// this before the tests).
Future<void> main() => setupWebpWorker(dir: 'test');
