import 'dart:typed_data';

import 'package:image/image.dart' as impl;
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_common_utils/byte_utils.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/size/size.dart';

/// Debug only
var debugComposeImage = false; // devWarning(true);
/// Log
void log(Object? message) {
  if (debugComposeImage) {
    // ignore: avoid_print
    print(message);
  }
}

/// Compose image data
class ImageComposerData {
  /// Image layers
  final List<ImageLayerData> layers;

  /// If null, get from the first layer
  final int? width;

  /// If null, get from the first layer
  final int? height;

  /// Image encoding
  final ImageEncoding encoding;

  /// Compose image data
  ImageComposerData({
    required this.layers,
    required this.width,
    required this.height,
    required this.encoding,
  });
}

/// Image layer data
class ImageLayerData {
  /// Source image
  final ImageSource source;

  /// Source crop rect
  final Rect<double>? sourceCropRect;

  /// Destination rect
  final Rect<double>? destination;

  /// Get source bytes
  Future<Uint8List> getSourceBytes() =>
      (source as ImageSourceAsyncData).getBytes();

  /// Image layer data
  ImageLayerData({
    required this.source,
    this.sourceCropRect,
    this.destination,
  }) {
    assert(source is ImageSourceAsyncData); // Only supported type
  }
}

/// Compose image
Future<ImageData> composeImage(ImageComposerData data) async {
  var width = data.width;
  var height = data.height;
  impl.Image? image;
  late Rect<double> fullImageDestination;
  void initImage() {
    image = impl.Image(
      width: width!,
      height: height!,
      numChannels: 4, // 4 needed for transparency
      //    backgroundColor: devWarning(impl.ColorUint32.rgba(255, 0, 0, 255))
    );

    fullImageDestination = Rect<double>.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    if (debugComposeImage) {
      log('/compose $fullImageDestination');
    }
  }

  if (width != null && height != null) {
    initImage();
  }
  for (var layer in data.layers) {
    var layerImage = impl.decodeImage(await layer.getSourceBytes())!;
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
      initImage();
    }

    var dst = layer.destination ?? fullImageDestination;
    if (debugComposeImage) {
      log('/compose (${layerImage.width}x${layerImage.width}) $src -> $dst');
    }

    impl.compositeImage(
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
      //blend: impl.BlendMode.direct,
    );
  }

  if (image == null) {
    throw ArgumentError(
      'Missing some parameters layer or size to find the best image size',
    );
  } else {
    var encoding = data.encoding;
    late Uint8List imageBytes;
    if (encoding is ImageEncodingJpg) {
      imageBytes = asUint8List(
        impl.encodeJpg(image!, quality: encoding.quality),
      );
    } else {
      imageBytes = asUint8List(impl.encodePng(image!));
    }
    return ImageData(
      bytes: imageBytes,
      encoding: encoding,
      width: width!,
      height: height!,
    );
  }
}
