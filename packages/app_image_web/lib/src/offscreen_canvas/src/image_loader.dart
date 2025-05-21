import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const bool _supportsDecode = true;
/*
final bool _supportsDecode = js_util.getProperty<Object?>(
        js_util.getProperty(js_util.getProperty(html.window, 'Image') as Object,
            'prototype') as Object,
        'decode') !=
    null;*/

/// Dart wrapper around an [html.ImageElement] and the element's
/// width and height.
class HtmlImage {
  /// {@macro html_image}
  const HtmlImage(this.imageElement, this.width, this.height);

  /// The image element.
  final web.HTMLImageElement imageElement;

  /// The width of the [imageElement].
  final int width;

  /// The height of the [imageElement].
  final int height;
}

/// Loads an [HtmlImage] given the `src` of the image.
class HtmlImageLoader {
  /// Ctor.
  const HtmlImageLoader(this.src);

  /// The image `src`.
  final String src;

  /// Load an image.
  Future<HtmlImage> loadImage() async {
    final completer = Completer<HtmlImage>();
    if (_supportsDecode) {
      // ignore: unsafe_html
      final imgElement = web.HTMLImageElement()..src = src;
      imgElement.decoding = 'async';

      unawaited(
        imgElement
            .decode()
            .toDart
            .then((dynamic _) {
              var naturalWidth = imgElement.naturalWidth;
              var naturalHeight = imgElement.naturalHeight;
              // Workaround for https://bugzilla.mozilla.org/show_bug.cgi?id=700533.
              if (naturalWidth == 0 && naturalHeight == 0) {
                const kDefaultImageSizeFallback = 300;
                naturalWidth = kDefaultImageSizeFallback;
                naturalHeight = kDefaultImageSizeFallback;
              }
              final image = HtmlImage(imgElement, naturalWidth, naturalHeight);
              completer.complete(image);
            })
            .catchError((dynamic e) {
              // This code path is hit on Chrome 80.0.3987.16 when too many
              // images are on the page (~1000).
              // Fallback here is to load using onLoad instead.
              _decodeUsingOnLoad(completer);
            }),
      );
    } else {
      _decodeUsingOnLoad(completer);
    }
    return completer.future;
  }

  void _decodeUsingOnLoad(Completer completer) {
    StreamSubscription<web.Event>? loadSubscription;
    late StreamSubscription<web.Event> errorSubscription;
    final imgElement = web.HTMLImageElement();
    // If the browser doesn't support asynchronous decoding of an image,
    // then use the `onload` event to decide when it's ready to paint to the
    // DOM. Unfortunately, this will cause the image to be decoded synchronously
    // on the main thread, and may cause dropped framed.
    errorSubscription = imgElement.onError.listen((web.Event event) {
      loadSubscription?.cancel();
      errorSubscription.cancel();
      completer.completeError(event);
    });
    loadSubscription = imgElement.onLoad.listen((web.Event event) {
      loadSubscription!.cancel();
      errorSubscription.cancel();
      final image = HtmlImage(
        imgElement,
        imgElement.naturalWidth,
        imgElement.naturalHeight,
      );
      completer.complete(image);
    });
    // ignore: unsafe_html
    imgElement.src = src;
  }
}
