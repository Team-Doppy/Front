import 'dart:convert';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/publish/post_exporter.dart';

/// 포스트 내용 변경 감지 서비스
///
/// 수정 모드에서 원본 데이터와 현재 데이터를 비교하여
/// 실제 변경사항이 있는지 철저하게 확인합니다.
class ContentChangeDetector {
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
  static bool hasContentChanged({
    required Map<String, dynamic> originalExported,
    required EditorService editorService,
    required StickerService stickerService,
  }) {
    try {
      print('[ContentChangeDetector] 변경사항 검사 시작');

      // 1. 현재 에디터 상태를 export
      final currentExported = PostExporter.exportToMap(
        editorService: editorService,
        stickerService: stickerService,
      );

      // 2. 문서 구조 비교
      if (_hasDocumentStructureChanged(originalExported, currentExported)) {
        print('[ContentChangeDetector] ✓ 문서 구조 변경 감지');
        return true;
      }

      // 3. 스티커 비교
      if (_hasStickersChanged(originalExported, currentExported)) {
        print('[ContentChangeDetector] ✓ 스티커 변경 감지');
        return true;
      }

      print('[ContentChangeDetector] ✗ 변경사항 없음');
      return false;
    } catch (e) {
      print('[ContentChangeDetector] 에러 발생: $e');
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
      print(
        '[ContentChangeDetector] 노드 개수 변경: ${originalNodes.length} → ${currentNodes.length}',
      );
      return true;
    }

    // 블록 단위 1:1 비교: deepEquals로 전체 비교
    if (!_deepEquals(originalNodes, currentNodes)) {
      print('[ContentChangeDetector] 노드 내용 변경 감지 (1:1 비교)');

      // 디버깅용: 어느 노드가 바뀌었는지 출력
      for (int i = 0; i < originalNodes.length; i++) {
        if (!_deepEquals(originalNodes[i], currentNodes[i])) {
          print('[ContentChangeDetector] 노드[$i] 변경됨');
          print('  원본: ${originalNodes[i]}');
          print('  현재: ${currentNodes[i]}');
          break; // 첫 번째 변경만 출력
        }
      }
      return true;
    }

    return false;
  }

  // 개별 노드 비교 함수들은 제거 (블록 단위 1:1 비교로 대체)

  /// 스티커 비교 (JSON 문자열 1:1 비교)
  static bool _hasStickersChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
  ) {
    // 🎯 content 안의 stickers를 추출
    final originalContent = original['content'] as Map<String, dynamic>?;
    final currentContent = current['content'] as Map<String, dynamic>?;

    final originalStickers = originalContent?['stickers'];
    final currentStickers = currentContent?['stickers'];

    print('[ContentChangeDetector] 🔍 스티커 비교 (content.stickers)');
    print(
      '  원본 스티커: ${originalStickers?.runtimeType} (${(originalStickers as List?)?.length ?? 0}개)',
    );
    print(
      '  현재 스티커: ${currentStickers?.runtimeType} (${(currentStickers as List?)?.length ?? 0}개)',
    );

    // 🎯 JSON 문자열로 변환하여 1:1 비교
    try {
      final originalJson = jsonEncode(originalStickers ?? []);
      final currentJson = jsonEncode(currentStickers ?? []);

      print('  원본 JSON 길이: ${originalJson.length}');
      print('  현재 JSON 길이: ${currentJson.length}');

      if (originalJson != currentJson) {
        print('[ContentChangeDetector] ✓ 스티커 변경 감지 (JSON 불일치)');
        print(
          '  원본 JSON: ${originalJson.substring(0, originalJson.length > 200 ? 200 : originalJson.length)}...',
        );
        print(
          '  현재 JSON: ${currentJson.substring(0, currentJson.length > 200 ? 200 : currentJson.length)}...',
        );
        return true;
      }

      print('[ContentChangeDetector] ✗ 스티커 변경 없음 (JSON 동일)');
      return false;
    } catch (e, stackTrace) {
      print('[ContentChangeDetector] ❌ 스티커 JSON 비교 에러: $e');
      print('  스택 트레이스: $stackTrace');
      // 에러 발생 시 안전하게 변경된 것으로 간주
      return true;
    }
  }

  /// Deep equality 비교 (재귀적으로 Map, List 비교, 정규화 포함)
  static bool _deepEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;

    if (a is Map && b is Map) {
      // 무시할 키 목록 (서버/클라이언트 차이로 인한 false positive 방지)
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
        'accessLevel', // 서버에서만 제공 (공개 범위) - 별도로 관리
        'visibility', // 서버에서만 제공 (공개 범위) - 별도로 관리
        'sharedGroupIds', // 서버에서만 제공 (그룹 공유) - 별도로 관리
        'groupIds', // 서버에서만 제공 (그룹 공유) - 별도로 관리
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
