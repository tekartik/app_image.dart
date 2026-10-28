/// App image information
library;

export 'src/constant.dart'
    show
        mimeTypeJpg,
        mimeTypePng,
        extensionPng,
        extensionJpg,
        mimeTypeWebp,
        extensionWebp;

export 'src/encoding.dart'
    show
        ImageEncoding,
        ImageEncodingJpg,
        ImageEncodingPng,
        ImageEncodingWebp,
        imageEncodingJpgQualityUnknown,
        imageEncodingWebpQualityUnknown,
        imageEncodingWebpQualityDefault;
export 'src/image_result.dart' show ImageData, ImageMeta;
export 'src/image_source.dart'
    show ImageSourceData, ImageSourceAsyncData, ImageSource;
