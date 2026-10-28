import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/pick_crop_image.dart';

import 'oval_editor_painter.dart';

/// Crop image page result.
class CropImagePageResult {
  /// Crop rectangle.
  final CropRect cropRect;

  /// Crop image page result constructor.
  CropImagePageResult({required this.cropRect});

  @override
  String toString() => {'cropRect': cropRect}.toString();
}

/// Crop image page.
class CropImagePage extends StatefulWidget {
  /// Image bytes.
  final Uint8List bytes;

  /// Pick crop image options.
  final PickCropImageOptions options;

  /// Crop image page constructor.
  const CropImagePage({super.key, required this.bytes, required this.options});

  @override
  // ignore: library_private_types_in_public_api
  _CropImagePageState createState() => _CropImagePageState();
}

class _CropImagePageState extends State<CropImagePage> {
  final editorKey = GlobalKey<ExtendedImageEditorState>();
  final _cropLayerPainter = const OvalEditorCropLayerPainter();

  PickCropImageOptions get options => widget.options;

  void _confirm() {
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
  }

  Widget _editor({EdgeInsets? padding}) => Padding(
    padding:
        padding ??
        const EdgeInsets.only(left: 16, right: 16, top: 32, bottom: 48),
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
            editActionDetailsIsChanged: (EditActionDetails? details) {},
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
  );

  @override
  Widget build(BuildContext context) {
    var title = options.title;
    if (title != null) {
      var confirmLabel = options.confirmLabel;
      var hint = options.hint;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: confirmLabel == null
                  ? IconButton(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check),
                    )
                  : FilledButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check),
                      label: Text(confirmLabel),
                    ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _editor(padding: const EdgeInsets.all(16))),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            _editor(),
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
        onPressed: _confirm,
        child: const Icon(Icons.check),
      ),
    );
  }
}
