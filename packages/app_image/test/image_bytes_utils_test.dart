import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:tekartik_app_image/app_image_bytes_utils.dart';
import 'package:test/test.dart';

void main() {
  group('image_bytes_utils', () {
    test('isPng/isJpg', () {
      var bytes = Uint8List.fromList([255, 216, 255, 224]);
      expect(isJpg(bytes), isTrue);
      expect(isPng(bytes), isFalse);
      bytes = Uint8List.fromList([137, 80, 78, 71]);
      expect(isJpg(bytes), isFalse);
      expect(isPng(bytes), isTrue);
    });
    test('file isPng/isJpg/isWebp', () async {
      var bytes = await File(join('data', 'white_1x1.jpg')).readAsBytes();
      expect(isJpg(bytes), isTrue);
      expect(isPng(bytes), isFalse);
      expect(isWebp(bytes), isFalse);
      bytes = await File(join('data', 'white_1x1.png')).readAsBytes();
      expect(isJpg(bytes), isFalse);
      expect(isPng(bytes), isTrue);
      expect(isWebp(bytes), isFalse);
      bytes = await File(join('data', 'white_1x1.webp')).readAsBytes();
      expect(isJpg(bytes), isFalse);
      expect(isPng(bytes), isFalse);
      expect(isWebp(bytes), isTrue);
    });
  });
}
