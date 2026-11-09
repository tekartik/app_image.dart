import 'package:image/image.dart' as img;
import 'package:tekartik_app_image/app_color.dart';
import 'package:tekartik_app_image/app_image_placeholder.dart';
import 'package:test/test.dart';

void main() {
  group('placeholder color', () {
    Future<List<num>> firstPixelRgba(int color) async {
      var data = await generatePlaceholderImage(
        encoding: const ImageEncodingPng(),
        width: 2,
        height: 2,
        color: color,
      );
      var pixel = img.decodePng(data.bytes)!.getPixel(0, 0);
      return [pixel.r, pixel.g, pixel.b, pixel.a];
    }

    test('argbToColorUint32 red', () async {
      // What example/placeholder.dart does: an opaque red placeholder.
      expect(await firstPixelRgba(argbToColorUint32(255, 255, 0, 0)), [
        255,
        0,
        0,
        255,
      ]);
    });

    test('argbToColorUint32 blue', () async {
      expect(await firstPixelRgba(argbToColorUint32(255, 0, 0, 255)), [
        0,
        0,
        255,
        255,
      ]);
    });

    test('literal 0xAARRGGBB', () async {
      expect(await firstPixelRgba(0xFFFF0000), [255, 0, 0, 255]);
    });

    test('argbToColorUint32 value', () {
      expect(argbToColorUint32(0xFF, 0x11, 0x22, 0x33), 0xFF112233);
      expect(argbToColorUint32(0x80, 0, 0, 0), 0x80000000);
    });
  });
}
