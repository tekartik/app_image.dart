import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

class OvalEditorCropLayerPainter extends EditorCropLayerPainter {
  const OvalEditorCropLayerPainter();

  @override
  void paintCorners(
      Canvas canvas, Size size, ExtendedImageCropLayerPainter painter) {
    final paint = Paint()
      ..color = painter.cornerColor
      ..style = PaintingStyle.fill;
    final cropRect = painter.cropRect;
    const radius = 6.0;
    canvas.drawCircle(Offset(cropRect.left, cropRect.top), radius, paint);
    canvas.drawCircle(Offset(cropRect.right, cropRect.top), radius, paint);
    canvas.drawCircle(Offset(cropRect.left, cropRect.bottom), radius, paint);
    canvas.drawCircle(Offset(cropRect.right, cropRect.bottom), radius, paint);
  }

  @override
  void paintMask(
      Canvas canvas, Size size, ExtendedImageCropLayerPainter painter) {
    final rect = Offset.zero & size;
    final cropRect = painter.cropRect;
    final maskColor = painter.maskColor;
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.fill
          ..color = maskColor);
    canvas.drawOval(cropRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  @override
  void paintLines(
      Canvas canvas, Size size, ExtendedImageCropLayerPainter painter) {
    final cropRect = painter.cropRect;
    if (painter.pointerDown) {
      canvas.save();
      canvas.clipPath(Path()..addOval(cropRect));
      super.paintLines(canvas, size, painter);
      canvas.restore();
    }
  }
}
