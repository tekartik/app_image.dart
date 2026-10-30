import 'package:web/web.dart' as web;

/// True when the browser encodes webp from a canvas: one that cannot
/// (Safari) gives a png data url.
bool platformWebpEncodingSupported() =>
    (web.HTMLCanvasElement()
          ..width = 1
          ..height = 1)
        .toDataUrl('image/webp')
        .startsWith('data:image/webp');
