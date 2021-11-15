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
  final int? width;

  /// If null, get from the first layer
  final int? height;
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
  var width = data.width;
  var height = data.height;
  Image? image;
  late Rect<double> _fullImageDestination;
  void _initImage() {
    image = Image(width!, height!);

    _fullImageDestination =
        Rect<double>.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    if (debugComposeImage) {
      print('/compose $_fullImageDestination');
    }
  }

  if (width != null && height != null) {
    _initImage();
  }
  for (var layer in data.layers) {
    var layerImage = decodeImage(await layer.getSourceBytes())!;
    var src = layer.sourceCropRect;
    var ratio = src?.size.ratio ?? (layerImage.width / layerImage.height);
    if (image == null) {
      if (width != null) {
        height = (width / ratio).round();
      } else if (height != null) {
        width = (height * ratio).round();
      } else {
        width = src?.width.round() ?? layerImage.width;
        height = src?.height.round() ?? layerImage.height;
      }
      _initImage();
    }

    var dst = layer.destination ?? _fullImageDestination;
    if (debugComposeImage) {
      print('/compose (${layerImage.width}x${layerImage.width}) $src -> $dst');
    }
    drawImage(
      image!,
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

  if (image == null) {
    throw ArgumentError(
        'Missing some parameters layer or size to find the best image size');
  } else {
    var encoding = data.encoding;
    late Uint8List imageBytes;
    if (encoding is ImageEncodingJpg) {
      imageBytes = asUint8List(encodeJpg(image!, quality: encoding.quality));
    } else {
      imageBytes = asUint8List(encodePng(image!));
    }
    return ImageData(
        bytes: imageBytes, encoding: encoding, width: width!, height: height!);
  }
}
