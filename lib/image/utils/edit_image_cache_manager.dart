import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// ✅ 편집 모드 전용 이미지 캐시 매니저
///
/// 목적:
/// - 글보기(리더) 캐시 정책과 분리해서, 편집 모드에서는 "짧게/가볍게" 캐시한다.
/// - 기존 노드 편집 진입 시(bytes 로드) 속도는 유지하되, 디스크 캐시가 과도하게 쌓이지 않게 한다.
///
/// 정책(가볍게):
/// - stalePeriod: 3시간 (이후 재다운로드 가능)
/// - maxNrOfCacheObjects: 60개 (초과 시 LRU 정리)
class EditImageCacheManager extends CacheManager {
  static const String key = 'editImageCache';
  static final EditImageCacheManager instance = EditImageCacheManager._();

  EditImageCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(hours: 3),
          maxNrOfCacheObjects: 60,
        ),
      );
}
