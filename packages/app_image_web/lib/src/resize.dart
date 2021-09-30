// ignore_for_file: avoid_web_libraries_in_flutter, unsafe_html

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:tekartik_app_http/app_http.dart';
import 'package:tekartik_app_image/app_image.dart';

import 'import.dart';

/// Crop rectangle
class CropRect {
  final num top;
  final num left;
  final num width;
  final num height;

  CropRect.fromTLWH(this.top, this.left, this.width, this.height);
}

/// Resize options.
class ResizeOptions {
  final int? width;
  final int? height;
  final CropRect? cropRect;
  final ImageEncoding encoding;

  ResizeOptions(
      {required this.width,
      required this.height,
      this.cropRect,
      this.encoding = const ImageEncodingPng()});
}

Future<html.CanvasElement> _loadImage(String url) {
  var result = Completer<html.CanvasElement>();
  var image = html.ImageElement();
  image.onLoad.listen((_) {
    devPrint('onLoad');
    var canvas = html.CanvasElement(
      width: image.naturalWidth,
      height: image.naturalHeight,
    );
    canvas.context2D.drawImage(image, 0, 0);
    result.complete(canvas);
  });
  image.onError.listen((Object event) {
    devPrint('onError $event');
    result.completeError(event);
  });
  image.src = url;
  return result.future;
}

Future<Uint8List> resizeTo(
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
  return await httpClientReadBytes(client, httpMethodGet, Uri.parse(url));
}
