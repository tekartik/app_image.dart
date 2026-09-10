import 'dart:typed_data';

import 'riff.dart';
import 'vp8/alpha.dart';
import 'vp8/vp8_decoder.dart';
import 'vp8/yuv.dart';
import 'vp8l/vp8l_decoder.dart';
import 'webp_image.dart';

/// Reads the header information of a WebP file without decoding pixels.
///
/// [bytes] is the whole file. Throws [WebpFormatException] on invalid data.
WebpInfo webpInfo(Uint8List bytes) {
  final container = WebpContainer.parse(bytes);
  final flags = container.vp8xFlags;
  final isExtended = container.isExtended;
  final hasAnimation = isExtended && (flags & Vp8xFlags.animation) != 0;
  final vp8 = container.find('VP8 ');
  final vp8l = container.find('VP8L');
  final alph = container.find('ALPH');
  WebpInfo? bitstream;
  if (vp8l != null) {
    bitstream = Vp8lDecoder.readInfo(vp8l.data);
  } else if (vp8 != null) {
    bitstream = Vp8Decoder.readInfo(vp8.data);
  } else if (!hasAnimation) {
    throw WebpFormatException('No VP8/VP8L bitstream found');
  }
  final width = isExtended ? container.canvasWidth : bitstream!.width;
  final height = isExtended ? container.canvasHeight : bitstream!.height;
  final hasAlpha =
      (isExtended && (flags & Vp8xFlags.alpha) != 0) ||
      alph != null ||
      (bitstream?.hasAlpha ?? false);
  return WebpInfo(
    width: width,
    height: height,
    hasAlpha: hasAlpha,
    hasAnimation: hasAnimation,
    isExtended: isExtended,
    format: bitstream?.format,
    hasIccProfile: container.find('ICCP') != null,
    hasExif: container.find('EXIF') != null,
    hasXmp: container.find('XMP ') != null,
  );
}

/// Decodes a still WebP image (lossy or lossless, with optional alpha).
///
/// [bytes] is the whole file (RIFF container). Animated files are not
/// supported and throw [WebpFormatException].
WebpImage decodeWebp(Uint8List bytes) {
  final container = WebpContainer.parse(bytes);
  if (container.isExtended &&
      (container.vp8xFlags & Vp8xFlags.animation) != 0) {
    throw WebpFormatException('Animated WebP is not supported');
  }
  final vp8l = container.find('VP8L');
  if (vp8l != null) {
    return decodeVp8lChunk(vp8l.data);
  }
  final vp8 = container.find('VP8 ');
  if (vp8 == null) {
    throw WebpFormatException('No VP8/VP8L bitstream found');
  }
  final alph = container.find('ALPH');
  return decodeVp8Chunk(vp8.data, alph?.data);
}

/// Decodes a raw `VP8L` chunk payload.
WebpImage decodeVp8lChunk(Uint8List data) {
  final dec = Vp8lDecoder(data);
  final argb = dec.decode();
  final rgba = Uint8List(dec.width * dec.height * 4);
  for (var i = 0, j = 0; i < argb.length; i++, j += 4) {
    final p = argb[i];
    rgba[j] = (p >>> 16) & 0xff;
    rgba[j + 1] = (p >>> 8) & 0xff;
    rgba[j + 2] = p & 0xff;
    rgba[j + 3] = (p >>> 24) & 0xff;
  }
  return WebpImage(dec.width, dec.height, rgba);
}

/// Decodes a raw `VP8 ` chunk payload, with an optional `ALPH` payload.
WebpImage decodeVp8Chunk(Uint8List data, [Uint8List? alphaData]) {
  final dec = Vp8Decoder(data);
  dec.decode();
  final width = dec.width;
  final height = dec.height;
  final rgba = yuvToRgba(
    dec.yPlane,
    dec.yStride,
    dec.uPlane,
    dec.vPlane,
    dec.uvStride,
    width,
    height,
  );
  if (alphaData != null) {
    final alpha = decodeAlphaChunk(alphaData, width, height);
    for (var i = 0, j = 3; i < alpha.length; i++, j += 4) {
      rgba[j] = alpha[i];
    }
  }
  return WebpImage(width, height, rgba);
}
