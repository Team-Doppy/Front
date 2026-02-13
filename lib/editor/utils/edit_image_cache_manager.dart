import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 에디터 이미지 캐시 매니저
///
/// 메인 에디터와 드래그 오버레이에서 동일한 이미지 캐시를 공유합니다.
class EditImageCacheManager {
  EditImageCacheManager._();

  /// 싱글톤 인스턴스
  static final CacheManager instance = CacheManager(
    Config(
      'editImageCache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: 'editImageCache.db'),
    ),
  );
}
