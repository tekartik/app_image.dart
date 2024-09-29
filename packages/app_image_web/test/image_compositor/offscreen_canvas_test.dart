@TestOn('chrome')
library;

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/src/image_bytes_utils.dart';
import 'package:tekartik_app_image_web/src/blob_utils.dart';
import 'package:tekartik_app_image_web/src/offscreen_canvas/src/offscreen_canvas.dart';
import 'package:test/test.dart';

void main() {
  group('Offscreen', () {
    test('blobToBytes implementation jpg', () async {
      var canvas = OffscreenCanvas(1, 1);
      var blob = await canvas.toBlob(ImageEncodingJpg(quality: 75));
      var bytes = await blobToBytesUsingArrayBuffer(blob);
      expect(isJpg(bytes), isTrue);
      expect(isPng(bytes), isFalse);
      bytes = await blobToBytesUsingFileReader(blob);
      expect(isJpg(bytes), isTrue);
      expect(isPng(bytes), isFalse);
      bytes = await blobToBytes(blob);
      expect(isJpg(bytes), isTrue);
      expect(isPng(bytes), isFalse);
    });

    test('blobToBytes png', () async {
      var canvas = OffscreenCanvas(1, 1);
      var blob = await canvas.toBlob(ImageEncodingPng());
      var bytes = await blobToBytes(blob);
      expect(isJpg(bytes), isFalse);
      expect(isPng(bytes), isTrue);
    });
  });
}
