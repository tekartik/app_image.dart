import 'package:dev_test/package.dart';
import 'package:path/path.dart';

Future main() async {
  for (var dir in [
    'app_image',
    'app_image_web',
    'app_pick_crop_image',
  ]) {
    await packageRunCi(join('..', 'packages', dir));
  }
}
