import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:tekartik_app_image/app_image_resize.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/pick_crop_image.dart';

class CropImagePageResult {
  final CropRect? cropRect;

  CropImagePageResult({required this.cropRect});

  @override
  String toString() => {'cropRect': cropRect}.toString();
}

class CropImagePage extends StatefulWidget {
  final Uint8List bytes;
  final PickCropImageOptions options;
  const CropImagePage({Key? key, required this.bytes, required this.options})
      : super(key: key);

  @override
  _CropImagePageState createState() => _CropImagePageState();
}

class _CropImagePageState extends State<CropImagePage> {
  final editorKey = GlobalKey<ExtendedImageEditorState>();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, top: 32, bottom: 48),
              child: ExtendedImage.memory(
                widget.bytes,
                fit: BoxFit.contain,
                mode: ExtendedImageMode.editor,
                extendedImageEditorKey: editorKey,
                initEditorConfigHandler: (state) {
                  return EditorConfig(
                      maxScale: 8.0,
                      //cropRectPadding: const EdgeInsets.all(20.0),
                      hitTestSize: 20.0,
                      cropAspectRatio: widget.options.aspectRatio?.toDouble());
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
                )),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: () {
            final cropRect = editorKey.currentState!.getCropRect();
            Navigator.of(context).pop(CropImagePageResult(
                cropRect: cropRect == null
                    ? null
                    : CropRect.fromLTWH(cropRect.left, cropRect.top,
                        cropRect.width, cropRect.height)));
          },
          child: const Icon(Icons.check)),
    );
  }
}
