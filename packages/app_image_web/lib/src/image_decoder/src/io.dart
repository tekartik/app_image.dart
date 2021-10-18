import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image/image_decoder/image_decoder.dart' as common;

Future<ImageMeta> getImageMetaFromBytes(Uint8List bytes) =>
    common.getImageMetaFromBytes(bytes);
