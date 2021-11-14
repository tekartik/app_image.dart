import 'dart:math';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/platform.dart';

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
    var cropRect = painter.cropRect;
    final maskColor = painter.maskColor;
    canvas.saveLayer(rect, Paint());

    if (isCanvasKit) {
      canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.fill
            ..color = maskColor);
      canvas.drawOval(cropRect, Paint()..blendMode = BlendMode.clear);
    } else {
      // Special trick make the rect as big as the image to fill it
      var dW = size.width - cropRect.width;
      var dH = size.height - cropRect.height;

      var strokeWidth = max(dW, dH) *
          1.5; // square root of 2 should be sufficient but that's ok...
      //var extent
      cropRect = Rect.fromLTRB(
          cropRect.left - strokeWidth / 2,
          cropRect.top - strokeWidth / 2,
          cropRect.right + strokeWidth / 2,
          cropRect.bottom + strokeWidth / 2);
      canvas.drawOval(
          cropRect,
          Paint()
            ..color = maskColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..color = maskColor); //..blendMode = BlendMode.clear);
    }
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
