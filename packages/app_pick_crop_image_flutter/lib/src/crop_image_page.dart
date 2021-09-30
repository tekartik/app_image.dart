import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/pick_crop_image.dart';

class CropImagePageResult {
  final Rect? cropRect;

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
      appBar: AppBar(
        title: const Text('Crop'),
      ),
      body: SafeArea(
        child: ExtendedImage.memory(
          widget.bytes,
          fit: BoxFit.contain,
          mode: ExtendedImageMode.editor,
          extendedImageEditorKey: editorKey,
          initEditorConfigHandler: (state) {
            return EditorConfig(
                maxScale: 8.0,
                cropRectPadding: const EdgeInsets.all(20.0),
                hitTestSize: 20.0,
                cropAspectRatio: widget.options.aspectRatio?.toDouble());
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: () {
            final cropRect = editorKey.currentState!.getCropRect();
            Navigator.of(context).pop(CropImagePageResult(cropRect: cropRect));
          },
          child: const Icon(Icons.check)),
    );
  }
}
