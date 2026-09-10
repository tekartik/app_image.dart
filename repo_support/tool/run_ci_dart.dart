import 'package:dev_build/package.dart';
import 'package:path/path.dart';

Future main() async {
  for (var dir in ['app_image', 'app_image_web', 'app_image_webp']) {
    await packageRunCi(join('..', 'packages', dir));
  }
}
