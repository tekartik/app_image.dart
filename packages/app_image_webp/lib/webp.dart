/// Pure Dart WebP encoder and decoder.
///
/// Decoding supports lossy (VP8), lossless (VP8L) and alpha (`ALPH`) still
/// images, including the extended `VP8X` container. Encoding produces lossy
/// VP8 (with lossless-compressed alpha) or lossless VP8L files.
///
/// ```dart
/// import 'package:tekartik_app_image_webp/webp.dart';
///
/// final image = decodeWebp(bytes);
/// final out = encodeWebp(image, options: WebpEncodeOptions(quality: 80));
/// ```
library;

export 'src/decoder.dart' show decodeWebp, webpInfo;
export 'src/encoder.dart' show encodeWebp, WebpEncodeOptions, WebpPreset;
export 'src/webp_image.dart'
    show WebpFormat, WebpFormatException, WebpImage, WebpInfo;
