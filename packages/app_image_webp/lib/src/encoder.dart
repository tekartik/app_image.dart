import 'dart:typed_data';

import 'riff.dart';
import 'vp8/alpha.dart';
import 'vp8/vp8_encoder.dart';
import 'vp8/yuv.dart';
import 'vp8l/vp8l_encoder.dart';
import 'webp_image.dart';

/// Tuning presets, mirroring libwebp's `WebPPreset`.
enum WebpPreset {
  /// Default preset.
  defaultPreset,

  /// Digital picture, like portrait, inner shot.
  picture,

  /// Outdoor photograph, with natural lighting.
  photo,

  /// Hand or line drawing, with high-contrast details.
  drawing,

  /// Small-sized colorful images.
  icon,

  /// Text-like.
  text,
}

/// Options controlling [encodeWebp].
class WebpEncodeOptions {
  /// Use lossless (VP8L) compression instead of lossy (VP8).
  final bool lossless;

  /// Quality factor 0..100. For lossy this drives the quantizer; for
  /// lossless it drives the compression effort.
  final double quality;

  /// Compression method, 0 (fast) to 6 (slower, smaller files).
  final int method;

  /// Quality of the alpha plane (0..100, 100 = lossless alpha), lossy only.
  final int alphaQuality;

  /// Alpha compression method: 0 none, 1 lossless (default).
  final int alphaCompression;

  /// Alpha plane prediction filtering strategy.
  final AlphaFiltering alphaFiltering;

  /// Preserve the RGB values of fully transparent pixels.
  final bool exact;

  /// Spatial noise shaping strength (0..100), lossy only.
  final int snsStrength;

  /// Loop filter strength (0 = off .. 100), lossy only.
  final int filterStrength;

  /// Loop filter sharpness (0..7), lossy only.
  final int filterSharpness;

  /// Loop filter type: 0 = simple, 1 = strong (default), lossy only.
  final int filterType;

  /// Number of macroblock segments (1..4), lossy only.
  final int segments;

  /// Number of entropy-analysis passes (1..10), lossy only.
  final int pass;

  /// Creates encoding options; unspecified values use libwebp's defaults.
  const WebpEncodeOptions({
    this.lossless = false,
    this.quality = 75,
    this.method = 4,
    this.alphaQuality = 100,
    this.alphaCompression = 1,
    this.alphaFiltering = AlphaFiltering.fast,
    this.exact = false,
    this.snsStrength = 50,
    this.filterStrength = 60,
    this.filterSharpness = 0,
    this.filterType = 1,
    this.segments = 4,
    this.pass = 1,
  });

  /// Creates options for a libwebp [preset] with the given [quality].
  factory WebpEncodeOptions.preset(WebpPreset preset, {double quality = 75}) {
    switch (preset) {
      case WebpPreset.picture:
        return WebpEncodeOptions(
          quality: quality,
          snsStrength: 80,
          filterSharpness: 4,
          filterStrength: 35,
        );
      case WebpPreset.photo:
        return WebpEncodeOptions(
          quality: quality,
          snsStrength: 80,
          filterSharpness: 3,
          filterStrength: 30,
        );
      case WebpPreset.drawing:
        return WebpEncodeOptions(
          quality: quality,
          snsStrength: 25,
          filterSharpness: 6,
          filterStrength: 10,
        );
      case WebpPreset.icon:
        return WebpEncodeOptions(
          quality: quality,
          snsStrength: 0,
          filterStrength: 0,
        );
      case WebpPreset.text:
        return WebpEncodeOptions(
          quality: quality,
          snsStrength: 0,
          filterStrength: 0,
          segments: 2,
        );
      case WebpPreset.defaultPreset:
        return WebpEncodeOptions(quality: quality);
    }
  }

  /// Returns a copy with some fields replaced.
  WebpEncodeOptions copyWith({
    bool? lossless,
    double? quality,
    int? method,
    int? alphaQuality,
    int? alphaCompression,
    AlphaFiltering? alphaFiltering,
    bool? exact,
    int? snsStrength,
    int? filterStrength,
    int? filterSharpness,
    int? filterType,
    int? segments,
    int? pass,
  }) => WebpEncodeOptions(
    lossless: lossless ?? this.lossless,
    quality: quality ?? this.quality,
    method: method ?? this.method,
    alphaQuality: alphaQuality ?? this.alphaQuality,
    alphaCompression: alphaCompression ?? this.alphaCompression,
    alphaFiltering: alphaFiltering ?? this.alphaFiltering,
    exact: exact ?? this.exact,
    snsStrength: snsStrength ?? this.snsStrength,
    filterStrength: filterStrength ?? this.filterStrength,
    filterSharpness: filterSharpness ?? this.filterSharpness,
    filterType: filterType ?? this.filterType,
    segments: segments ?? this.segments,
    pass: pass ?? this.pass,
  );
}

/// Encodes [image] as a WebP file (RIFF container).
///
/// Returns the complete file bytes. With [WebpEncodeOptions.lossless] a
/// `VP8L` bitstream is produced; otherwise a `VP8 ` bitstream, with a
/// `VP8X` + `ALPH` chunk pair when the image has transparency.
Uint8List encodeWebp(
  WebpImage image, {
  WebpEncodeOptions options = const WebpEncodeOptions(),
}) {
  if (image.width > 16383 || image.height > 16383) {
    throw ArgumentError('Image too large for WebP (max 16383x16383)');
  }
  if (options.lossless) {
    return _encodeLossless(image, options);
  }
  return _encodeLossy(image, options);
}

Uint8List _encodeLossless(WebpImage image, WebpEncodeOptions options) {
  final argb = image.toArgb();
  final hasAlpha = image.hasAlpha;
  final chunk = encodeVp8lChunk(
    argb,
    image.width,
    image.height,
    hasAlpha,
    Vp8lEncoderOptions(
      method: options.method.clamp(0, 6),
      quality: options.quality.round().clamp(0, 100),
      exact: options.exact,
    ),
  );
  final riff = RiffBuilder()..add('VP8L', chunk);
  return riff.build();
}

Uint8List _encodeLossy(WebpImage image, WebpEncodeOptions options) {
  final planes = rgbaToYuva(image.rgba, image.width, image.height);
  if (!options.exact) {
    cleanupTransparentArea(planes);
  }
  final config = Vp8EncoderConfig(
    quality: options.quality.clamp(0, 100),
    method: options.method.clamp(0, 6),
    snsStrength: options.snsStrength.clamp(0, 100),
    filterStrength: options.filterStrength.clamp(0, 100),
    filterSharpness: options.filterSharpness.clamp(0, 7),
    filterType: options.filterType.clamp(0, 1),
    segments: options.segments.clamp(1, 4),
    pass: options.pass.clamp(1, 10),
    exact: options.exact,
  );
  final vp8 = Vp8Encoder(planes, config).encode();
  final riff = RiffBuilder();
  final alphaPlane = planes.a;
  if (alphaPlane != null) {
    final alph = encodeAlphaChunk(
      alphaPlane,
      image.width,
      image.height,
      quality: options.alphaQuality.clamp(0, 100),
      method: options.alphaCompression.clamp(0, 1),
      filtering: options.alphaFiltering,
      effortLevel: options.method.clamp(0, 6),
    );
    riff.addVp8x(Vp8xFlags.alpha, image.width, image.height);
    riff.add('ALPH', alph);
  }
  riff.add('VP8 ', vp8);
  return riff.build();
}
