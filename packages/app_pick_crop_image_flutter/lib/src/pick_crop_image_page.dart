import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/platform.dart';

import 'crop_image_page.dart';
import 'import.dart' as size;
import 'import.dart';
import 'import_image.dart';
import 'pick_crop_image.dart';
import 'picked_file.dart';

class PickImageCropPage extends StatefulWidget {
  final TkPickedFile? file;
  final PickCropImageOptions options;
  final ConvertPickCropResultCallback? callback;

  const PickImageCropPage(
      {Key? key, required this.options, required this.file, this.callback})
      : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _PickImageCropPageState createState() => _PickImageCropPageState();
}

class ConvertPickCropResultParam {
  final ImageSourceData imageSource;
  final PickCropImageOptions options;
  final CropRect cropRect;

  ConvertPickCropResultParam(
      {required this.imageSource,
      required this.options,
      required this.cropRect});
}

typedef ConvertPickCropResultCallback = Future<ImageData> Function(
    ConvertPickCropResultParam param);

Future<ImageData> _callbackDefault(ConvertPickCropResultParam param) async {
  var convertOptions = PickCropConvertImageOptions(
      cropRect: param.cropRect,
      encoding: param.options.encoding,
      width: param.options.width,
      height: param.options.height,
      aspectRatio: param.options.aspectRatio);

  var imageData =
      await pickCropResizeTo(param.imageSource.bytes, options: convertOptions);
  return imageData;
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
          if (source is ImageSourceAsyncData) {
            bytes = await (source as ImageSourceAsyncData).getBytes();
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
              var callback = widget.callback ?? _callbackDefault;

              if (options.autoCrop) {
                var image = decodeImage(bytes)!;
                if (options.aspectRatio != null) {
                  var cropRect = size.sizeDoubleCenteredRectWithRatio(
                      size.Size<double>(
                          image.width.toDouble(), image.height.toDouble()),
                      options.aspectRatio!);

                  imageData = await callback(ConvertPickCropResultParam(
                      imageSource: ImageSourceData(bytes),
                      options: options,
                      cropRect: cropRect));
                } else {
                  imageData = await callback(ConvertPickCropResultParam(
                      imageSource: ImageSourceData(bytes),
                      options: options,
                      cropRect: CropRect.fromLTWH(0, 0, image.width.toDouble(),
                          image.height.toDouble())));
                }
              } else {
                var result = await Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) {
                  return CropImagePage(
                    bytes: bytes!,
                    options: options,
                  );
                }));
                if (mounted) {
                  if (result is CropImagePageResult) {
                    imageData = await callback(ConvertPickCropResultParam(
                        imageSource: ImageSourceData(bytes),
                        options: options,
                        cropRect: result.cropRect));
                  }
                }
              }
            } catch (e) {
              // ignore: avoid_print
              print('crop error $e');
            }
            if (mounted) {
              if (imageData != null) {
                popImageData(imageData);
              } else {
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
