import 'package:tekartik_app_image_webp/webp.dart';
import 'package:tekartik_app_image_webp_web_worker/webp_worker.dart';
import 'package:test/test.dart';

void main() {
  group('protocol', () {
    test('options map', () {
      const defaults = WebpEncodeOptions();
      expect(
        webpEncodeOptionsToMap(webpEncodeOptionsFromMap(const {})),
        webpEncodeOptionsToMap(defaults),
      );
      var options = WebpEncodeOptions.preset(WebpPreset.drawing, quality: 42)
          .copyWith(
            lossless: true,
            method: 6,
            alphaFiltering: AlphaFiltering.best,
            exact: true,
            pass: 3,
          );
      var map = webpEncodeOptionsToMap(options);
      expect(map['alphaFiltering'], 'best');
      expect(webpEncodeOptionsToMap(webpEncodeOptionsFromMap(map)), map);
    });

    test('options map from JS numbers', () {
      // dartify gives doubles for every JS number in dart2wasm.
      var options = webpEncodeOptionsFromMap(const {
        'quality': 80,
        'method': 2.0,
        'segments': 1.0,
        'alphaFiltering': 'none',
        'unknown': 1,
      });
      expect(options.quality, 80.0);
      expect(options.method, 2);
      expect(options.segments, 1);
      expect(options.alphaFiltering, AlphaFiltering.none);
      expect(options.lossless, isFalse);
    });
  });
}
