import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/pick_crop_image.dart';

import 'oval_editor_painter.dart';

class CropImagePageResult {
  final CropRect cropRect;

  CropImagePageResult({required this.cropRect});

  @override
  String toString() => {'cropRect': cropRect}.toString();
}

class CropImagePage extends StatefulWidget {
  final Uint8List bytes;
  final PickCropImageOptions options;
  const CropImagePage({super.key, required this.bytes, required this.options});

  @override
  // ignore: library_private_types_in_public_api
  _CropImagePageState createState() => _CropImagePageState();
}

class _CropImagePageState extends State<CropImagePage> {
  final editorKey = GlobalKey<ExtendedImageEditorState>();
  final _cropLayerPainter = const OvalEditorCropLayerPainter();

  PickCropImageOptions get options => widget.options;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 32,
                bottom: 48,
              ),
              child: ExtendedImage.memory(
                widget.bytes,
                fit: BoxFit.contain,
                mode: ExtendedImageMode.editor,
                extendedImageEditorKey: editorKey,
                initEditorConfigHandler: (state) {
                  if (options.ovalCropMask) {
                    return EditorConfig(
                      maxScale: 8.0,
                      cropRectPadding: const EdgeInsets.all(20.0),
                      hitTestSize: 20.0,
                      initCropRectType: InitCropRectType.imageRect,
                      cropAspectRatio: widget.options.aspectRatio?.toDouble(),
                      cropLayerPainter: _cropLayerPainter,
                      editActionDetailsIsChanged:
                          (EditActionDetails? details) {},
                    );
                  }
                  return EditorConfig(
                    maxScale: 8.0,
                    //cropRectPadding: const EdgeInsets.all(20.0),
                    hitTestSize: 20.0,
                    cropAspectRatio: widget.options.aspectRatio?.toDouble(),
                  );
                },
              ),
            ),
            IconButton(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Padding(
                padding: EdgeInsets.only(top: 8.0, left: 8),
                child: Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final cropRect = editorKey.currentState!.getCropRect();
          Navigator.of(context).pop(
            CropImagePageResult(
              cropRect: CropRect.fromLTWH(
                cropRect!.left,
                cropRect.top,
                cropRect.width,
                cropRect.height,
              ),
            ),
          );
        },
        child: const Icon(Icons.check),
      ),
    );
  }
}
