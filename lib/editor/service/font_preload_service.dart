import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../editor/data/font.dart';
import '../../editor/style/font_catalog.dart';

/// 폰트 미리 로드 서비스
/// 에디터 초기화 시 폰트를 미리 로드하여 폰트 오버레이 열 때 즉시 적용 가능하도록 함
class FontPreloadService {
  static final FontPreloadService _instance = FontPreloadService._internal();
  factory FontPreloadService() => _instance;
  FontPreloadService._internal();

  final Set<String> _preloadedFonts = {}; // 로드된 폰트 식별자 저장
  bool _isPreloading = false;

  /// 폰트가 미리 로드되었는지 확인
  bool isPreloaded(String identifier) {
    return _preloadedFonts.contains(identifier);
  }

  /// 우선순위 폰트 미리 로드 (비동기, 백그라운드에서 병렬 처리)
  /// - 현재 사용 중인 폰트
  /// - 즐겨찾기 폰트
  /// - 손글씨, 산세리프 카테고리의 인기 폰트
  Future<void> preloadPriorityFonts({
    String? currentFontIdentifier,
    List<String>? favoriteIdentifiers,
  }) async {
    if (_isPreloading) {
      debugPrint('[FontPreloadService] 이미 프리로드 중입니다');
      return;
    }

    _isPreloading = true;

    try {
      // 1. 우선순위 폰트 목록 생성
      final Set<FontItem> priorityFonts = {};

      // 현재 사용 중인 폰트
      if (currentFontIdentifier != null && currentFontIdentifier.isNotEmpty) {
        final currentFont = FontCatalog.findByIdentifier(currentFontIdentifier);
        if (currentFont != null) {
          priorityFonts.add(currentFont);
        }
      }

      // 즐겨찾기 폰트
      if (favoriteIdentifiers != null && favoriteIdentifiers.isNotEmpty) {
        for (final id in favoriteIdentifiers) {
          final font = FontCatalog.findByIdentifier(id);
          if (font != null) {
            priorityFonts.add(font);
          }
        }
      }

      // 손글씨 카테고리 상위 폰트 (최대 15개)
      final handwritingFonts = FontCatalog.getByCategory('손글씨').take(15);
      priorityFonts.addAll(handwritingFonts);

      // 산세리프 카테고리 상위 폰트 (최대 15개)
      final sansSerifFonts = FontCatalog.getByCategory('산세리프').take(15);
      priorityFonts.addAll(sansSerifFonts);

      // 2. 병렬로 폰트 로드 (최대 동시 10개)
      final fontsToLoad = priorityFonts
          .where((f) => f.googleFont != null)
          .toList();
      final batchSize = 10;

      for (int i = 0; i < fontsToLoad.length; i += batchSize) {
        // UI 스레드가 블로킹되지 않도록 다음 프레임으로 미루기
        await Future.delayed(Duration.zero);

        final batch = fontsToLoad.skip(i).take(batchSize).toList();

        // 배치 내 폰트들을 병렬로 로드
        await Future.wait(
          batch.map((font) async {
            try {
              if (!_preloadedFonts.contains(font.identifier)) {
                // Google Fonts 실제 로드 (캐시 활성화)
                await font.googleFont!(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                );
                // 폰트 이름으로도 로드 시도 (더 확실한 캐싱)
                try {
                  await GoogleFonts.pendingFonts([font.displayName]);
                } catch (_) {}

                _preloadedFonts.add(font.identifier);
                debugPrint(
                  '[FontPreloadService] ✅ 폰트 로드 완료: ${font.displayName}',
                );
              }
            } catch (e) {
              debugPrint(
                '[FontPreloadService] ⚠️ 폰트 로드 실패: ${font.displayName} - $e',
              );
            }
          }),
          eagerError: false, // 하나 실패해도 계속 진행
        );

        // 배치 간 짧은 딜레이 (UI 업데이트 기회 제공)
        if (i + batchSize < fontsToLoad.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      debugPrint(
        '[FontPreloadService] ✅ 우선순위 폰트 프리로드 완료: ${_preloadedFonts.length}개',
      );
    } catch (e) {
      debugPrint('[FontPreloadService] ❌ 폰트 프리로드 오류: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// 특정 폰트 즉시 로드
  Future<void> preloadFont(FontItem font) async {
    if (_preloadedFonts.contains(font.identifier)) {
      return; // 이미 로드됨
    }

    if (font.googleFont == null) {
      _preloadedFonts.add(font.identifier);
      return; // Google Font가 아닌 경우 즉시 완료
    }

    try {
      await font.googleFont!(fontWeight: FontWeight.w400, fontSize: 14);
      try {
        await GoogleFonts.pendingFonts([font.displayName]);
      } catch (_) {}
      _preloadedFonts.add(font.identifier);
      debugPrint('[FontPreloadService] ✅ 폰트 로드 완료: ${font.displayName}');
    } catch (e) {
      debugPrint('[FontPreloadService] ⚠️ 폰트 로드 실패: ${font.displayName} - $e');
    }
  }

  /// 모든 폰트 프리로드 (선택적, 백그라운드에서 처리)
  Future<void> preloadAllFonts() async {
    if (_isPreloading) return;

    _isPreloading = true;

    try {
      final googleFonts = FontCatalog.all
          .where((f) => f.googleFont != null)
          .toList();
      final batchSize = 10;

      for (int i = 0; i < googleFonts.length; i += batchSize) {
        final batch = googleFonts.skip(i).take(batchSize).toList();

        await Future.wait(
          batch.map((font) async {
            if (!_preloadedFonts.contains(font.identifier)) {
              try {
                await font.googleFont!(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                );
                try {
                  await GoogleFonts.pendingFonts([font.displayName]);
                } catch (_) {}
                _preloadedFonts.add(font.identifier);
              } catch (_) {}
            }
          }),
          eagerError: false,
        );

        if (i + batchSize < googleFonts.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } catch (e) {
      debugPrint('[FontPreloadService] ❌ 전체 폰트 프리로드 오류: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// 로드된 폰트 목록 초기화
  void clearPreloadedFonts() {
    _preloadedFonts.clear();
  }
}
