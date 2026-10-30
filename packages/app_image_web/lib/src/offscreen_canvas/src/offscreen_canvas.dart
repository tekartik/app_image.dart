// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:tekartik_app_image/app_image.dart';
import 'package:tekartik_app_image_web/src/import.dart';
import 'package:tekartik_app_image_web/src/webp_codec_deferred.dart';
import 'package:tekartik_app_image_web/src/webp_encoder.dart';
import 'package:tekartik_app_image_webp/webp.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_common_utils/size/size.dart';
import 'package:web/web.dart' as web;

/// {@template offscreen_canvas}
/// Polyfill for html.OffscreenCanvas that is not supported on some browsers.
/// {@endtemplate}
class OffscreenCanvas {
  /// Create a canvas from bytes
  static Future<OffscreenCanvas> fromBytes(Uint8List bytes) async {
    var result = Completer<OffscreenCanvas>();
    var image = web.HTMLImageElement();
    image.onLoad.listen((_) {
      var canvas = OffscreenCanvas(image.naturalWidth, image.naturalHeight);
      canvas._canvasElement!.context2D.drawImage(image, 0, 0);
      result.complete(canvas);
    });
    image.onError.listen((Object event) {
      result.completeError(event);
    });
    var srcBlob = web.Blob([bytes.toJS].toJS);

    var srcUrl = web.URL.createObjectURL(srcBlob);
    // ignore: unsafe_html
    image.src = srcUrl;
    return result.future;
  }

  /// {@macro offscreen_canvas}
  OffscreenCanvas(this.width, this.height) {
    // For now force html Canvas
    // ignore: dead_code
    if (false) {
      // OffscreenCanvas.supported) {
      _offScreenCanvas = web.OffscreenCanvas(width, height);
    } else {
      _canvasElement = web.HTMLCanvasElement()
        ..width = width
        ..height = height;
      _canvasElement!.className = 'gl-canvas';
      final cssWidth = width / web.window.devicePixelRatio;
      final cssHeight = height / web.window.devicePixelRatio;
      _canvasElement!.style
        ..position = 'absolute'
        ..width = '${cssWidth}px'
        ..height = '${cssHeight}px';
    }

    /// Initialize context.
    getContext2d();
  }

  /// Only one is non null
  web.OffscreenCanvas? _offScreenCanvas;
  web.HTMLCanvasElement? _canvasElement;

  /// The desired width of the canvas.
  final int width;

  /// The desired height of the canvas.
  final int height;
  Object? _context;
  static bool? _supported;

  /// Clears internal state which includes references various canvas elements.
  void dispose() {
    _offScreenCanvas = null;
    _canvasElement = null;
  }

  /// Generates a data url from the offscreen canvas.
  Future<String> toDataUrl() {
    final completer = Completer<String>();
    if (_offScreenCanvas != null) {
      _offScreenCanvas!.convertToBlob().toDart.then((web.Blob value) {
        final fileReader = web.FileReader();
        web.EventStreamProviders.loadEvent.forTarget(fileReader).listen((
          web.Event event,
        ) {
          completer.complete((fileReader.result as JSString).toDart);
        });
        fileReader.readAsDataURL(value);
      });
      return completer.future;
    } else {
      return Future.value(_canvasElement!.toDataUrl('image/png'));
    }
  }

  /// Convert canvas to blob.
  Future<web.Blob> canvasToBlob(
    web.HTMLCanvasElement canvas,
    String mimeType,
    int? quality,
  ) {
    var completer = Completer<web.Blob>();
    void callback(web.Blob blob) {
      completer.complete(blob);
    }

    if (quality != null) {
      // Quality is from 0 to 100 but we want from 0 to 1
      canvas.toBlob(callback.toJS, mimeType, (quality / 100).toJS);
    } else {
      canvas.toBlob(callback.toJS, mimeType);
    }
    return completer.future;
  }

  /// Encodes the canvas pixels as webp with the pure Dart encoder
  /// (`tekartik_app_image_webp`, lossy, quality 75 by default).
  ///
  /// Synchronous and CPU bound, on the calling thread; calling it puts the
  /// encoder in `main.dart.js` ([toBlob] loads it on demand).
  Uint8List toWebpBytes({
    WebpEncodeOptions options = const WebpEncodeOptions(),
  }) => encodeWebp(_webpImage(), options: options);

  /// The canvas pixels.
  WebpImage _webpImage() {
    final imageData = _canvasElement != null
        ? _canvasElement!.context2D.getImageData(0, 0, width, height)
        : offscreenCanvasRenderingContext2D!.getImageData(0, 0, width, height);
    final rgba = Uint8List.sublistView(imageData.data.toDart);
    return WebpImage(width, height, rgba);
  }

  /// Webp encoded by [appImageWebpEncoder], else by the pure Dart encoder
  /// loaded on demand (main thread).
  Future<web.Blob> _toWebpBlobDart(int quality) async {
    final encoder = appImageWebpEncoder ?? encodeWebpDeferred;
    final bytes = await encoder(
      _webpImage(),
      WebpEncodeOptions(quality: quality.toDouble()),
    );
    return web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeTypeWebp));
  }

  /// False once the browser returned another format for webp.
  static bool? _browserWebpSupported;

  // https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvas/convertToBlob
  /// Convert to blob.
  ///
  /// Webp is encoded by [appImageWebpEncoder] when set. Otherwise the
  /// browser encodes it, falling back to the pure Dart encoder (loaded on
  /// demand) when it cannot (Safari): the blob always matches the encoding
  /// mime type.
  Future<web.Blob> toBlob(ImageEncoding encoding) async {
    if (encoding is! ImageEncodingJpg &&
        encoding is! ImageEncodingPng &&
        encoding is! ImageEncodingWebp) {
      throw UnsupportedError('Unsupported image encoding $encoding');
    }
    int? quality;
    if (encoding is ImageEncodingJpg) {
      quality = encoding.quality;
    } else if (encoding is ImageEncodingWebp) {
      quality = encoding.quality == imageEncodingWebpQualityUnknown
          ? imageEncodingWebpQualityDefault
          : encoding.quality;
      if (appImageWebpEncoder != null || _browserWebpSupported == false) {
        return await _toWebpBlobDart(quality);
      }
    }
    web.Blob blob;
    if (_offScreenCanvas != null) {
      var blobOptions = web.ImageEncodeOptions();
      blobOptions.type = encoding.mimeType;
      if (quality != null) {
        blobOptions.quality = quality / 100;
      }
      blob = await _offScreenCanvas!.convertToBlob(blobOptions).toDart;
    } else {
      blob = await canvasToBlob(_canvasElement!, encoding.mimeType, quality);
    }
    // A browser that cannot encode a type silently falls back to png.
    if (blob.type != encoding.mimeType) {
      if (encoding is ImageEncodingWebp) {
        _browserWebpSupported = false;
        return await _toWebpBlobDart(quality!);
      }
      throw UnsupportedError(
        'This browser cannot encode $encoding (it produced ${blob.type})',
      );
    }
    return blob;
  }

  /// Draw image to rect.
  void drawImageToRect(
    OffscreenCanvas offscreenCanvas,
    Rect<double> destRect, {
    Rect<double>? sourceRect,
  }) {
    if (_canvasElement != null) {
      if (sourceRect != null) {
        _canvasElement!.context2D.drawImage(
          offscreenCanvas._canvasElement!,
          sourceRect.left,
          sourceRect.top,
          sourceRect.width,
          sourceRect.height,
          destRect.left,
          destRect.top,
          destRect.width,
          destRect.height,
        );
      } else {
        _canvasElement!.context2D.drawImage(
          offscreenCanvas._canvasElement!,
          destRect.left,
          destRect.top,
          destRect.width,
          destRect.height,
        );
      }
    }
  }

  /// One of 2 is set below
  web.OffscreenCanvasRenderingContext2D?
  get offscreenCanvasRenderingContext2D =>
      _offScreenCanvas?.getContext('2d')
          as web.OffscreenCanvasRenderingContext2D;

  /// One of 2 is set below
  web.CanvasRenderingContext2D? get canvasRenderingContext2D =>
      _canvasElement?.context2D;

  /// Returns CanvasRenderContext2D or OffscreenCanvasRenderingContext2D to
  /// paint into.
  Object? getContext2d() => _context ??= (_offScreenCanvas != null
      ? _offScreenCanvas!.getContext('2d')
      : _canvasElement!.getContext('2d'));

  /// Proxy to `canvas.getContext('2d').save()`.
  void save() {
    offscreenCanvasRenderingContext2D?.save();
    canvasRenderingContext2D?.save();
  }

  /// Proxy to `canvas.getContext('2d').restore()`.
  void restore() {
    offscreenCanvasRenderingContext2D?.restore();
    canvasRenderingContext2D?.restore();
  }

  /// Proxy to `canvas.getContext('2d').translate()`.
  void translate(double x, double y) {
    offscreenCanvasRenderingContext2D?.translate(x, y);
    canvasRenderingContext2D?.translate(x, y);
  }

  /// Proxy to `canvas.getContext('2d').rotate()`.
  void rotate(double angle) {
    if (offscreenCanvasRenderingContext2D != null) {
      offscreenCanvasRenderingContext2D!.rotate(angle);
    } else {
      canvasRenderingContext2D!.rotate(angle);
    }
  }

  /// Proxy to `canvas.getContext('2d').drawImage()`.
  void drawImage(JSObject image, int x, int y, int width, int height) {
    if (offscreenCanvasRenderingContext2D != null) {
      offscreenCanvasRenderingContext2D!.drawImage(image, x, y, width, height);
    } else {
      canvasRenderingContext2D!.drawImage(image, x, y, width, height);
    }
  }

  /// Creates a rectangular path whose starting point is at (x, y) and
  /// whose size is specified by width and height and clips the path.
  void clipRect(int x, int y, int width, int height) {
    if (offscreenCanvasRenderingContext2D != null) {
      offscreenCanvasRenderingContext2D!.beginPath();
      offscreenCanvasRenderingContext2D!.rect(x, y, width, height);
      offscreenCanvasRenderingContext2D!.clip();
    } else {
      canvasRenderingContext2D!.beginPath();
      canvasRenderingContext2D!.rect(x, y, width, height);
      canvasRenderingContext2D!.clip();
    }
  }

  /// Feature detection for transferToImageBitmap on OffscreenCanvas.
  bool get transferToImageBitmapSupported {
    if (offscreenCanvasRenderingContext2D != null) {
      return offscreenCanvasRenderingContext2D!.has('transferToImageBitmap');
    } else {
      return canvasRenderingContext2D!.has('transferToImageBitmap');
    }
  }

  /// Creates an ImageBitmap object from the most recently rendered image
  /// of the OffscreenCanvas.
  ///
  /// !Warning API still in experimental status, feature detect before using.
  web.ImageBitmap? transferToImageBitmap() {
    if (offscreenCanvasRenderingContext2D != null) {
      return offscreenCanvasRenderingContext2D!.callMethod(
        'transferToImageBitmap'.toJS,
      );
    } else {
      return canvasRenderingContext2D!.callMethod('transferToImageBitmap'.toJS);
    }
  }

  /// Draws canvas contents to a rendering context.
  void transferImage(JSObject targetContext) {
    // Actual size of canvas may be larger than viewport size. Use
    // source/destination to draw part of the image data.
    targetContext.callMethodVarArgs('drawImage'.toJS, [
      _offScreenCanvas ?? _canvasElement!,
      0.toJS,
      0.toJS,
      width.toJS,
      height.toJS,
      0.toJS,
      0.toJS,
      width.toJS,
      height.toJS,
    ]);
  }

  /// Feature detects OffscreenCanvas.
  static bool get supported => _supported ??= web.window.has('OffscreenCanvas');
}
