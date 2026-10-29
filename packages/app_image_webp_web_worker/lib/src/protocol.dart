/// The messages between the page and the webp worker, pure Dart.
library;

import 'package:tekartik_app_image_webp/webp.dart';

/// The version of the messages: a worker script built for another version
/// (an older `web/webp_worker.js`) is not used.
const webpWorkerProtocolVersion = 1;

/// The default file name of the worker script, next to the page.
const webpWorkerJsFilename = 'webp_worker.js';

/// Message type, worker to page, once started (with its `version`).
const webpWorkerMessageReady = 'ready';

/// Message type, page to worker: encode `rgba` (`width` x `height`) with
/// `options`, answered with the same `id`.
const webpWorkerMessageEncode = 'encode';

/// Message type, worker to page: the `webp` bytes of the request `id`.
const webpWorkerMessageResult = 'result';

/// Message type, worker to page: the request `id` failed with `error`.
const webpWorkerMessageError = 'error';

/// [options] as a map of strings, numbers and booleans.
Map<String, Object> webpEncodeOptionsToMap(WebpEncodeOptions options) => {
  'lossless': options.lossless,
  'quality': options.quality,
  'method': options.method,
  'alphaQuality': options.alphaQuality,
  'alphaCompression': options.alphaCompression,
  'alphaFiltering': options.alphaFiltering.name,
  'exact': options.exact,
  'snsStrength': options.snsStrength,
  'filterStrength': options.filterStrength,
  'filterSharpness': options.filterSharpness,
  'filterType': options.filterType,
  'segments': options.segments,
  'pass': options.pass,
};

/// The options of [map] ([webpEncodeOptionsToMap]), the defaults for the
/// missing ones. Numbers can come as doubles (from JavaScript).
WebpEncodeOptions webpEncodeOptionsFromMap(Map map) {
  const defaults = WebpEncodeOptions();
  int integer(String key, int defaultValue) =>
      (map[key] as num?)?.toInt() ?? defaultValue;
  return WebpEncodeOptions(
    lossless: map['lossless'] as bool? ?? defaults.lossless,
    quality: (map['quality'] as num?)?.toDouble() ?? defaults.quality,
    method: integer('method', defaults.method),
    alphaQuality: integer('alphaQuality', defaults.alphaQuality),
    alphaCompression: integer('alphaCompression', defaults.alphaCompression),
    alphaFiltering:
        AlphaFiltering.values.asNameMap()[map['alphaFiltering']] ??
        defaults.alphaFiltering,
    exact: map['exact'] as bool? ?? defaults.exact,
    snsStrength: integer('snsStrength', defaults.snsStrength),
    filterStrength: integer('filterStrength', defaults.filterStrength),
    filterSharpness: integer('filterSharpness', defaults.filterSharpness),
    filterType: integer('filterType', defaults.filterType),
    segments: integer('segments', defaults.segments),
    pass: integer('pass', defaults.pass),
  );
}

/// An encoding that failed in the worker.
class WebpWorkerException implements Exception {
  /// The error, as the worker told it.
  final String message;

  /// An encoding that failed in the worker.
  WebpWorkerException(this.message);

  @override
  String toString() => 'WebpWorkerException: $message';
}
