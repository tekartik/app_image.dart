/// WebP encoding off the main thread: the pure Dart encoder of
/// tekartik_app_image_webp in a web worker (`webp_worker.js`, built by the
/// setup step), in an isolate on io.
///
/// ```dart
/// import 'package:tekartik_app_image_webp_web_worker/webp_worker.dart';
///
/// var bytes = await webpWorker.encode(image, options: WebpEncodeOptions(quality: 80));
/// ```
library;

export 'src/protocol.dart'
    show
        webpWorkerJsFilename,
        webpWorkerProtocolVersion,
        webpEncodeOptionsToMap,
        webpEncodeOptionsFromMap,
        WebpWorkerException;
export 'src/webp_worker.dart' show WebpWorker, webpWorker;
