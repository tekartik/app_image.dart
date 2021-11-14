import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/image_decoder.dart';
import 'package:test/test.dart';

import 'white_1x1_jpg.dart' as jpg;
import 'white_1x1_png.dart' as png;

void main() {
  group('decoding', () {
    test('jpg', () async {
      var bytes = jpg.bytes;
      var meta = await getImageMetaFromBytes(bytes);
      expect(meta.encoding, const TypeMatcher<ImageEncodingJpg>());
      expect(meta.width, 1);
      expect(meta.height, 1);
    });
    test('file isPng/isJpg', () async {
      var bytes = png.bytes;
      var meta = await getImageMetaFromBytes(bytes);
      expect(meta.encoding, const TypeMatcher<ImageEncodingPng>());
      expect(meta.width, 1);
      expect(meta.height, 1);
    });
  });
}
