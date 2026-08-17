import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

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

/// Picked file platform, from the file picker (desktop).
class TkPickedFilePlatform implements TkPickedFile {
  /// File picker result.
  final TekalyPickedFile pickedFile;

  /// Picked file platform constructor.
  TkPickedFilePlatform(this.pickedFile);

  @override
  Future<Uint8List> readAsBytes() => pickedFile.readAsBytes();
}
