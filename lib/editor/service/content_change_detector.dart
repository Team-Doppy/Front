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

  /// ID 비교를 위한 정규화: null/''/'null'/0 → null, 그 외는 문자열로 통일
  static String? _normalizeId(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      if (value == 0) return null;
      return value.toString();
    }
    final String s = value.toString().trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase() == 'null') return null;
    if (s == '0') return null;
    return s;
  }

  /// 문자열 비교를 위한 정규화: null/''/'null' → null, 그 외 trim 적용
  static String? _normalizeString(dynamic value) {
    if (value == null) return null;
    final String s = value.toString().trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase() == 'null') return null;
    return s;
  }

  /// 동등성 비교를 위한 숫자 파싱
  static num? _asNumOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) {
      final s = value.trim();
      if (s.isEmpty) return null;
      return num.tryParse(s);
    }
    return null;
  }

  /// 숫자 동등성(허용 오차 포함)
  static bool _numEquals(num? a, num? b, {double epsilon = 0.0001}) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() < epsilon;
  }

  /// 문서 구조 및 내용 비교
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

    // 각 노드를 하나씩 비교
    for (int i = 0; i < originalNodes.length; i++) {
      if (_hasNodeChanged(originalNodes[i], currentNodes[i], i)) {
        return true;
      }
    }

    return false;
  }

  /// 개별 노드 비교
  static bool _hasNodeChanged(
    dynamic originalNode,
    dynamic currentNode,
    int index,
  ) {
    if (originalNode is! Map || currentNode is! Map) {
      final changed = originalNode != currentNode;
      if (changed) {
        print('[ContentChangeDetector] 노드[$index] 타입 변경');
      }
      return changed;
    }

    final original = originalNode as Map<String, dynamic>;
    final current = currentNode as Map<String, dynamic>;

    // 1. 노드 타입 확인
    final originalType = original['type'];
    final currentType = current['type'];

    // clip과 video는 동일한 타입으로 취급 (호환성)
    final normalizedOriginalType =
        originalType == 'clip' ? 'video' : originalType;
    final normalizedCurrentType = currentType == 'clip' ? 'video' : currentType;

    if (normalizedOriginalType != normalizedCurrentType) {
      print(
        '[ContentChangeDetector] 노드[$index] 타입 변경: $originalType → $currentType',
      );
      return true;
    }

    // 2. 타입별 비교 (정규화된 타입 사용)
    switch (normalizedOriginalType) {
      case 'paragraph':
      case 'title':
        return _hasParagraphNodeChanged(original, current, index);

      case 'image':
        return _hasImageNodeChanged(original, current, index);

      case 'imageRow':
        return _hasImageRowNodeChanged(original, current, index);

      case 'video': // clip과 video 모두 여기서 처리
        return _hasClipNodeChanged(original, current, index);

      case 'link':
        return _hasLinkNodeChanged(original, current, index);

      case 'mention':
        return _hasMentionNodeChanged(original, current, index);

      case 'divider':
        return _hasDividerNodeChanged(original, current, index);

      default:
        // 알 수 없는 타입은 deep equality 비교
        return !_deepEquals(original, current);
    }
  }

  /// 문단/제목 노드 비교
  static bool _hasParagraphNodeChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    // 1. 텍스트 내용 비교
    final originalText = _normalizeString(original['text']);
    final currentText = _normalizeString(current['text']);

    if (originalText != currentText) {
      print('[ContentChangeDetector] 노드[$index] 텍스트 변경');
      print('  원본: "$originalText"');
      print('  현재: "$currentText"');
      return true;
    }

    // 2. 메타데이터 비교 (align, fontFamily, spoiler 등)
    if (_hasMetadataChanged(original, current, index)) {
      return true;
    }

    // 3. 텍스트 스타일 비교 (spans)
    final originalSpans = original['spans'] as List?;
    final currentSpans = current['spans'] as List?;

    if (!_deepEquals(originalSpans, currentSpans)) {
      print('[ContentChangeDetector] 노드[$index] 스타일(spans) 변경');
      return true;
    }

    return false;
  }

  /// 이미지 노드 비교
  static bool _hasImageNodeChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    // 1. 이미지 URL
    if (original['imageUrl'] != current['imageUrl']) {
      print('[ContentChangeDetector] 노드[$index] 이미지 URL 변경');
      return true;
    }

    // 2. 이미지 ID (null/''/0 동등 처리, 타입 차이 보정)
    final String? origImageId = _normalizeId(original['imageId']);
    final String? currImageId = _normalizeId(current['imageId']);
    if (origImageId != currImageId) {
      // 두 값이 모두 존재할 때만 변경으로 간주 (한쪽만 비어있으면 서버/클라이언트 표현 차이로 무시)
      if (origImageId != null && currImageId != null) {
        print('[ContentChangeDetector] 노드[$index] 이미지 ID 변경');
        return true;
      }
    }

    // 3. 이미지 크기
    final num? oW = _asNumOrNull(original['width']);
    final num? oH = _asNumOrNull(original['height']);
    final num? cW = _asNumOrNull(current['width']);
    final num? cH = _asNumOrNull(current['height']);
    if (!_numEquals(oW, cW) || !_numEquals(oH, cH)) {
      print('[ContentChangeDetector] 노드[$index] 이미지 크기 변경');
      return true;
    }

    // 4. alt 텍스트
    if (_normalizeString(original['alt']) != _normalizeString(current['alt'])) {
      print('[ContentChangeDetector] 노드[$index] 이미지 alt 변경');
      return true;
    }

    // 5. 메타데이터 (spoiler 등)
    if (_hasMetadataChanged(original, current, index)) {
      return true;
    }

    return false;
  }

  /// 이미지 행 노드 비교
  static bool _hasImageRowNodeChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    final originalImages = original['images'] as List?;
    final currentImages = current['images'] as List?;

    if (originalImages == null || currentImages == null) {
      return originalImages != currentImages;
    }

    // 이미지 개수 비교
    if (originalImages.length != currentImages.length) {
      print('[ContentChangeDetector] 노드[$index] 이미지 행 개수 변경');
      return true;
    }

    // 각 이미지 비교 (ID/사이즈/alt 느슨 비교)
    for (int i = 0; i < originalImages.length; i++) {
      final origImg = originalImages[i] as Map<String, dynamic>?;
      final currImg = currentImages[i] as Map<String, dynamic>?;

      // null 비교
      if (origImg == null || currImg == null) {
        if (origImg != currImg) {
          print('[ContentChangeDetector] 노드[$index] 이미지 행[$i] 변경(null)');
          return true;
        }
        continue;
      }

      // URL
      if (_normalizeString(origImg['imageUrl']) !=
          _normalizeString(currImg['imageUrl'])) {
        print('[ContentChangeDetector] 노드[$index] 이미지 행[$i] URL 변경');
        return true;
      }

      // ID (느슨 비교: 둘 다 존재할 때만 변경)
      final String? oId = _normalizeId(origImg['imageId']);
      final String? cId = _normalizeId(currImg['imageId']);
      if (oId != cId && oId != null && cId != null) {
        print('[ContentChangeDetector] 노드[$index] 이미지 행[$i] ID 변경');
        return true;
      }

      // width/height
      final num? oW = _asNumOrNull(origImg['width']);
      final num? oH = _asNumOrNull(origImg['height']);
      final num? cW = _asNumOrNull(currImg['width']);
      final num? cH = _asNumOrNull(currImg['height']);
      if (!_numEquals(oW, cW) || !_numEquals(oH, cH)) {
        print('[ContentChangeDetector] 노드[$index] 이미지 행[$i] 크기 변경');
        return true;
      }

      // alt
      if (_normalizeString(origImg['alt']) !=
          _normalizeString(currImg['alt'])) {
        print('[ContentChangeDetector] 노드[$index] 이미지 행[$i] alt 변경');
        return true;
      }

      // 기타 필드는 깊은 비교 (있다면)
      if (!_deepEquals(origImg, currImg)) {
        print('[ContentChangeDetector] 노드[$index] 이미지 행[$i] 기타 변경');
        return true;
      }
    }

    // 메타데이터
    if (_hasMetadataChanged(original, current, index)) {
      return true;
    }

    return false;
  }

  /// 클립(비디오) 노드 비교
  static bool _hasClipNodeChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    // 1. 비디오 URL
    if (_normalizeString(original['clipUrl']) !=
        _normalizeString(current['clipUrl'])) {
      print('[ContentChangeDetector] 노드[$index] 클립 URL 변경');
      return true;
    }

    // 2. 썸네일 URL
    if (_normalizeString(original['thumbnailUrl']) !=
        _normalizeString(current['thumbnailUrl'])) {
      print('[ContentChangeDetector] 노드[$index] 클립 썸네일 변경');
      return true;
    }

    // 3. 비디오 ID (null/''/0 동등 처리)
    final String? origVideoId = _normalizeId(original['videoId']);
    final String? currVideoId = _normalizeId(current['videoId']);
    if (origVideoId != currVideoId) {
      if (origVideoId != null && currVideoId != null) {
        print('[ContentChangeDetector] 노드[$index] 클립 ID 변경');
        return true;
      }
    }

    // 4. 메타데이터
    if (_hasMetadataChanged(original, current, index)) {
      return true;
    }

    return false;
  }

  /// 링크 노드 비교
  static bool _hasLinkNodeChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    // 1. URL
    if (_normalizeString(original['url']) != _normalizeString(current['url'])) {
      print('[ContentChangeDetector] 노드[$index] 링크 URL 변경');
      return true;
    }

    // 2. 제목
    if (_normalizeString(original['title']) !=
        _normalizeString(current['title'])) {
      print('[ContentChangeDetector] 노드[$index] 링크 제목 변경');
      return true;
    }

    // 3. 설명
    if (_normalizeString(original['description']) !=
        _normalizeString(current['description'])) {
      print('[ContentChangeDetector] 노드[$index] 링크 설명 변경');
      return true;
    }

    // 4. 이미지 URL
    if (_normalizeString(original['imageUrl']) !=
        _normalizeString(current['imageUrl'])) {
      print('[ContentChangeDetector] 노드[$index] 링크 이미지 변경');
      return true;
    }

    return false;
  }

  /// 멘션 노드 비교
  static bool _hasMentionNodeChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    // 멘션된 사용자 목록 비교
    final originalUsernames = original['usernames'] as List?;
    final currentUsernames = current['usernames'] as List?;

    if (!_deepEquals(originalUsernames, currentUsernames)) {
      print('[ContentChangeDetector] 노드[$index] 멘션 사용자 변경');
      return true;
    }

    // 텍스트 비교
    if (original['text'] != current['text']) {
      print('[ContentChangeDetector] 노드[$index] 멘션 텍스트 변경');
      return true;
    }

    return false;
  }

  /// 구분선 노드 비교
  static bool _hasDividerNodeChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    // 구분선은 단순 노드이므로 타입만 같으면 동일
    return false;
  }

  /// 메타데이터 비교 (spoiler, align, fontFamily 등)
  static bool _hasMetadataChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
    int index,
  ) {
    // spoiler
    final bool origSpoiler = original['spoiler'] == true;
    final bool currSpoiler = current['spoiler'] == true;
    if (origSpoiler != currSpoiler) {
      print('[ContentChangeDetector] 노드[$index] spoiler 변경');
      return true;
    }

    // align: null 과 'center' 를 동일하게 취급 (export 시 center는 생략되기도 함)
    final String origAlign = (original['align'] ?? 'center').toString();
    final String currAlign = (current['align'] ?? 'center').toString();
    if (origAlign != currAlign) {
      print('[ContentChangeDetector] 노드[$index] align 변경');
      return true;
    }

    // fontFamily (null/'' 동등 처리)
    if (_normalizeString(original['fontFamily']) !=
        _normalizeString(current['fontFamily'])) {
      print('[ContentChangeDetector] 노드[$index] fontFamily 변경');
      return true;
    }

    // isTitle은 비교하지 않음 (서버 데이터에 없을 수 있고, 에디터가 자동으로 추가함)
    // 제목 변경은 썸네일 수정에서만 가능하므로 여기서는 무시

    return false;
  }

  /// 스티커 비교
  static bool _hasStickersChanged(
    Map<String, dynamic> original,
    Map<String, dynamic> current,
  ) {
    final originalStickers = original['stickers'] as List?;
    final currentStickers = current['stickers'] as List?;

    // null과 빈 배열을 동일하게 취급 (둘 다 "스티커 없음")
    final originalEmpty = originalStickers == null || originalStickers.isEmpty;
    final currentEmpty = currentStickers == null || currentStickers.isEmpty;

    // 둘 다 비어있으면 변경 없음
    if (originalEmpty && currentEmpty) {
      return false;
    }

    // 하나만 비어있으면 변경됨
    if (originalEmpty != currentEmpty) {
      print('[ContentChangeDetector] 스티커 존재 여부 변경');
      final origCount = originalStickers?.length ?? 0;
      final currCount = currentStickers?.length ?? 0;
      print('  원본: ${originalEmpty ? "없음" : "$origCount개"}');
      print('  현재: ${currentEmpty ? "없음" : "$currCount개"}');
      return true;
    }

    // 둘 다 null이 아닌 경우 (위에서 empty 체크 완료)
    if (originalStickers == null || currentStickers == null) {
      return false;
    }

    // 스티커 개수 비교
    if (originalStickers.length != currentStickers.length) {
      print(
        '[ContentChangeDetector] 스티커 개수 변경: ${originalStickers.length} → ${currentStickers.length}',
      );
      return true;
    }

    // 각 스티커 비교
    for (int i = 0; i < originalStickers.length; i++) {
      final origSticker = originalStickers[i] as Map<String, dynamic>;
      final currSticker = currentStickers[i] as Map<String, dynamic>;

      // 1. 타입
      if (origSticker['type'] != currSticker['type']) {
        print('[ContentChangeDetector] 스티커[$i] 타입 변경');
        return true;
      }

      // 2. 위치
      final origPos = origSticker['position'] as Map<String, dynamic>?;
      final currPos = currSticker['position'] as Map<String, dynamic>?;

      if (!_deepEquals(origPos, currPos)) {
        print('[ContentChangeDetector] 스티커[$i] 위치 변경');
        print('  원본: $origPos');
        print('  현재: $currPos');
        return true;
      }

      // 3. 크기
      final origSize = origSticker['size'] as Map<String, dynamic>?;
      final currSize = currSticker['size'] as Map<String, dynamic>?;

      if (!_deepEquals(origSize, currSize)) {
        print('[ContentChangeDetector] 스티커[$i] 크기 변경');
        return true;
      }

      // 4. 앵커
      final origAnchor = origSticker['anchor'] as Map<String, dynamic>?;
      final currAnchor = currSticker['anchor'] as Map<String, dynamic>?;

      if (!_deepEquals(origAnchor, currAnchor)) {
        print('[ContentChangeDetector] 스티커[$i] 앵커 변경');
        return true;
      }

      // 5. 타입별 추가 데이터
      final stickerType = origSticker['type'];

      switch (stickerType) {
        case 'image':
          // 이미지 URL, ID 비교 (ID는 느슨 비교)
          final String? sOrigId = _normalizeId(origSticker['imageId']);
          final String? sCurrId = _normalizeId(currSticker['imageId']);
          final bool urlChanged =
              origSticker['imageUrl'] != currSticker['imageUrl'];
          final bool idChanged =
              (sOrigId != sCurrId) && (sOrigId != null && sCurrId != null);
          if (urlChanged || idChanged) {
            print('[ContentChangeDetector] 스티커[$i] 이미지 데이터 변경');
            return true;
          }
          break;

        case 'drawing':
          // 드로잉 strokes 비교
          final origStrokes = origSticker['strokes'] as List?;
          final currStrokes = currSticker['strokes'] as List?;

          if (!_deepEquals(origStrokes, currStrokes)) {
            print('[ContentChangeDetector] 스티커[$i] 드로잉 strokes 변경');
            return true;
          }
          break;
      }
    }

    return false;
  }

  /// Deep equality 비교 (재귀적으로 Map, List 비교)
  static bool _deepEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;

    if (a is Map && b is Map) {
      if (a.length != b.length) return false;

      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
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
