import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tekartik_app_pick_crop_image_flutter/src/platform.dart';

import 'import.dart';

/// Picked file result.
abstract class TkPickedFile {
  /// Read as bytes.
  Future<Uint8List> readAsBytes();
}

/// Picked file image.
class TkPickedFileImage implements TkPickedFile {
  /// XFile result.
  final XFile xFile;

  /// Picked file image constructor.
  TkPickedFileImage(this.xFile);

  @override
  Future<Uint8List> readAsBytes() => xFile.readAsBytes();
}

/// Picked file platform.
class TkPickedFilePlatform implements TkPickedFile {
  /// Platform file result.
  final PlatformFile platformFile;

  /// Picked file platform constructor.
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
