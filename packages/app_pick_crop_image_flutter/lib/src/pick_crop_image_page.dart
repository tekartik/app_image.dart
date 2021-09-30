import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/platform.dart';

import 'crop_image_page.dart';
import 'import.dart';
import 'pick_crop_image.dart';
import 'picked_file.dart';

class PickImageCropPage extends StatefulWidget {
  final TkPickedFile? file;
  final PickCropImageOptions options;
  const PickImageCropPage({Key? key, required this.options, required this.file})
      : super(key: key);

  @override
  _PickImageCropPageState createState() => _PickImageCropPageState();
}

class _PickImageCropPageState extends State<PickImageCropPage> {
  PickCropImageOptions get options => widget.options;
  TkPickedFile? get file => widget.file;
  @override
  void initState() {
    sleep(0).then((_) async {
      if (mounted) {
        var source = options.source;
        Uint8List? bytes;

        // First step, pick image
        try {
          if (source is PickCropImageSourceMemory) {
            bytes = source.bytes;
          } else {
            if (file != null) {
              if (mounted) {
                bytes = await file!.readAsBytes();
              }
            }
          }
        } catch (e) {
          // ignore: avoid_print
          print('pick error $e');
        }
        if (bytes == null) {
          if (mounted) {
            Navigator.pop(context);
          }
        } else {
          if (mounted) {
            Uint8List? resultBytes;
            try {
              var result = await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) {
                return CropImagePage(
                  bytes: bytes!,
                  options: options,
                );
              }));
              if (mounted) {
                if (result is CropImagePageResult) {
                  var convertOptions = PickCropConvertImageOptions(
                      cropRect: result.cropRect!,
                      encoding: options.encoding,
                      width: options.width,
                      height: options.height,
                      aspectRatio: options.aspectRatio);

                  resultBytes = await resizeTo(bytes, options: convertOptions);
                  popBytes(resultBytes);
                }
              }
            } catch (e) {
              // ignore: avoid_print
              print('crop error $e');
            }
            if (resultBytes == null) {
              if (mounted) {
                Navigator.pop(context);
              }
            }
          }
        }
      }
    });
    super.initState();
  }

  void popBytes(Uint8List bytes) {
    var encoding = options.encoding;
    if (mounted) {
      // devPrint('converted to ${bytes.length} $mimeType');
      Navigator.pop(
          context, PickCropImageResult(bytes: bytes, encoding: encoding));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
