import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/src/blob_utils.dart';
import 'package:tekartik_app_image_web/src/image_composer/image_composer.dart';
import 'package:tekartik_app_image_web/src/import.dart';
import 'package:tekartik_app_image_web/src/offscreen_canvas/src/offscreen_canvas.dart';
import 'package:tekartik_common_utils/size/size.dart';

var debugComposeImage = false; // devWarning(true);
Future<ImageData> composeImage(ImageComposerData data) async {
  var canvas = OffscreenCanvas(data.width, data.height);
  var encoding = data.encoding;

  var _fullImageDestination = Rect<double>.fromLTWH(
      0, 0, data.width.toDouble(), data.height.toDouble());
  for (var layer in data.layers) {
    var layerCanvas =
        await OffscreenCanvas.fromBytes(await layer.getSourceBytes());
    var src = layer.sourceCropRect;
    var dst = layer.destination ?? _fullImageDestination;
    if (debugComposeImage) {
      print(
          '/web_compose (${layerCanvas.width}x${layerCanvas.width}) $src -> $dst');
    }
    canvas.drawImageToRect(layerCanvas, dst, sourceRect: src);
  }
  var blob = await canvas.toBlob(data.encoding);
  var bytes = await blobToBytes(blob);
  return ImageData(
      bytes: bytes, encoding: encoding, width: data.width, height: data.height);

  /*
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

   */
}
