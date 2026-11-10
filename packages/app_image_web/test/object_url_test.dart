@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:tekartik_app_image_web/image_decoder.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'white_1x1_png.dart' as png;

/// The object urls created while running [action].
Future<List<String>> _recordObjectUrls(Future<void> Function() action) async {
  globalContext.callMethod(
    'eval'.toJS,
    '''
    window.__appImageWebUrls = [];
    window.__appImageWebCreate = URL.createObjectURL;
    URL.createObjectURL = function (blob) {
      const url = window.__appImageWebCreate.call(URL, blob);
      window.__appImageWebUrls.push(url);
      return url;
    };
    '''
        .toJS,
  );
  try {
    await action();
  } finally {
    globalContext.callMethod(
      'eval'.toJS,
      'URL.createObjectURL = window.__appImageWebCreate;'.toJS,
    );
  }
  return (globalContext['__appImageWebUrls'] as JSArray<JSString>).toDart
      .map((url) => url.toDart)
      .toList();
}

/// True if [url] can still be fetched (not revoked).
Future<bool> _isAlive(String url) async {
  try {
    await web.window.fetch(url.toJS).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('object urls revoked', () async {
    var urls = await _recordObjectUrls(() async {
      await getImageMetaFromBytes(png.bytes);
      await resizeTo(png.bytes, options: ResizeOptions(width: 4, height: null));
    });
    expect(urls, hasLength(2));
    var alive = <String>[];
    for (var url in urls) {
      if (await _isAlive(url)) {
        alive.add(url);
      }
    }
    expect(alive, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('object url revoked on a decoding error', () async {
    var urls = await _recordObjectUrls(() async {
      // A png header followed by garbage: the browser fails to decode it.
      await expectLater(
        getImageMetaFromBytes(png.bytes.sublist(0, 40)),
        throwsA(anything),
      );
    });
    expect(urls, hasLength(1));
    expect(await _isAlive(urls.single), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
