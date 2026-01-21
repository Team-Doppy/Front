import 'package:doppy/editor/publish/service/post_publish_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:flutter/material.dart';

/// 포스트 내용 변경 감지 서비스
///
/// 수정 모드에서 원본 데이터와 현재 데이터를 비교하여
/// 실제 변경사항이 있는지 철저하게 확인합니다.
class ContentChangeDetector {
  /// ✅ exported(Map) 두 개를 직접 비교하여 본문(content/stickers) 변경 여부를 판단
  ///
  /// - PostExportScreen처럼 "에디터 서비스"가 없는 곳에서도 사용하기 위해 제공
  /// - 공개범위/썸네일/타이틀 등은 _deepEquals에서 무시되거나 별도 관리 대상이므로,
  ///   이 함수는 오직 content/stickers 구조 변경만 판단합니다.
  static bool hasExportedContentChanged({
    required Map<String, dynamic> originalExported,
    required Map<String, dynamic> currentExported,
  }) {
    try {
      debugPrint('[ContentChangeDetector] exported 직접 비교 시작');

      if (_hasDocumentStructureChanged(originalExported, currentExported)) {
        debugPrint('[ContentChangeDetector] ✓ 문서 구조 변경 감지(exported)');
        return true;
      }

      if (_hasStickersChanged(originalExported, currentExported)) {
        debugPrint('[ContentChangeDetector] ✓ 스티커 변경 감지(exported)');
        return true;
      }

      debugPrint('[ContentChangeDetector] ✗ 변경사항 없음(exported)');
      return false;
    } catch (e) {
      debugPrint('[ContentChangeDetector] exported 비교 에러: $e');
      return true;
    }
  }

  /// 포스트 내용이 변경되었는지 확인
  ///
  /// 다음 항목들을 모두 비교합니다:
  /// - 문서 구조 (노드 개수, 타입, 순서)
  /// - 텍스트 내용 (모든 문자, 공백 포함)
  /// - 텍스트 스타일 (폰트, 크기, 색상, bold, italic, underline 등)
  /// - 이미지 메타데이터 (URL, ID, width, height, alt 등)
  /// - 비디오 메타데이터 (URL, thumbnail 등)
  /// - 링크 메타데이터 (URL, title, description 등)
  /// - 스포일러 설정
  /// - 스티커 (위치, 크기, 타입, 내용)
  /// - 정렬 (align)
  /// - 제목 메타데이터
  ///
  /// 다음 항목들은 무시됩니다 (별도로 관리):
  /// - 공개범위 (accessLevel, visibility)
  static bool hasContentChanged({
    required Map<String, dynamic> originalExported,
    required EditorService editorService,
    required StickerService stickerService,
  }) {
    try {
      debugPrint('[ContentChangeDetector] 변경사항 검사 시작');

      // 1. 현재 에디터 상태를 export
      final currentExported = PostExporter.exportToMap(
        editorService: editorService,
        stickerService: stickerService,
      );

      // 2. 문서 구조 비교 (공개범위는 무시)
      if (_hasDocumentStructureChanged(originalExported, currentExported)) {
        debugPrint('[ContentChangeDetector] ✓ 문서 구조 변경 감지');
        return true;
      }

      // 3. 스티커 비교
      if (_hasStickersChanged(originalExported, currentExported)) {
        debugPrint('[ContentChangeDetector] ✓ 스티커 변경 감지');
        return true;
      }

      debugPrint('[ContentChangeDetector] ✗ 변경사항 없음');
      return false;
    } catch (e) {
      debugPrint('[ContentChangeDetector] 에러 발생: $e');
      // 에러 발생 시 안전하게 변경된 것으로 간주
      return true;
    }
  }

  // 헬퍼 함수들 제거 (블록 1:1 비교로 단순화)

  /// 문서 구조 및 내용 비교 (블록 단위 1:1 비교)
  static bool _hasDocumentStructureChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
  ) {
    final originalContent = original['content'] as Map<String, dynamic>?;
    final currentContent = current['content'] as Map<String, dynamic>?;

    if (originalContent == null || currentContent == null) {
      return originalContent != currentContent;
    }

    final originalNodes = originalContent['nodes'] as List?;
    final currentNodes = currentContent['nodes'] as List?;

    if (originalNodes == null || currentNodes == null) {
      return originalNodes != currentNodes;
    }

    // 노드 개수가 다르면 변경됨
    if (originalNodes.length != currentNodes.length) {
      debugPrint(
        '[ContentChangeDetector] 노드 개수 변경: ${originalNodes.length} → ${currentNodes.length}',
      );
      return true;
    }

    // 블록 단위 1:1 비교: deepEquals로 전체 비교
    if (!_deepEquals(originalNodes, currentNodes)) {
      debugPrint('[ContentChangeDetector] 노드 내용 변경 감지 (1:1 비교)');

      // 디버깅용: 어느 노드가 바뀌었는지 출력
      for (int i = 0; i < originalNodes.length; i++) {
        if (!_deepEquals(originalNodes[i], currentNodes[i])) {
          debugPrint('[ContentChangeDetector] 노드[$i] 변경됨');
          debugPrint('  원본: ${originalNodes[i]}');
          debugPrint('  현재: ${currentNodes[i]}');
          break; // 첫 번째 변경만 출력
        }
      }
      return true;
    }

    return false;
  }

  // 개별 노드 비교 함수들은 제거 (블록 단위 1:1 비교로 대체)

  /// 스티커 비교 (정규화 후 비교)
  static bool _hasStickersChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
  ) {
    // 🎯 content 안의 stickers를 추출
    final originalContent = original['content'] as Map<String, dynamic>?;
    final currentContent = current['content'] as Map<String, dynamic>?;

    final originalStickers = originalContent?['stickers'] as List?;
    final currentStickers = currentContent?['stickers'] as List?;

    debugPrint('[ContentChangeDetector] 🔍 스티커 비교 (content.stickers)');
    debugPrint('  원본 스티커: ${originalStickers?.length ?? 0}개');
    debugPrint('  현재 스티커: ${currentStickers?.length ?? 0}개');

    // 둘 다 null이거나 빈 리스트면 변경 없음
    if ((originalStickers == null || originalStickers.isEmpty) &&
        (currentStickers == null || currentStickers.isEmpty)) {
      debugPrint('[ContentChangeDetector] ✗ 스티커 변경 없음 (둘 다 비어있음)');
      return false;
    }

    // 하나만 null이거나 빈 리스트면 변경됨
    if (originalStickers == null ||
        originalStickers.isEmpty ||
        currentStickers == null ||
        currentStickers.isEmpty) {
      debugPrint('[ContentChangeDetector] ✓ 스티커 변경 감지 (개수 차이)');
      return true;
    }

    // 개수가 다르면 변경됨
    if (originalStickers.length != currentStickers.length) {
      debugPrint(
        '[ContentChangeDetector] ✓ 스티커 변경 감지 (개수: ${originalStickers.length} → ${currentStickers.length})',
      );
      return true;
    }

    // 각 스티커를 정규화하여 비교
    try {
      final normalizedOriginal = _normalizeStickers(originalStickers);
      final normalizedCurrent = _normalizeStickers(currentStickers);

      if (!_deepEquals(normalizedOriginal, normalizedCurrent)) {
        debugPrint('[ContentChangeDetector] ✓ 스티커 변경 감지 (내용 차이)');
        return true;
      }

      debugPrint('[ContentChangeDetector] ✗ 스티커 변경 없음');
      return false;
    } catch (e, stackTrace) {
      debugPrint('[ContentChangeDetector] ❌ 스티커 비교 에러: $e');
      debugPrint('  스택 트레이스: $stackTrace');
      // 에러 발생 시 안전하게 변경된 것으로 간주
      return true;
    }
  }

  /// 스티커 데이터 정규화 (기본값 채우기, 메타데이터 포함)
  static List<Map<String, dynamic>> _normalizeStickers(List stickers) {
    return stickers.map((sticker) {
      if (sticker is! Map<String, dynamic>) {
        return <String, dynamic>{};
      }

      final normalized = <String, dynamic>{};

      // 필수 필드
      normalized['id'] = sticker['id'];
      normalized['type'] = sticker['type'];

      // 메타데이터 필드 (기본값 채우기)
      normalized['scale'] = (sticker['scale'] as num?)?.toDouble() ?? 1.0;
      normalized['zIndex'] = (sticker['zIndex'] as num?)?.toInt() ?? 0;
      normalized['opacity'] = (sticker['opacity'] as num?)?.toDouble() ?? 1.0;
      normalized['rotation'] = (sticker['rotation'] as num?)?.toDouble() ?? 0.0;

      // content 필드 (URL 등)
      if (sticker['content'] != null) {
        normalized['content'] = sticker['content'];
      }

      // 위치 정보: anchor와 positionFallback 모두 비교
      final anchor = sticker['anchor'] as Map<String, dynamic>?;
      final positionFallback =
          sticker['positionFallback'] as Map<String, dynamic>?;

      if (anchor != null) {
        // anchor 정보 정규화
        normalized['anchor'] = {
          'nodeId': anchor['nodeId'],
          'localX': (anchor['localX'] as num?)?.toDouble(),
          'localY': (anchor['localY'] as num?)?.toDouble(),
          'refW': (anchor['refW'] as num?)?.toDouble(),
        };
      } else {
        // anchor가 null이면 null로 명시적으로 저장
        normalized['anchor'] = null;
      }

      if (positionFallback != null) {
        // positionFallback 정보 정규화
        normalized['positionFallback'] = {
          'xPx': (positionFallback['xPx'] as num?)?.toDouble(),
          'yPx': (positionFallback['yPx'] as num?)?.toDouble(),
          'docWidth': (positionFallback['docWidth'] as num?)?.toDouble(),
        };
      } else {
        // positionFallback이 null이면 null로 명시적으로 저장
        normalized['positionFallback'] = null;
      }

      return normalized;
    }).toList();
  }

  /// Deep equality 비교 (재귀적으로 Map, List 비교, 정규화 포함)
  static bool _deepEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;

    if (a is Map && b is Map) {
      // 무시할 키 목록 (서버/클라이언트 차이로 인한 false positive 방지)
      // 공개범위 및 그룹 공유 관련 키는 변경 감지에서 제외 (별도로 관리)
      const ignoredKeys = {
        'title',
        'isliked', // 클라이언트가 자동 추가
        'hasComments', // 서버에서만 제공 (댓글 존재 여부)
        'commentCount', // 서버에서만 제공 (댓글 개수)
        'likeCount', // 서버에서만 제공 (좋아요 개수)
        'viewCount', // 서버에서만 제공 (조회수)
        'isLiked', // 서버에서만 제공 (좋아요 여부)
        'createdAt', // 서버에서만 제공 (생성 시간)
        'updatedAt', // 서버에서만 제공 (수정 시간)
        'author', // 서버에서만 제공 (작성자)
        'position', // 서버에서만 제공 (순서)
        'id', // 노드 ID는 변경 여부와 무관 (순서만 중요)
        'accessLevel', // 공개 범위 - 변경 감지에서 제외
        'visibility', // 공개 범위 - 변경 감지에서 제거
        'thumbnailImageUrl', // 서버에서만 제공 (썸네일 URL) - 별도로 관리
        'summary', // 서버에서만 제공 (요약) - 별도로 관리
        'authorProfileImageUrl', // 서버에서만 제공 (작성자 프로필 이미지 URL) - 별도로 관리
        'spoiler', // 별도 비교 (키 없음 = false)
      };

      final aKeys = a.keys.where((k) => !ignoredKeys.contains(k)).toSet();
      final bKeys = b.keys.where((k) => !ignoredKeys.contains(k)).toSet();

      // spoiler 별도 비교 (키 없음/false/null을 모두 false로 취급)
      final aSpoiler = a['spoiler'] == true;
      final bSpoiler = b['spoiler'] == true;
      if (aSpoiler != bSpoiler) return false;

      // 키 개수가 다르면 (무시 키 제외)
      if (aKeys.length != bKeys.length) return false;

      for (final key in aKeys) {
        if (!bKeys.contains(key)) return false;

        final aVal = a[key];
        final bVal = b[key];

        // 특정 키에 대한 정규화
        if (key == 'align' || key == 'padding') {
          // null과 'center'를 동일하게 취급
          final aNorm = aVal?.toString() ?? 'center';
          final bNorm = bVal?.toString() ?? 'center';
          if (aNorm != bNorm) return false;
          continue;
        }

        if (key == 'fontFamily') {
          // null과 ''를 동일하게 취급
          final aNorm = aVal?.toString().trim() ?? '';
          final bNorm = bVal?.toString().trim() ?? '';
          if (aNorm != bNorm) return false;
          continue;
        }

        if (!_deepEquals(aVal, bVal)) return false;
      }

      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) return false;

      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }

      return true;
    }

    // 숫자 타입 비교 (double vs int 처리)
    if (a is num && b is num) {
      return (a - b).abs() < 0.0001; // 부동소수점 오차 허용
    }

    return a == b;
  }

  /// 변경된 필드 목록 반환 (디버깅용)
  static List<String> getChangedFields({
    required Map<String, dynamic> originalExported,
    required EditorService editorService,
    required StickerService stickerService,
  }) {
    final changes = <String>[];

    try {
      final currentExported = PostExporter.exportToMap(
        editorService: editorService,
        stickerService: stickerService,
      );

      // 문서 구조
      if (_hasDocumentStructureChanged(originalExported, currentExported)) {
        changes.add('문서 내용');
      }

      // 스티커
      if (_hasStickersChanged(originalExported, currentExported)) {
        changes.add('스티커');
      }
    } catch (e) {
      changes.add('비교 오류: $e');
    }

    return changes;
  }
}
