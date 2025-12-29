import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// ✅ 읽기(Home/Reader) 전용 이미지 디스크 캐시 매니저
///
/// 목적:
/// - 홈/리더에서 "재진입/토글/스와이프" 시 이미지 재로딩(네트워크/디코드)을 줄인다.
/// - 편집(Edit) 모드 캐시 정책과 분리하여, 용량/만료 정책을 읽기에 맞게 가져간다.
///
/// 정책(보수적):
/// - stalePeriod: 7일 (상대적으로 재방문이 많은 읽기 특성 반영)
/// - maxNrOfCacheObjects: 300개 (초과 시 LRU 정리)
class ReadImageCacheManager extends CacheManager {
  static const String key = 'readImageCache';
  static final ReadImageCacheManager instance = ReadImageCacheManager._();

  ReadImageCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 300,
        ),
      );

  /// 읽기 이미지 디스크 캐시를 비운다.
  ///
  /// - 로그아웃/계정 전환 시 "다른 계정 이미지 섞임"을 막기 위한 용도
  /// - 설정 화면에서 사용자가 수동으로 "캐시 삭제"를 누르는 용도
  static Future<void> purge() async {
    try {
      await instance.emptyCache();
    } catch (_) {
      // best-effort
    }
  }
}
