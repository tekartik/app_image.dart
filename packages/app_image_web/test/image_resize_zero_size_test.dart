import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_common_utils/env_utils.dart';
import 'package:test/test.dart';

import 'white_1x1_jpg.dart' as jpg;

/// The value or the error of [resizeTo], a TimeoutException when it does not
/// complete within 10 seconds.
Future<Object?> _resizeOutcome(ResizeOptions options) =>
    resizeTo(jpg.bytes, options: options)
        .then<Object?>((value) => value, onError: (Object error) => error)
        .timeout(const Duration(seconds: 10));

void main() {
  group('resize zero size', () {
    // The web canvas cannot encode an image with a zero side: it throws (it
    // used to hang). On the VM it depends on package:image (4.12 throws
    // 'Cannot encode an empty image', older versions encode it).
    test('0x0', () async {
      var outcome = await _resizeOutcome(ResizeOptions(width: 0, height: 0));
      if (kDartIsWeb) {
        expect(outcome, isA<StateError>());
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('height rounded to 0', () async {
      // Crop ratio 2.5, width 1: height round(0.4) = 0.
      var outcome = await _resizeOutcome(
        ResizeOptions(
          width: 1,
          height: null,
          cropRect: CropRect.fromLTWH(0, 0, .5, .2),
          encoding: ImageEncodingJpg(quality: 80),
        ),
      );
      if (kDartIsWeb) {
        expect(outcome, isA<StateError>());
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
