import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/image_decoder/image_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('decoding', () {
    test('jpg', () async {
      var bytes = await File(join('data', 'white_1x1.jpg')).readAsBytes();
      var meta = await getImageMetaFromBytes(bytes);
      expect(meta.encoding, const TypeMatcher<ImageEncodingJpg>());
      expect(meta.width, 1);
      expect(meta.height, 1);
    });
    test('file isPng/isJpg', () async {
      var bytes = await File(join('data', 'white_1x1.png')).readAsBytes();
      var meta = await getImageMetaFromBytes(bytes);
      expect(meta.encoding, const TypeMatcher<ImageEncodingPng>());
      expect(meta.width, 1);
      expect(meta.height, 1);
    });
    test('getImageEncodingFromBytes webp', () async {
      var bytes = await File(join('data', 'white_1x1.webp')).readAsBytes();
      var encoding = getImageEncodingFromBytes(bytes);

      expect(encoding, isA<ImageEncodingWebp>());
      expect(encoding.mimeType, 'image/webp');
      expect(encoding.extension, '.webp');
    });
  });
}
