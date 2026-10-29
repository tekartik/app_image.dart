import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';
import 'package:tekartik_app_image_webp_web_worker/webp_worker.dart';
import 'package:test/test.dart';

const _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// A gradient, half transparent on the right.
WebpImage _image(int width, int height) {
  var rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var i = (y * width + x) * 4;
      rgba[i] = x * 255 ~/ width;
      rgba[i + 1] = y * 255 ~/ height;
      rgba[i + 2] = 128;
      rgba[i + 3] = x < width ~/ 2 ? 255 : 128;
    }
  }
  return WebpImage(width, height, rgba);
}

const _lossless = WebpEncodeOptions(lossless: true, exact: true);

void main() {
  group('WebpWorker', () {
    late WebpWorker worker;
    late bool running;
    setUpAll(() async {
      // test/webp_worker.js on the web, built by tool/dev_build_setup.dart.
      worker = WebpWorker(fallback: false);
      running = await worker.ready;
    });
    tearDownAll(() => worker.close());

    void skipIfNotRunning() {
      if (!running) {
        markTestSkipped(
          'test/$webpWorkerJsFilename not built: '
          'dart run tool/dev_build_setup.dart (or the VM tests) first',
        );
      }
    }

    test('ready', () {
      if (!_isWeb) {
        expect(running, isTrue);
      }
      skipIfNotRunning();
    });

    test('encode lossless', () async {
      skipIfNotRunning();
      if (!running) {
        return;
      }
      var image = _image(40, 30);
      var bytes = await worker.encode(image, options: _lossless);
      var decoded = decodeWebp(bytes);
      expect([decoded.width, decoded.height], [40, 30]);
      expect(decoded.rgba, image.rgba);
      // Not moved.
      expect(image.rgba, hasLength(40 * 30 * 4));
    });

    test('encode lossy, transfer, concurrent', () async {
      skipIfNotRunning();
      if (!running) {
        return;
      }
      var sizes = [(16, 16), (64, 48), (33, 7)];
      var results = await Future.wait([
        for (var (width, height) in sizes)
          worker.encode(
            _image(width, height),
            options: const WebpEncodeOptions(quality: 60),
            transfer: true,
          ),
      ]);
      for (var i = 0; i < sizes.length; i++) {
        var info = webpInfo(results[i]);
        expect([info.width, info.height], [sizes[i].$1, sizes[i].$2]);
        expect(info.isLossless, isFalse);
        expect(info.hasAlpha, isTrue);
      }
      // Same bytes as on the main thread.
      var image = _image(64, 48);
      expect(
        results[1],
        encodeWebp(image, options: const WebpEncodeOptions(quality: 60)),
      );
    });

    test('encoder error', () async {
      skipIfNotRunning();
      if (!running) {
        return;
      }
      // Too wide for webp: the encoder throws.
      var image = WebpImage(16384, 1, Uint8List(16384 * 4));
      await expectLater(
        worker.encode(image),
        throwsA(_isWeb ? isA<WebpWorkerException>() : isA<ArgumentError>()),
      );
      // Still working.
      expect(await worker.encode(_image(2, 2)), isNotEmpty);
    });
  });

  test('fallback on the main thread', () async {
    var worker = WebpWorker(url: 'missing_webp_worker.js');
    try {
      expect(await worker.ready, !_isWeb);
      var image = _image(8, 8);
      var bytes = await worker.encode(image, options: _lossless);
      expect(decodeWebp(bytes).rgba, image.rgba);
    } finally {
      await worker.close();
    }
  });

  test('no fallback', () async {
    var worker = WebpWorker(url: 'missing_webp_worker.js', fallback: false);
    try {
      if (_isWeb) {
        await expectLater(worker.encode(_image(2, 2)), throwsStateError);
      } else {
        expect(await worker.encode(_image(2, 2)), isNotEmpty);
      }
    } finally {
      await worker.close();
    }
  });

  test('closed', () async {
    var worker = WebpWorker();
    await worker.close();
    expect(await worker.ready, isFalse);
    await expectLater(worker.encode(_image(2, 2)), throwsStateError);
  });
}
