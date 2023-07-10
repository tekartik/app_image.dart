import 'package:dev_test/package.dart';
import 'package:path/path.dart';

Future main() async {
  for (var dir in [
    'app_image',
    'app_image_web',
    'app_pick_crop_image_flutter',
  ]) {
    await packageRunCi(join('..', 'packages', dir));
  }
  for (var dir in [
    'app_pick_crop_image_demo',
  ]) {
    await packageRunCi(join('..', 'example', dir));
  }
}
