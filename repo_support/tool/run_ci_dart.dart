import 'package:dev_build/package.dart';
import 'package:path/path.dart';

Future main() async {
  for (var dir in ['app_image', 'app_image_web']) {
    await packageRunCi(join('..', 'packages', dir));
  }
}
