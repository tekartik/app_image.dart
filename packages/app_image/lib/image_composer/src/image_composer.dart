import 'dart:typed_data';

import 'package:image/image.dart';
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_common_utils/byte_utils.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/size/size.dart';

var debugComposeImage = false; //devWarning(true);

class ImageComposerData {
  final List<ImageLayerData> layers;

  /// If null, get from the first layer
  final int width;

  /// If null, get from the first layer
  final int height;
  final ImageEncoding encoding;

  ImageComposerData(
      {required this.layers,
      required this.width,
      required this.height,
      required this.encoding});
}

class ImageLayerData {
  final ImageSource source;
  final Rect<double>? sourceCropRect;
  final Rect<double>? destination;
  Future<Uint8List> getSourceBytes() =>
      (source as ImageSourceAsyncData).getBytes();

  ImageLayerData(
      {required this.source, this.sourceCropRect, this.destination}) {
    assert(source is ImageSourceAsyncData); // Only supported type
  }
}

Future<ImageData> composeImage(ImageComposerData data) async {
  var image = Image(data.width, data.height);
  var _fullImageDestination = Rect<double>.fromLTWH(
      0, 0, data.width.toDouble(), data.height.toDouble());
  if (debugComposeImage) {
    print('/compose $_fullImageDestination');
  }
  for (var layer in data.layers) {
    var layerImage = decodeImage(await layer.getSourceBytes())!;
    var src = layer.sourceCropRect;
    var dst = layer.destination ?? _fullImageDestination;
    if (debugComposeImage) {
      print('/compose (${layerImage.width}x${layerImage.width}) $src -> $dst');
    }
    drawImage(
      image,
      layerImage,
      srcX: src?.left.toInt(),
      srcY: src?.top.toInt(),
      srcW: src?.width.toInt(),
      srcH: src?.height.toInt(),
      dstX: dst.left.toInt(),
      dstY: dst.top.toInt(),
      dstW: dst.width.toInt(),
      dstH: dst.height.toInt(),
    );
  }

  var encoding = data.encoding;
  late Uint8List imageBytes;
  if (encoding is ImageEncodingJpg) {
    imageBytes = asUint8List(encodeJpg(image, quality: encoding.quality));
  } else {
    imageBytes = asUint8List(encodePng(image));
  }
  return ImageData(
      bytes: imageBytes,
      encoding: encoding,
      width: data.width,
      height: data.height);
}
