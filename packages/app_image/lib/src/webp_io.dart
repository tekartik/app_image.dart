import 'dart:io';
import 'dart:math';

import 'package:dev_build/shell.dart';
import 'package:image/image.dart';
import 'package:path/path.dart';
import 'package:tekartik_common_utils/size/int_size.dart';

/// Webp options
class WebpOptions {
  /// Lossless
  final bool lossless;

  /// Quality (0 to 100)
  final int quality;

  /// Alpha quality (0 to 100)
  final int alphaQuality;

  /// Default is quality 50
  WebpOptions({
    this.lossless = false,
    this.quality = 50,
    this.alphaQuality = 100,
  });
}

/// Quality medium
var webpOptionsQuality50 = WebpOptions(quality: 50);

/// Quality ok
var webpOptionsQuality75 = WebpOptions(quality: 75);

/// Lossless
var webpOptionsLossless = WebpOptions(lossless: true);

Future _convertFileToWebp(
  String src,
  String dst, {
  WebpOptions? options,
}) async {
  options ??= WebpOptions();
  if (!options.lossless) {
    await run(
      'cwebp -q ${options.quality} -alpha_q ${options.alphaQuality} ${shellArgument(src)} -o ${shellArgument(dst)}',
    );
  } else {
    await run('cwebp -lossless ${shellArgument(src)} -o ${shellArgument(dst)}');
  }
}

var _tmpDir = Directory.systemTemp.createTempSync('image_io_utils').path;

/// Copy a file, resize and convert to webp
Future<void> fileCopyToWebp(
  String src,
  String dst, {
  Rect? cropRect,
  int? resizeWidth,
  WebpOptions? options,
  bool? ifNotExists,
}) async {
  ifNotExists ??= false;
  options ??= WebpOptions();
  if (ifNotExists) {
    if (File(dst).existsSync()) {
      // ok
      return;
    }
  }

  var image = decodeImage(await File(src).readAsBytes())!;
  if (cropRect != null) {
    image = copyCrop(
      image,
      x: cropRect.left,
      y: cropRect.top,
      width: cropRect.width,
      height: cropRect.height,
    );
    if (image.width != cropRect.width || image.height != cropRect.height) {
      var toImage = Image(
        width: cropRect.width,
        height: cropRect.height,
        format: image.format,
        numChannels: 4,
      );
      copyExpandCanvas(
        image,
        newWidth: cropRect.width,
        newHeight: cropRect.height,
        toImage: toImage,
      );
      image = toImage;
    }
  }
  if (resizeWidth != null) {
    var ratio = image.width / image.height;
    image = copyResize(
      image,
      width: max(1, resizeWidth),
      height: max(1, (resizeWidth / ratio).round()),
      interpolation: Interpolation.average,
    );
  }
  var pngTile = join(_tmpDir, '${basenameWithoutExtension(src)}.png');
  await fileWritePng(pngTile, image, force: true);
  // Ensure parent exists
  File(dst).parent.createSync(recursive: true);
  await _convertFileToWebp(pngTile, dst, options: options);
}

/// Png options
class PngOptions {
  /// Level
  final int level;

  /// Default is quality 6
  PngOptions({this.level = 6});
}

///
/// Write png conditionnally
Future<void> fileWritePng(
  String path,
  Image image, {
  bool force = false,
  PngOptions? options,
}) async {
  var file = File(path);
  if (!file.existsSync() || force) {
    await file.writeAsBytes(
      encodePng(image, level: (options ?? PngOptions()).level),
    );
  }
}
