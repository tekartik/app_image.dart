import 'dart:html' as html;
import 'dart:typed_data';

import 'package:js/js_util.dart' as js_util;
import 'package:tekartik_app_image_web/src/import.dart';

/// Convert a blog a list of bytes
Future<Uint8List> blobToBytesUsingFileReader(html.Blob value) async {
  var completer = Completer<ByteBuffer>();
  final fileReader = html.FileReader();
  fileReader.onLoad.listen((event) {
    completer.complete(js_util.getProperty(
            js_util.getProperty(event, 'target') as Object, 'result')
        as ByteBuffer);
  });
  fileReader.readAsArrayBuffer(value);

  var byteBuffer = await completer.future;
  return Uint8List.view(byteBuffer);
}

Future<Uint8List> blobToBytes(html.Blob value) async {
  try {
    return await blobToBytesUsingArrayBuffer(value);
  } catch (_) {
    return blobToBytesUsingFileReader(value);
  }
}

/// Convert a blog a list of bytes
Future<Uint8List> blobToBytesUsingArrayBuffer(html.Blob value) async {
  var completer = Completer<ByteBuffer>();
  final fileReader = html.FileReader();
  fileReader.onLoad.listen((event) {
    completer.complete(js_util.getProperty(
            js_util.getProperty(event, 'target') as Object, 'result')
        as ByteBuffer);
  });
  fileReader.readAsArrayBuffer(value);

  var byteBuffer = await completer.future;
  return Uint8List.view(byteBuffer);
}
