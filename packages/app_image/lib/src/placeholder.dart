import 'package:image/image.dart' as img;
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/src/encoder.dart';

const _defaultWidth = 256;
const _defaultHeight = 256;
var _defaultEncoding = ImageEncodingJpg(quality: 50);

/// Create a color from a 32-bit unsigned integer
img.Color colorFromUint32(int color) {
  final a = (color >> 24) & 0xFF;
  final r = (color >> 16) & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = color & 0xFF;

  return img.ColorRgba8(r, g, b, a);
}

/// Default to a 256x256 image
Future<ImageData> generatePlaceholderImage({
  ImageEncoding? encoding,
  int? width,
  int? height,
  int? color,
}) async {
  width ??= _defaultWidth;
  height ??= _defaultHeight;
  encoding ??= _defaultEncoding;
  var image = img.Image(
    width: width,
    height: height,
  ); // , backgroundColor: img.ConstColorRg8.Color(0xFFFFFFFF));
  if (color != null) {
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: width,
      y2: height,
      color: colorFromUint32(color),
    );
  }
  var data = await imageEncode(image, encoding: encoding);
  return data;
}
