import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 에디터 내 특수 노드(이미지/이미지행/링크/멘션 등)의 선택/하이라이트 상태를 관리하는 서비스
class NodeComponentService extends ChangeNotifier {
  static final NodeComponentService _instance =
      NodeComponentService._internal();
  factory NodeComponentService() => _instance;
  NodeComponentService._internal();

  void clearAll() {
    clearHighlightedSelection();
    selectImage(null);
    _spoilerByNodeId.clear();
  }

  /// 스포일러 상태만 초기화 (다른 상태는 유지)
  void clearSpoilers() {
    if (_spoilerByNodeId.isEmpty) return;
    _spoilerByNodeId.clear();
    if (kDebugMode) {
      print('[NodeComponentService] clearSpoilers: 모든 스포일러 상태 초기화');
    }
    notifyListeners();
  }

  // ===== 스포일러 헬퍼 =====
  bool shouldShowImageSpoiler(String nodeId, Map<String, dynamic>? metadata) {
    if (isSpoilerDisabled(nodeId)) return false; // 해제되면 숨기지 않음
    final metaFlag = (metadata != null && metadata['spoiler'] == true);
    return metaFlag || isSpoiler(nodeId);
  }

  bool shouldShowParagraphSpoiler(String nodeId, AttributedText text) {
    if (isSpoilerDisabled(nodeId)) return false;
    for (int i = 0; i < text.text.length; i++) {
      final attrs = text.getAllAttributionsAt(i);
      if (attrs.any((a) => a is NamedAttribution && a.id == 'spoiler')) {
        return true;
      }
    }
    return false;
  }

  // URL↔ID 매핑 로직 제거됨

  // 현재 선택된 노드 ID (과거 호환: 이미지 기준 네이밍 유지)
  String? _selectedImageId;
  // 편집된 이미지 바이트 저장소 (nodeId -> bytes)
  final Map<String, Uint8List> _editedBytesByNodeId = <String, Uint8List>{};
  // 텍스트 범위 선택에 포함된 이미지/이미지행 하이라이트 id 집합
  final Set<String> _selectionHighlightedImageIds = <String>{};
  // 스포일러 상태 (세션 범위 캐시)
  final Map<String, bool> _spoilerByNodeId = <String, bool>{};

  // Getters
  String? get selectedImageId => _selectedImageId;
  // 신규 API(의미 반영): 선택된 노드 ID
  String? get selectedNodeId => _selectedImageId;
  Uint8List? getEditedBytes(String nodeId) => _editedBytesByNodeId[nodeId];
  Set<String> get selectionHighlightedIds => _selectionHighlightedImageIds;
  bool get hasSelectedImage => _selectedImageId != null;
  bool isSpoiler(String nodeId) => _spoilerByNodeId[nodeId] == true;

  /// 스포일러가 명시적으로 비활성화되었는지 확인 (false로 설정된 경우)
  bool isSpoilerDisabled(String nodeId) {
    final hasKey = _spoilerByNodeId.containsKey(nodeId);
    final value = _spoilerByNodeId[nodeId];
    final result = hasKey && value == false;
    if (kDebugMode) {
      print(
        '[NodeComponentService] isSpoilerDisabled: $nodeId -> hasKey=$hasKey, value=$value, result=$result',
      );
    }
    return result;
  }

  // ====== Transient thumbnail storage (session-scoped, in-memory only) ======
  final Map<String, String> _tempThumbnailUrlBySession = <String, String>{};
  final Map<String, String> _tempThumbnailIdBySession = <String, String>{};

  String? getTempThumbnailUrl(String sessionKey) {
    final url = _tempThumbnailUrlBySession[sessionKey];
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔍 [NodeComponentService] getTempThumbnailUrl');
    print('   sessionKey: $sessionKey');
    print('   결과: $url');
    print('   전체 맵: $_tempThumbnailUrlBySession');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return url;
  }

  String? getTempThumbnailId(String sessionKey) =>
      _tempThumbnailIdBySession[sessionKey];

  void setTempThumbnail(String sessionKey, {required String url, String? id}) {
    _tempThumbnailUrlBySession[sessionKey] = url;
    if (id != null) {
      _tempThumbnailIdBySession[sessionKey] = id;
    }
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('💾 [NodeComponentService] setTempThumbnail');
    print('   sessionKey: $sessionKey');
    print('   url: $url');
    print('   id: $id');
    print('   저장 후 전체 맵: $_tempThumbnailUrlBySession');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    notifyListeners();
  }

  void clearTempThumbnail(String sessionKey) {
    _tempThumbnailUrlBySession.remove(sessionKey);
    _tempThumbnailIdBySession.remove(sessionKey);
    notifyListeners();
  }

  // notifyListeners() 없이 조용히 썸네일 정리 (dispose 시 사용)
  void clearTempThumbnailSilently(String sessionKey) {
    _tempThumbnailUrlBySession.remove(sessionKey);
    _tempThumbnailIdBySession.remove(sessionKey);
  }

  /// 노드 선택 (과거 호환: 이미지 선택)
  void selectImage(String? imageId) {
    if (imageId == _selectedImageId) {
      // 이미지 선택 취소
      _selectedImageId = null;
    } else {
      _selectedImageId = imageId;
    }

    notifyListeners();
  }

  /// 신규 API: 노드 선택
  void selectNode(String? nodeId) => selectImage(nodeId);

  /// 선택 상태 해제
  void clearSelection() {
    _selectedImageId = null;
    notifyListeners();
  }

  /// 신규 API: 선택 상태 해제 (별칭)
  void clearNodeSelection() => clearSelection();

  /// 선택 상태 해제 (notify 없이 조용히)
  void clearSelectionSilently() {
    _selectedImageId = null;
  }

  /// 신규 API: 선택 상태 해제 (notify 없이 조용히) 별칭
  void clearNodeSelectionSilently() => clearSelectionSilently();

  /// 편집 결과 반영: 해당 이미지 노드에 편집된 바이트를 저장한다
  void applyEditedBytes({required String nodeId, required Uint8List bytes}) {
    _editedBytesByNodeId[nodeId] = bytes;
    notifyListeners();
  }

  /// 편집 결과 제거(원본으로 복귀)
  void clearEditedBytes(String nodeId) {
    if (_editedBytesByNodeId.remove(nodeId) != null) {
      notifyListeners();
    }
  }

  /// 이미지/행 노드 스포일러 토글 및 설정
  void toggleSpoiler(String nodeId) {
    _spoilerByNodeId[nodeId] = !(_spoilerByNodeId[nodeId] == true);
    notifyListeners();
  }

  void setSpoiler(String nodeId, bool value) {
    final oldValue = _spoilerByNodeId[nodeId];
    if (oldValue == value) {
      if (kDebugMode) {
        print('[NodeComponentService] setSpoiler: $nodeId = $value (변경 없음)');
      }
      return;
    }
    _spoilerByNodeId[nodeId] = value;
    if (kDebugMode) {
      print(
        '[NodeComponentService] setSpoiler: $nodeId = $value (이전: $oldValue), notifyListeners 호출',
      );
    }
    notifyListeners();
  }

  /// 현재 텍스트 범위 선택에 포함된 특수 노드를 하이라이트한다
  void setHighlightedSelection(Set<String> ids) {
    if (_selectionHighlightedImageIds.length == ids.length &&
        _selectionHighlightedImageIds.containsAll(ids)) {
      return;
    }
    _selectionHighlightedImageIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  /// 신규 API: 하이라이트 설정 별칭
  void setHighlightedNodeSelection(Set<String> ids) =>
      setHighlightedSelection(ids);

  /// 특수 노드 하이라이트 해제
  void clearHighlightedSelection() {
    if (_selectionHighlightedImageIds.isEmpty) return;
    _selectionHighlightedImageIds.clear();
    notifyListeners();
  }

  /// 신규 API: 하이라이트 해제 별칭
  void clearHighlightedNodeSelection() => clearHighlightedSelection();

  /// 특수 노드 하이라이트 해제 (notify 없이 조용히)
  void clearHighlightedSelectionSilently() {
    if (_selectionHighlightedImageIds.isEmpty) return;
    _selectionHighlightedImageIds.clear();
  }

  /// 신규 API: 하이라이트 해제 (조용히) 별칭
  void clearHighlightedNodeSelectionSilently() =>
      clearHighlightedSelectionSilently();
}
