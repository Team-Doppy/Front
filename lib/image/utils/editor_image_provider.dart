import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'package:doppy/image/utils/edit_image_cache_manager.dart';
import 'package:doppy/image/utils/edit_image_provider_registry.dart';
import 'package:doppy/image/utils/read_image_provider.dart';
import 'package:doppy/utils/image_size_utils.dart';

class EditorImageProviderResult {
  const EditorImageProviderResult({
    required this.isLocal,
    required this.baseProvider,
    required this.effectiveProvider,
  });

  final bool isLocal;
  final ImageProvider baseProvider;
  final ImageProvider effectiveProvider;
}

/// Editor에서 사용하는 이미지 provider 생성 로직을 한 곳으로 모은 유틸.
///
/// 목표:
/// - Single/Row/PageView에서 중복되는 provider 분기(File/Network/Cached) 제거
/// - ResizeImage(width) 정책을 통일해서 변환(Row ↔ Single ↔ PageView) 시 캐시 재사용률을 높임
/// - EditImageProviderRegistry에 항상 기록해서 split/merge 시 깜빡임을 최소화
class EditorImageProvider {
  static int? editingDecodeWidth(BuildContext context, double screenWidth) {
    final dpr = View.of(context).devicePixelRatio;
    final v = (screenWidth * dpr).round();
    return v.clamp(1, 1000000);
  }

  static String normalizeUrl(String url) {
    if (url.startsWith('file://')) return url.substring(7);
    return url;
  }

  static EditorImageProviderResult build({
    required String url,
    required bool isEditing,
    int? decodeWidth,
  }) {
    final isLocal = ImageSizeUtils.isLocalPath(url);

    final ImageProvider base;
    if (isLocal) {
      base = FileImage(File(normalizeUrl(url)));
    } else {
      base =
          isEditing
              ? CachedNetworkImageProvider(
                url,
                cacheManager: EditImageCacheManager.instance,
              )
              : ReadImageProvider.build(url: url);
    }

    // split/merge, localPath ↔ networkUrl 상황에서 provider 재사용을 높이기 위해 레지스트리에 기록
    EditImageProviderRegistry.set(url, base);

    final effective =
        decodeWidth != null ? ResizeImage(base, width: decodeWidth) : base;

    return EditorImageProviderResult(
      isLocal: isLocal,
      baseProvider: base,
      effectiveProvider: effective,
    );
  }
}
