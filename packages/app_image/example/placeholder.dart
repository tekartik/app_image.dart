import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:tekartik_app_image/app_color.dart';
import 'package:tekartik_app_image/app_image_placeholder.dart';

Future<void> main(List<String> args) async {
  var data =
      await generatePlaceholderImage(color: argbToColorUint32(255, 255, 0, 0));
  var file = File(
      '.local/image_${data.width}x${data.height}${data.encoding.extension}');
  await writeBytes(file, data.bytes);
  stdout.writeln(
      'Wrote ${file.path} (${data.width}x${data.height}) ${data.bytes.length}');
}
