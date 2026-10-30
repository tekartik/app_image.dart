import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';
// The encoder of the fallback, loaded on demand: not in main.dart.js.
import 'package:tekartik_app_image_webp/webp.dart' deferred as webp_codec;
import 'package:web/web.dart' as web;

import 'js_message.dart';
import 'protocol.dart';
import 'webp_worker.dart';

/// The web worker: the script at [url], started on the first encoding.
WebpWorker newWebpWorker({
  required String url,
  required bool fallback,
  required Duration startTimeout,
}) => _WebpWorkerWeb(url, fallback, startTimeout);

const _setupCommand = 'dart run tekartik_app_image_webp_web_worker:setup';

class _WebpWorkerWeb implements WebpWorker {
  _WebpWorkerWeb(this.url, this.fallback, this.startTimeout);

  final String url;
  final bool fallback;
  final Duration startTimeout;

  web.Worker? _worker;
  Future<bool>? _ready;

  /// Completed by the ready message (or an error before it).
  Completer<bool>? _started;
  var _lastId = 0;
  final _pending = <int, Completer<Uint8List>>{};
  var _closed = false;

  @override
  Future<bool> get ready =>
      _closed ? Future.value(false) : (_ready ??= _start());

  Future<bool> _start() async {
    var started = _started = Completer<bool>();
    try {
      var worker = _worker = web.Worker(url.toJS);
      worker.onmessage = _onMessage.toJS;
      worker.onerror = _onError.toJS;
    } catch (e) {
      // A url the page refuses (content security policy).
      _warn('cannot start $url ($e)');
      return false;
    }
    var ok = await started.future.timeout(
      startTimeout,
      onTimeout: () {
        _warn('$url did not start within $startTimeout');
        return false;
      },
    );
    if (!ok) {
      _terminate();
    }
    return ok;
  }

  void _onMessage(web.MessageEvent event) {
    var message = event.data as WebpWorkerJsMessage?;
    switch (message?.type) {
      case webpWorkerMessageReady:
        var version = message!.version;
        if (version == webpWorkerProtocolVersion) {
          _started?.complete(true);
        } else {
          _warn(
            '$url speaks version $version, not $webpWorkerProtocolVersion: '
            'build it again ($_setupCommand)',
          );
          _started?.complete(false);
        }
      case webpWorkerMessageResult:
        _pending.remove(message!.id)?.complete(message.webp!.toDart);
      case webpWorkerMessageError:
        _pending
            .remove(message!.id)
            ?.completeError(WebpWorkerException(message.error ?? 'error'));
    }
  }

  void _onError(web.Event event) {
    var started = _started;
    if (started != null && !started.isCompleted) {
      // Missing (404), not a script (an html page served instead)...
      _warn('cannot load $url ($_setupCommand builds it)');
      started.complete(false);
      return;
    }
    // Out of an encoding (they catch their errors): the worker may be gone,
    // the pending encodings fail, the next one starts it again.
    var error = WebpWorkerException(
      event.isA<web.ErrorEvent>()
          ? (event as web.ErrorEvent).message
          : 'worker error',
    );
    _failPending(error);
    _terminate();
    _ready = null;
  }

  void _terminate() {
    _worker?.terminate();
    _worker = null;
  }

  void _failPending(Object error) {
    var pending = _pending.values.toList();
    _pending.clear();
    for (var completer in pending) {
      completer.completeError(error);
    }
  }

  void _warn(String message) {
    web.console.warn('WebpWorker: $message, encoding on the main thread'.toJS);
  }

  @override
  Future<Uint8List> encode(
    WebpImage image, {
    WebpEncodeOptions options = const WebpEncodeOptions(),
    bool transfer = false,
  }) async {
    if (_closed) {
      throw StateError('WebpWorker closed');
    }
    var worker = await ready ? _worker : null;
    if (worker == null) {
      if (_closed) {
        throw StateError('WebpWorker closed');
      }
      if (!fallback) {
        throw StateError('$url not started ($_setupCommand builds it)');
      }
      await webp_codec.loadLibrary();
      return webp_codec.encodeWebp(image, options: options);
    }
    var completer = Completer<Uint8List>();
    var id = ++_lastId;
    _pending[id] = completer;
    var rgba = jsTransferableBytes(image.rgba, transfer: transfer);
    worker.postMessage(
      WebpWorkerJsMessage(
        type: webpWorkerMessageEncode,
        id: id,
        width: image.width,
        height: image.height,
        rgba: rgba,
        options: webpEncodeOptionsToMap(options).jsify(),
      ),
      [rgba.buffer].toJS,
    );
    return completer.future;
  }

  @override
  Future<void> close() async {
    _closed = true;
    var started = _started;
    if (started != null && !started.isCompleted) {
      started.complete(false);
    }
    _terminate();
    _failPending(StateError('WebpWorker closed'));
  }
}
