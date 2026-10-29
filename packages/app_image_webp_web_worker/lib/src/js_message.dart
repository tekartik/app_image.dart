/// The messages between the page and the webp worker, as JS objects (web
/// only).
library;

import 'dart:js_interop';
import 'dart:typed_data';

/// A message, a plain JS object (see the types in `protocol.dart`).
extension type WebpWorkerJsMessage._(JSObject _) implements JSObject {
  /// A message with the given fields only.
  external factory WebpWorkerJsMessage({
    String type,
    int id,
    int version,
    int width,
    int height,
    JSUint8Array rgba,
    JSAny? options,
    JSUint8Array webp,
    String error,
  });

  /// The message type.
  external String? get type;

  /// The request id.
  external int? get id;

  /// The protocol version (ready).
  external int? get version;

  /// The image width (encode).
  external int? get width;

  /// The image height (encode).
  external int? get height;

  /// The RGBA pixels (encode).
  external JSUint8Array? get rgba;

  /// The options, a plain object (encode).
  external JSAny? get options;

  /// The webp bytes (result).
  external JSUint8Array? get webp;

  /// The error (error).
  external String? get error;
}

/// The `buffer` of a JS typed array, to put in the transfer list of
/// `postMessage`.
extension JSTypedArrayBuffer on JSTypedArray {
  /// The ArrayBuffer of this view.
  external JSArrayBuffer get buffer;
}

/// [bytes] in a JS array whose buffer can be moved to the other thread (in
/// the transfer list of `postMessage`) without detaching anything else:
/// [bytes] itself when [transfer] is true and it has a buffer of its own (it
/// is then detached: empty), a copy otherwise.
JSUint8Array jsTransferableBytes(Uint8List bytes, {required bool transfer}) {
  var ownBuffer =
      bytes.offsetInBytes == 0 &&
      bytes.lengthInBytes == bytes.buffer.lengthInBytes;
  return (transfer && ownBuffer ? bytes : Uint8List.fromList(bytes)).toJS;
}
