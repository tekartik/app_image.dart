/// The main of the webp worker script (web only), built by the setup step
/// (`dart run tekartik_app_image_webp_web_worker:setup`).
library;

import 'dart:js_interop';

import 'package:tekartik_app_image_webp/webp.dart';
import 'package:web/web.dart' as web;

import 'js_message.dart';
import 'protocol.dart';

/// The worker script main.
void main() => webpWorkerMain();

/// Encodes the images the page sends, one after the other.
void webpWorkerMain() {
  var scope = globalContext as web.DedicatedWorkerGlobalScope;
  scope.onmessage = (web.MessageEvent event) {
    var message = event.data as WebpWorkerJsMessage?;
    if (message?.type != webpWorkerMessageEncode) {
      return;
    }
    var id = message!.id!;
    try {
      var image = WebpImage(
        message.width!,
        message.height!,
        message.rgba!.toDart,
      );
      var options = webpEncodeOptionsFromMap(
        (message.options?.dartify() as Map?) ?? const {},
      );
      // The encoder output has its own buffer: moved, not copied.
      var webp = jsTransferableBytes(
        encodeWebp(image, options: options),
        transfer: true,
      );
      scope.postMessage(
        WebpWorkerJsMessage(type: webpWorkerMessageResult, id: id, webp: webp),
        [webp.buffer].toJS,
      );
    } catch (e) {
      scope.postMessage(
        WebpWorkerJsMessage(type: webpWorkerMessageError, id: id, error: '$e'),
      );
    }
  }.toJS;
  scope.postMessage(
    WebpWorkerJsMessage(
      type: webpWorkerMessageReady,
      version: webpWorkerProtocolVersion,
    ),
  );
}
