import 'dart:isolate';
import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';

import 'webp_worker.dart';

/// The io worker: an isolate per encoding.
WebpWorker newWebpWorker({
  required String url,
  required bool fallback,
  required Duration startTimeout,
}) => _WebpWorkerIo();

Uint8List _encode(WebpImage image, WebpEncodeOptions options) =>
    encodeWebp(image, options: options);

class _WebpWorkerIo implements WebpWorker {
  var _closed = false;

  @override
  Future<Uint8List> encode(
    WebpImage image, {
    WebpEncodeOptions options = const WebpEncodeOptions(),
    bool transfer = false,
  }) async {
    if (_closed) {
      throw StateError('WebpWorker closed');
    }
    return Isolate.run(() => _encode(image, options), debugName: 'webp encode');
  }

  @override
  Future<bool> get ready async => !_closed;

  @override
  Future<void> close() async {
    _closed = true;
  }
}
