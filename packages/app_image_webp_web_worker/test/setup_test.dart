@TestOn('vm')
library;

import 'package:tekartik_app_image_webp_web_worker/setup.dart';
import 'package:test/test.dart';

void main() {
  // Also builds the worker that test/webp_worker_test.dart loads in Chrome
  // (tool/dev_build_setup.dart, run by run_ci before the tests, does too).
  test('builds the worker once', () async {
    var result = await setupWebpWorker(dir: 'test');
    var segments = result.file.uri.pathSegments;
    expect(segments.sublist(segments.length - 2), [
      'test',
      webpWorkerJsFilename,
    ]);
    var js = await result.file.readAsString();
    expect(
      js,
      startsWith('// Web worker of tekartik_app_image_webp_web_worker'),
    );
    expect(js, isNot(contains('sourceMappingURL')));
    var packages = (result.key['packages'] as Map).keys;
    expect(
      packages,
      containsAll([
        'tekartik_app_image_webp_web_worker',
        'tekartik_app_image_webp',
        'web',
      ]),
    );
    expect(packages, isNot(contains('test')));
    var again = await setupWebpWorker(dir: 'test');
    expect(again.built, isFalse);
    expect(again.written, isFalse);
    expect(again.version, result.version);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
