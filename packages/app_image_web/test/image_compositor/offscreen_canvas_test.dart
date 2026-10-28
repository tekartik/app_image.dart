@TestOn('chrome')
library;

import 'dart:js_interop';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/src/image_bytes_utils.dart';
import 'package:tekartik_app_image_web/src/blob_utils.dart';
import 'package:tekartik_app_image_web/src/offscreen_canvas/src/offscreen_canvas.dart';
import 'package:tekartik_app_image_webp/webp.dart';
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
      var blob = await canvas.toBlob(const ImageEncodingPng());
      var bytes = await blobToBytes(blob);
      expect(isJpg(bytes), isFalse);
      expect(isPng(bytes), isTrue);
    });

    test('blobToBytes webp', () async {
      // Chrome encodes webp; a browser that cannot throws (never png bytes).
      var canvas = OffscreenCanvas(1, 1);
      var blob = await canvas.toBlob(const ImageEncodingWebp());
      expect(blob.type, mimeTypeWebp);
      var bytes = await blobToBytes(blob);
      expect(isWebp(bytes), isTrue);
      expect(isPng(bytes), isFalse);
    });

    test('toBlob webp quality', () async {
      var canvas = OffscreenCanvas(32, 32);
      var ctx = canvas.canvasRenderingContext2D!;
      for (var i = 0; i < 64; i++) {
        ctx
          ..fillStyle = 'hsl(${i * 37 % 360},70%,50%)'.toJS
          ..fillRect((i * 7) % 32, (i * 5) % 32, 3, 2);
      }
      Future<int> size(int quality) async =>
          (await canvas.toBlob(ImageEncodingWebp(quality: quality))).size;
      expect(await size(10), lessThan(await size(95)));
    });

    test('toWebpBytes pure dart', () async {
      // The Safari fallback, red left half, transparent right half.
      var canvas = OffscreenCanvas(4, 2);
      canvas.canvasRenderingContext2D!
        ..fillStyle = '#ff0000'.toJS
        ..fillRect(0, 0, 2, 2);
      var bytes = canvas.toWebpBytes(
        options: const WebpEncodeOptions(lossless: true),
      );
      expect(isWebp(bytes), isTrue);
      var image = decodeWebp(bytes);
      expect([image.width, image.height], [4, 2]);
      expect(image.rgba.sublist(0, 4), [255, 0, 0, 255]);
      expect(image.rgba[3 * 4 + 3], 0);
    });
  });
}
