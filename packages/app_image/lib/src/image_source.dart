import 'dart:typed_data';

/// Root image source definition
abstract class ImageSource {
  /// Image source from bytes
  factory ImageSource.bytes(Uint8List bytes) => _ImageSourceData(bytes);
}

class _ImageSourceData implements ImageSourceData, ImageSourceAsyncData {
  @override
  final Uint8List bytes;

  _ImageSourceData(this.bytes);

  @override
  Future<Uint8List> getBytes() async => bytes;
}

/// Create an image source from bytes
ImageSourceData imageSourceDataFromBytes(Uint8List bytes) =>
    ImageSource.bytes(bytes) as ImageSourceData;

/// Image source with data in it
abstract class ImageSourceData implements ImageSource {
  /// The bytes
  Uint8List get bytes;

  /// Image source from bytes
  factory ImageSourceData(Uint8List bytes) => _ImageSourceData(bytes);
}

/// Image source with async data in it
abstract class ImageSourceAsyncData implements ImageSource {
  /// Get the bytes
  Future<Uint8List> getBytes();
}
