import 'package:tekartik_app_image/app_image.dart';
import 'package:test/test.dart';

void main() {
  group('encoding', () {
    test('png', () {
      expect(const ImageEncodingPng().mimeType, 'image/png');
      expect(const ImageEncodingPng().extension, '.png');
    });
    test('jpg', () {
      expect(ImageEncodingJpg(quality: 75).mimeType, 'image/jpeg');
      expect(ImageEncodingJpg(quality: 75).extension, '.jpg');
      expect(ImageEncodingJpg(quality: 75).quality, 75);
    });
    test('webp', () {
      expect(const ImageEncodingWebp().mimeType, 'image/webp');
      expect(const ImageEncodingWebp().extension, '.webp');
      expect(const ImageEncodingWebp().quality, 75);
      expect(const ImageEncodingWebp(quality: 90).quality, 90);
      expect(const ImageEncodingWebp(quality: 90).toString(), 'Webp(90)');
    });
  });
}
