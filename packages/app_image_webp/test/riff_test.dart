import 'dart:typed_data';

import 'package:tekartik_app_image_webp/src/riff.dart';
import 'package:test/test.dart';

void main() {
  test('RiffBuilder / WebpContainer round trip', () {
    final builder = RiffBuilder()
      ..addVp8x(Vp8xFlags.alpha, 300, 200)
      ..add('ALPH', Uint8List.fromList([1, 2, 3]))
      ..add('VP8 ', Uint8List.fromList([4, 5, 6, 7]));
    final bytes = builder.build();
    expect(bytes.length.isEven, isTrue);
    final container = WebpContainer.parse(bytes);
    expect(container.isExtended, isTrue);
    expect(container.canvasWidth, 300);
    expect(container.canvasHeight, 200);
    expect(container.vp8xFlags & Vp8xFlags.alpha, isNonZero);
    expect(container.chunks.map((c) => c.tag), ['VP8X', 'ALPH', 'VP8 ']);
    expect(container.find('ALPH')!.data, [1, 2, 3]);
    expect(container.find('VP8 ')!.data, [4, 5, 6, 7]);
    expect(container.find('XXXX'), isNull);
  });
}
