import 'dart:typed_data';

import 'package:tekaly_file_download/download_file.dart';

/// Save an image file.
///
/// On the web the browser downloads it, elsewhere a save as dialog is shown
/// (`tekaly_file_download`).
Future<void> saveImageFile({
  required Uint8List bytes,
  required String mimeType,
  required String filename,
}) => downloadFile(
  DownloadFileInfo(filename: filename, data: bytes, mimeType: mimeType),
);
