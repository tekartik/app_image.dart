import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/platform.dart';

import 'import.dart';

/// Picked file result.
abstract class TkPickedFile {
  Future<Uint8List> readAsBytes();
}

class TkPickedFileImage implements TkPickedFile {
  final XFile xFile;

  TkPickedFileImage(this.xFile);

  @override
  Future<Uint8List> readAsBytes() => xFile.readAsBytes();
}

class TkPickedFilePlatform implements TkPickedFile {
  final PlatformFile platformFile;

  TkPickedFilePlatform(this.platformFile);

  @override
  Future<Uint8List> readAsBytes() async {
    if (platformFile.bytes != null) {
      return platformFile.bytes!;
    }
    if (platformFile.readStream != null) {
      return await listStreamGetBytes(platformFile.readStream!);
    }
    if (platformFile.path != null) {
      return await readFile(platformFile.path!);
    }
    throw StateError('No data');
  }
}
