// ignore_for_file: avoid_print

// Reads the size of an image then makes a jpeg thumbnail of its left half.
// Runs on the Dart VM (`dart run example/main.dart`, package:image) and on
// the web (the browser canvas).
import 'package:tekartik_app_image/app_image_placeholder.dart';
import 'package:tekartik_app_image_web/app_image_web.dart';
import 'package:tekartik_app_image_web/image_decoder.dart';

Future<void> main() async {
  // A 640x480 red png: use any jpg, png or webp bytes (a picked file, a
  // download...).
  var source = await generatePlaceholderImage(
    width: 640,
    height: 480,
    color: 0xFFFF0000,
    encoding: const ImageEncodingPng(),
  );
  var meta = await getImageMetaFromBytes(source.bytes);
  print('source: ${meta.width}x${meta.height} ${meta.encoding}');

  // The left half, 160 pixels wide, the height from the crop ratio (240).
  var thumbnail = await resizeTo(
    source.bytes,
    options: ResizeOptions(
      width: 160,
      height: null,
      cropRect: CropRect.fromLTWH(0, 0, 320, 480),
      encoding: ImageEncodingJpg(quality: 80),
    ),
  );
  print(
    'thumbnail: ${thumbnail.width}x${thumbnail.height} '
    '${thumbnail.encoding} ${thumbnail.bytes.length} bytes',
  );
}
