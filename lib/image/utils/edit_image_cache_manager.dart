import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/foundation.dart';

/// ✅ 편집 모드 전용 이미지 캐시 매니저
///
/// 목적:
/// - 글보기(리더) 캐시 정책과 분리해서, 편집 모드에서는 "짧게/가볍게" 캐시한다.
/// - 기존 노드 편집 진입 시(bytes 로드) 속도는 유지하되, 디스크 캐시가 과도하게 쌓이지 않게 한다.
/// - 서버에서 미발행 이미지가 30일 후 삭제되므로, 캐시 유효기간을 30일로 설정하여
///   서버에서 삭제된 이미지가 에러로 표시되도록 한다.
///
/// 정책:
/// - stalePeriod: 30일 (서버 이미지 삭제 정책과 동일하게 설정)
/// - maxNrOfCacheObjects: 60개 (초과 시 LRU 정리)
class EditImageCacheManager extends CacheManager {
  static const String key = 'editImageCache';
  static final EditImageCacheManager instance = EditImageCacheManager._();

  EditImageCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 60,
        ),
      );

  /// 특정 이미지 URL들의 캐시를 삭제 (발행 시 임시저장 관련 캐시 정리용)
  ///
  /// [imageUrls] - 삭제할 이미지 URL 목록
  Future<void> removeCachesForUrls(List<String> imageUrls) async {
    try {
      for (final url in imageUrls) {
        if (url.isEmpty ||
            (!url.startsWith('http://') && !url.startsWith('https://'))) {
          continue; // 네트워크 URL이 아니면 스킵
        }
        try {
          await removeFile(url);
          debugPrint('[EditImageCacheManager] ✅ 캐시 삭제 완료: $url');
        } catch (e) {
          debugPrint('[EditImageCacheManager] ⚠️ 캐시 삭제 실패: $url - $e');
        }
      }
    } catch (e) {
      debugPrint('[EditImageCacheManager] ❌ 캐시 삭제 중 오류: $e');
    }
  }
}
