import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/app_image_bytes_utils.dart';
import 'package:tekartik_app_image/image_composer/image_composer.dart';
import 'package:tekartik_app_image/src/encoder.dart';
import 'package:tekartik_app_image/src/image_encode.dart';
import 'package:tekartik_app_image_webp/image_web.dart';
import 'package:tekartik_common_utils/size/size.dart';
import 'package:test/test.dart';

void main() {
  img.Image redImage() =>
      img.Image(width: 6, height: 4)..clear(img.ColorRgb8(255, 0, 0));
  img.Image noiseImage() {
    var image = img.Image(width: 32, height: 32);
    for (final p in image) {
      p.setRgb((p.x * 37) % 256, (p.y * 91) % 256, (p.x * p.y * 13) % 256);
    }
    return image;
  }

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
    test('imageEncode webp quality', () async {
      Future<int> size(int quality) async => (await imageEncode(
        noiseImage(),
        encoding: ImageEncodingWebp(quality: quality),
      )).bytes.length;
      expect(await size(10), lessThan(await size(95)));
      // Unknown (decoded) quality encodes with the default one.
      expect(
        await size(imageEncodingWebpQualityUnknown),
        await size(imageEncodingWebpQualityDefault),
      );
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
    test('composeImage webp source cropped', () async {
      // A webp source (decoded by the webp decoder) cropped to a square, as
      // a thumbnail cropped from a webp cover.
      var source = ImageSource.bytes(
        encodeImageWebp(
          noiseImage(),
          options: const WebpEncodeOptions(quality: 90),
        ),
      );
      var data = await composeImage(
        ImageComposerData(
          layers: [
            ImageLayerData(
              source: source,
              sourceCropRect: Rect<double>.fromLTWH(8, 4, 16, 16),
            ),
          ],
          width: 8,
          height: 8,
          encoding: const ImageEncodingPng(),
        ),
      );
      expect(isPng(data.bytes), isTrue);
      expect([data.width, data.height], [8, 8]);
    });
    test('imageDecodeBytes', () {
      var webp = encodeImageWebp(redImage());
      expect(imageDecodeBytes(webp).width, 6);
      var png = Uint8List.fromList(img.encodePng(redImage()));
      expect(imageDecodeBytes(png).height, 4);
      expect(
        () => imageDecodeBytes(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });
}
