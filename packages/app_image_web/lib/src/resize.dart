// ignore_for_file: avoid_web_libraries_in_flutter, unsafe_html

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:tekartik_app_http/app_http.dart';
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/app_image_resize.dart';

import 'import.dart';

var debugResizeWeb = false;

Future<html.CanvasElement> _loadImage(String url) {
  var result = Completer<html.CanvasElement>();
  var image = html.ImageElement();
  image.onLoad.listen((_) {
    var canvas = html.CanvasElement(
      width: image.naturalWidth,
      height: image.naturalHeight,
    );
    canvas.context2D.drawImage(image, 0, 0);
    result.complete(canvas);
  });
  image.onError.listen((Object event) {
    result.completeError(event);
  });
  image.src = url;
  return result.future;
}

Future<ImageData> resizeTo(
  Uint8List bytes, {
  required ResizeOptions options,
}) async {
  var srcBlob = html.Blob([bytes]);

  var srcUrl = html.Url.createObjectUrl(srcBlob);
  final srcCanvas = await _loadImage(srcUrl);

  var dstWidth = options.width ?? options.cropRect!.width.round();
  var dstHeight = options.height ?? options.cropRect!.height.round();
  final canvasDest = html.CanvasElement(width: dstWidth, height: dstHeight);
  var dst = html.Rectangle(0, 0, dstWidth, dstHeight);
  var src = html.Rectangle(
      options.cropRect?.left.round() ?? 0,
      options.cropRect?.top.round() ?? 0,
      options.cropRect?.width.round() ?? canvasDest.width!,
      options.cropRect?.height.round() ?? canvasDest.height!);
  if (debugResizeWeb) {
    print('$src to $dst');
  }
  canvasDest.context2D.drawImageToRect(srcCanvas, dst, sourceRect: src);

  late html.Blob blob;
  var encoding = options.encoding;
  if (encoding is ImageEncodingJpg) {
    // Quality is from 0 to 100 but we want from 0 to 1
    blob = await canvasDest.toBlob(encoding.mimeType, encoding.quality / 100);
  } else {
    blob = await canvasDest.toBlob(encoding.mimeType);
  }
  var url = html.Url.createObjectUrl(blob);
  var client = httpClientFactory.newClient();
  var readBytes =
      await httpClientReadBytes(client, httpMethodGet, Uri.parse(url));
  return ImageData(
      bytes: readBytes, width: dstWidth, height: dstHeight, encoding: encoding);
}
