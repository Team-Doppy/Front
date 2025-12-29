import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'package:doppy/image/utils/read_image_cache_manager.dart';
import 'package:doppy/utils/image_size_utils.dart';

/// 읽기(Home/Reader) 영역에서 사용하는 ImageProvider 생성 유틸.
///
/// - 네트워크 이미지는 디스크 캐시(CachedNetworkImageProvider + ReadImageCacheManager) 사용
/// - 로컬 파일은 FileImage 사용
/// - 메모리 점유/디코드 비용을 줄이기 위해 필요 시 ResizeImage(width) 적용
class ReadImageProvider {
  static String normalizeUrl(String url) {
    if (url.startsWith('file://')) return url.substring(7);
    return url;
  }

  static ImageProvider build({required String url, int? decodeWidth}) {
    final isLocal = ImageSizeUtils.isLocalPath(url);

    final ImageProvider base;
    if (isLocal) {
      base = FileImage(File(normalizeUrl(url)));
    } else {
      base = CachedNetworkImageProvider(
        url,
        cacheManager: ReadImageCacheManager.instance,
      );
    }

    return decodeWidth != null ? ResizeImage(base, width: decodeWidth) : base;
  }
}
