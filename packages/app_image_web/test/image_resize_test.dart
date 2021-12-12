import 'package:tekartik_app_image/app_image_resize.dart';
import 'package:tekartik_app_image_web/src/resize.dart';
import 'package:test/test.dart';

import 'white_1x1_jpg.dart' as jpg;

void main() {
  group('resize', () {
    test('noHeight', () async {
      var bytes = jpg.bytes;
      var result = await resizeTo(bytes,
          options: ResizeOptions(width: 48, height: null));
      expect(result.width, 48);
      expect(result.height, 48);
    });

    test('noWidth', () async {
      var bytes = jpg.bytes;
      var result = await resizeTo(bytes,
          options: ResizeOptions(width: null, height: 48));
      expect(result.width, 48);
      expect(result.height, 48);
    });

    test('noSize', () async {
      var bytes = jpg.bytes;
      var result = await resizeTo(bytes,
          options: ResizeOptions(width: null, height: null));
      expect(result.width, 1);
      expect(result.height, 1);
    });
    test('cropRect', () async {
      var bytes = jpg.bytes;
      var result = await resizeTo(bytes,
          options: ResizeOptions(
              width: 500,
              height: null,
              cropRect: CropRect.fromLTWH(0, 0, .5, .2)));
      expect(result.width, 500);
      expect(result.height, 200);
    });
  });
}
