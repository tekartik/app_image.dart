/// The setup step of an app (dart:io, run from a tool): builds
/// `webp_worker.js` from Dart, next to the page.
///
/// ```dart
/// // tool/dev_build_setup.dart, run by run_ci before the tests and the build.
/// import 'package:tekartik_app_image_webp_web_worker/setup.dart';
///
/// Future<void> main() => setupWebpWorker();
/// ```
library;

export 'package:tekartik_web_worker_build/web_worker_build.dart'
    show WebWorkerScript, WebWorkerScriptSetupResult;

export 'src/protocol.dart' show webpWorkerJsFilename;
export 'src/setup.dart' show setupWebpWorker, webpWorkerScript;
