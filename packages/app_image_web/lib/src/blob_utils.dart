import 'dart:js_interop';
import 'dart:typed_data';

import 'package:tekartik_app_image_web/src/import.dart';
import 'package:web/web.dart' as web;

/// Convert a blog a list of bytes
Future<Uint8List> blobToBytesUsingFileReader(web.Blob value) async {
  var completer = Completer<ByteBuffer>();
  final fileReader = web.FileReader();
  web.EventStreamProviders.loadEvent
      .forTarget(fileReader)
      .listen((web.Event event) {
    var result = fileReader.result as JSArrayBuffer;
    completer.complete(result.toDart);
  });
  fileReader.readAsArrayBuffer(value);

  var byteBuffer = await completer.future;
  return Uint8List.view(byteBuffer);
}

Future<Uint8List> blobToBytes(web.Blob value) async {
  try {
    return await blobToBytesUsingArrayBuffer(value);
  } catch (_) {
    return blobToBytesUsingFileReader(value);
  }
}

/// Convert a blog a list of bytes
Future<Uint8List> blobToBytesUsingArrayBuffer(web.Blob value) async {
  return Uint8List.view((await value.arrayBuffer().toDart).toDart);
}
