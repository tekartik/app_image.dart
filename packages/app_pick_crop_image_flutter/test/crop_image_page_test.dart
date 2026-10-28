import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/crop_image_page.dart';

// A 1x1 png.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0, //
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, //
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

void main() {
  Widget app(PickCropImageOptions options) => MaterialApp(
    home: CropImagePage(bytes: _png, options: options),
  );

  testWidgets('titled crop page', (tester) async {
    await tester.pumpWidget(
      app(
        PickCropImageOptions(
          aspectRatio: 1,
          source: PickCropImageSourceMemory(bytes: _png),
          title: 'Crop the thumbnail',
          hint: 'Drag and zoom',
          confirmLabel: 'Use',
        ),
      ),
    );
    expect(find.text('Crop the thumbnail'), findsOneWidget);
    expect(find.text('Drag and zoom'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Use'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('untitled crop page keeps the floating buttons', (tester) async {
    await tester.pumpWidget(app(PickCropImageOptions(aspectRatio: 1)));
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
