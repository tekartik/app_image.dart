import 'dart:typed_data';

import 'package:tekartik_app_image_webp/webp.dart';
// The encoder, loaded on demand: not in main.dart.js.
import 'package:tekartik_app_image_webp/webp.dart' deferred as webp_codec;

/// Encodes with the pure Dart encoder, loaded on the first call.
Future<Uint8List> encodeWebpDeferred(
  WebpImage image,
  WebpEncodeOptions options,
) async {
  await webp_codec.loadLibrary();
  return webp_codec.encodeWebp(image, options: options);
}
