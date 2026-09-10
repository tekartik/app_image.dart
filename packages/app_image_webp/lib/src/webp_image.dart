import 'dart:typed_data';

/// Error thrown when WebP data cannot be parsed or is not supported.
class WebpFormatException implements FormatException {
  @override
  final String message;

  @override
  final dynamic source;

  @override
  final int? offset;

  /// Creates a format exception with a human readable [message].
  ///
  /// [source] and [offset] are optional and follow [FormatException].
  WebpFormatException(this.message, [this.source, this.offset]);

  @override
  String toString() => 'WebpFormatException: $message';
}

/// A decoded (or to-be-encoded) raster image with 8-bit RGBA pixels.
///
/// Pixels are stored row-major in [rgba], 4 bytes per pixel in the order
/// red, green, blue, alpha. Alpha is straight (not premultiplied).
class WebpImage {
  /// Image width in pixels (1..16383).
  final int width;

  /// Image height in pixels (1..16383).
  final int height;

  /// Pixel data, `width * height * 4` bytes, RGBA order, row-major.
  final Uint8List rgba;

  /// Creates an image from existing [rgba] pixel data.
  ///
  /// [rgba] must have exactly `width * height * 4` bytes.
  WebpImage(this.width, this.height, this.rgba) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid image size ${width}x$height');
    }
    if (rgba.length != width * height * 4) {
      throw ArgumentError(
        'rgba length ${rgba.length} does not match ${width}x$height*4',
      );
    }
  }

  /// Creates an opaque black image (all channels 0, alpha 255).
  factory WebpImage.blank(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var i = 3; i < rgba.length; i += 4) {
      rgba[i] = 255;
    }
    return WebpImage(width, height, rgba);
  }

  /// Creates an image from RGB pixel data (3 bytes per pixel), opaque.
  factory WebpImage.fromRgb(int width, int height, List<int> rgb) {
    if (rgb.length != width * height * 3) {
      throw ArgumentError('rgb length ${rgb.length} does not match size');
    }
    final rgba = Uint8List(width * height * 4);
    var j = 0;
    for (var i = 0; i < rgb.length; i += 3) {
      rgba[j++] = rgb[i];
      rgba[j++] = rgb[i + 1];
      rgba[j++] = rgb[i + 2];
      rgba[j++] = 255;
    }
    return WebpImage(width, height, rgba);
  }

  /// Number of pixels (`width * height`).
  int get pixelCount => width * height;

  /// True if any pixel has an alpha value different from 255.
  bool get hasAlpha {
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) return true;
    }
    return false;
  }

  /// Returns the pixel at ([x], [y]) packed as 0xAARRGGBB.
  int getPixel(int x, int y) {
    final i = (y * width + x) * 4;
    return ((rgba[i + 3] << 24) |
            (rgba[i] << 16) |
            (rgba[i + 1] << 8) |
            rgba[i + 2]) >>>
        0;
  }

  /// Sets the pixel at ([x], [y]) from an 0xAARRGGBB packed value.
  void setPixel(int x, int y, int argb) {
    final i = (y * width + x) * 4;
    rgba[i] = (argb >> 16) & 0xff;
    rgba[i + 1] = (argb >> 8) & 0xff;
    rgba[i + 2] = argb & 0xff;
    rgba[i + 3] = (argb >> 24) & 0xff;
  }

  /// Sets the pixel at ([x], [y]) from separate channel values (0..255).
  void setRgba(int x, int y, int r, int g, int b, [int a = 255]) {
    final i = (y * width + x) * 4;
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }

  /// Returns the pixels as a list of 0xAARRGGBB values (row-major).
  Uint32List toArgb() {
    final out = Uint32List(width * height);
    for (var i = 0, j = 0; i < out.length; i++, j += 4) {
      out[i] =
          (rgba[j + 3] << 24) |
          (rgba[j] << 16) |
          (rgba[j + 1] << 8) |
          rgba[j + 2];
    }
    return out;
  }

  /// Creates an image from a list of 0xAARRGGBB values (row-major).
  factory WebpImage.fromArgb(int width, int height, List<int> argb) {
    if (argb.length != width * height) {
      throw ArgumentError('argb length ${argb.length} does not match size');
    }
    final rgba = Uint8List(width * height * 4);
    for (var i = 0, j = 0; i < argb.length; i++, j += 4) {
      final p = argb[i];
      rgba[j] = (p >> 16) & 0xff;
      rgba[j + 1] = (p >> 8) & 0xff;
      rgba[j + 2] = p & 0xff;
      rgba[j + 3] = (p >> 24) & 0xff;
    }
    return WebpImage(width, height, rgba);
  }

  /// Returns a deep copy of this image.
  WebpImage clone() => WebpImage(width, height, Uint8List.fromList(rgba));

  @override
  String toString() => 'WebpImage(${width}x$height)';
}

/// The bitstream flavor used by a WebP file.
enum WebpFormat {
  /// Lossy VP8 bitstream (`VP8 ` chunk).
  lossy,

  /// Lossless VP8L bitstream (`VP8L` chunk).
  lossless,
}

/// Header information about a WebP file, obtained without decoding pixels.
class WebpInfo {
  /// Canvas width in pixels.
  final int width;

  /// Canvas height in pixels.
  final int height;

  /// True if the file declares (or contains) an alpha channel.
  final bool hasAlpha;

  /// True if the file is an animation (`ANIM`/`ANMF` chunks).
  final bool hasAnimation;

  /// True if the file uses the extended `VP8X` container.
  final bool isExtended;

  /// Bitstream format of the (first) image, null for animations without
  /// a top-level bitstream.
  final WebpFormat? format;

  /// True if an ICC color profile chunk (`ICCP`) is present.
  final bool hasIccProfile;

  /// True if an `EXIF` metadata chunk is present.
  final bool hasExif;

  /// True if an `XMP ` metadata chunk is present.
  final bool hasXmp;

  /// Creates a header description; normally obtained via `webpInfo`.
  WebpInfo({
    required this.width,
    required this.height,
    required this.hasAlpha,
    this.hasAnimation = false,
    this.isExtended = false,
    this.format,
    this.hasIccProfile = false,
    this.hasExif = false,
    this.hasXmp = false,
  });

  /// True if the bitstream is lossless (VP8L).
  bool get isLossless => format == WebpFormat.lossless;

  @override
  String toString() =>
      'WebpInfo(${width}x$height, ${format?.name ?? 'none'}'
      '${hasAlpha ? ', alpha' : ''}${hasAnimation ? ', animated' : ''})';
}
