import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';

import 'protocol.dart';
import 'webp_worker_io.dart'
    if (dart.library.js_interop) 'webp_worker_web.dart'
    as platform;

/// Encodes webp off the main thread: in a web worker on the web (the script
/// built by the setup step, `webp_worker.js` next to the page), in an
/// isolate on io.
abstract class WebpWorker {
  /// A worker loading [url] (relative to the page) when it first encodes.
  ///
  /// When the script cannot start (missing, not answering within
  /// [startTimeout], built for another protocol version), the images are
  /// encoded on the main thread (the encoder loaded on demand, a deferred
  /// library), unless [fallback] is false: [encode] throws a [StateError]
  /// then. [url], [fallback] and [startTimeout] are ignored on
  /// io.
  factory WebpWorker({
    String url = webpWorkerJsFilename,
    bool fallback = true,
    Duration startTimeout = const Duration(seconds: 30),
  }) => platform.newWebpWorker(
    url: url,
    fallback: fallback,
    startTimeout: startTimeout,
  );

  /// Encodes [image] with [options].
  ///
  /// [transfer] moves the pixels to the worker instead of copying them, for
  /// pixels used once (`getImageData`): `image.rgba` can be emptied then.
  ///
  /// Encodings run one after the other in the worker. An encoder error is a
  /// [WebpWorkerException] on the web.
  Future<Uint8List> encode(
    WebpImage image, {
    WebpEncodeOptions options = const WebpEncodeOptions(),
    bool transfer = false,
  });

  /// True when the images are encoded off the main thread, false on the
  /// fallback. Starts the worker.
  Future<bool> get ready;

  /// Stops the worker: the pending encodings fail, the next ones throw.
  Future<void> close();
}

/// The worker loading `webp_worker.js` next to the page, falling back on the
/// main thread when missing. Can be replaced.
///
/// For tekartik_app_image_web when the browser cannot encode webp (Safari):
/// `appImageWebpEncoder = (image, options) => webpWorker.encode(image,
/// options: options, transfer: true)`.
WebpWorker webpWorker = WebpWorker();
