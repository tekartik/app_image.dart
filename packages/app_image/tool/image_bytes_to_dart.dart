import 'dart:io';

import 'package:path/path.dart';
import 'package:process_run/shell.dart';

Future<void> main() async {
  Directory('.local').createSync(recursive: true);
  for (var image in ['white_1x1.jpg', 'white_1x1.png', 'white_1x1.webp']) {
    var bytes = await File(join('data', image)).readAsBytes();
    var sb = StringBuffer(
        'import \'dart:typed_data\';\nfinal Uint8List bytes = new Uint8List.fromList([');
    sb.write(bytes.map((byte) => '0x${byte.toRadixString(16)}').join(','));
    sb.write((']);'));
    var file = File(join('.local', '${image.replaceAll('.', '_')}.dart'));

    await file.writeAsString(sb.toString());
    await run('dart format ${shellArgument(file.path)}');
  }
}
