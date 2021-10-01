import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tekartik_app_image/app_image.dart';
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
    sleep(100).then((_) async {
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
            ImageData? imageData;
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

                  imageData = await resizeTo(bytes, options: convertOptions);
                  popImageData(imageData);
                  return;
                }
              }
            } catch (e) {
              // ignore: avoid_print
              print('crop error $e');
            }
            if (imageData == null) {
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

  void popImageData(ImageData imageData) {
    if (mounted) {
      // devPrint('converted to ${bytes.length} $mimeType');
      Navigator.pop(context, imageData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: Icon(
      Icons.hourglass_empty_outlined,
      size: 32,
      color: Colors.grey.shade300,
    )));
  }
}
