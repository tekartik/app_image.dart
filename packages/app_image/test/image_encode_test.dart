import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/app_image_bytes_utils.dart';
import 'package:tekartik_app_image/image_composer/image_composer.dart';
import 'package:tekartik_app_image/src/encoder.dart';
import 'package:tekartik_app_image_webp/image_web.dart';
import 'package:test/test.dart';

void main() {
  img.Image redImage() =>
      img.Image(width: 6, height: 4)..clear(img.ColorRgb8(255, 0, 0));

  group('image encode', () {
    test('imageEncode webp', () async {
      var data = await imageEncode(
        redImage(),
        encoding: const ImageEncodingWebp(),
      );
      expect(data.encoding, isA<ImageEncodingWebp>());
      expect(isWebp(data.bytes), isTrue);
      var decoded = decodeImageWebp(data.bytes)!;
      expect([decoded.width, decoded.height], [6, 4]);
    });
    test('imageEncode png/jpg', () async {
      var data = await imageEncode(
        redImage(),
        encoding: const ImageEncodingPng(),
      );
      expect(isPng(data.bytes), isTrue);
      data = await imageEncode(redImage());
      expect(isJpg(data.bytes), isTrue);
      expect((data.encoding as ImageEncodingJpg).quality, 50);
    });
    test('composeImage webp', () async {
      var source = ImageSource.bytes(
        Uint8List.fromList(img.encodePng(redImage())),
      );
      var data = await composeImage(
        ImageComposerData(
          layers: [ImageLayerData(source: source)],
          width: null,
          height: null,
          encoding: const ImageEncodingWebp(),
        ),
      );
      expect(data.encoding, isA<ImageEncodingWebp>());
      expect(String.fromCharCodes(data.bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(data.bytes.sublist(8, 12)), 'WEBP');
      expect(isPng(data.bytes), isFalse);
      var decoded = decodeImageWebp(data.bytes)!;
      expect([decoded.width, decoded.height], [6, 4]);
      expect([data.width, data.height], [6, 4]);
    });
  });
}
