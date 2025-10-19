import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 에디터 내 특수 노드(이미지/이미지행/링크/멘션 등)의 선택/하이라이트 상태를 관리하는 서비스
class NodeComponentService extends ChangeNotifier {
  static final NodeComponentService _instance =
      NodeComponentService._internal();
  factory NodeComponentService() => _instance;
  NodeComponentService._internal();

  List<String> _imageIds = [];
  List<String> get imageIds => _imageIds;
  void addImageId(String imageId) {
    _imageIds.add(imageId);
  }

  // URL ↔ imageId 매핑 (업로드 성공 시 등록)
  final Map<String, String> _urlToImageId = <String, String>{};
  void registerImageUrlId(String url, String imageId) {
    if (url.isEmpty || imageId.isEmpty) return;
    _urlToImageId[url] = imageId;

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📸 [이미지 매핑 등록]');
    print('URL: $url');
    print('ID: $imageId');
    print('💾 현재 매핑 맵 (총 ${_urlToImageId.length}개):');
    _urlToImageId.forEach((key, value) {
      print(
        '  • ${key.substring(key.length > 50 ? key.length - 50 : 0)} → $value',
      );
    });
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  String? getImageIdByUrl(String url) => _urlToImageId[url];
  Map<String, String> get urlToImageIdMap => Map.unmodifiable(_urlToImageId);

  // 삭제 시 URL 매핑 제거 (usedImageIds에서 빠지도록)
  void unregisterImageUrl(String url) {
    final removed = _urlToImageId.remove(url);
    if (removed != null) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🗑️ [이미지 매핑 제거]');
      print('URL: $url');
      print('제거된 ID: $removed');
      print('💾 현재 매핑 맵 (총 ${_urlToImageId.length}개):');
      _urlToImageId.forEach((key, value) {
        print(
          '  • ${key.substring(key.length > 50 ? key.length - 50 : 0)} → $value',
        );
      });
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      notifyListeners();
    }
  }

  void unregisterImageUrls(Iterable<String> urls) {
    bool changed = false;
    final removedUrls = <String>[];
    for (final u in urls) {
      if (_urlToImageId.remove(u) != null) {
        changed = true;
        removedUrls.add(u);
      }
    }
    if (changed) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🗑️ [이미지 매핑 일괄 제거]');
      print('제거된 URL 개수: ${removedUrls.length}');
      removedUrls.forEach((url) => print('  • $url'));
      print('💾 현재 매핑 맵 (총 ${_urlToImageId.length}개):');
      _urlToImageId.forEach((key, value) {
        print(
          '  • ${key.substring(key.length > 50 ? key.length - 50 : 0)} → $value',
        );
      });
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      notifyListeners();
    }
  }

  // 매핑 맵 전체 정리 (발행/임시저장/에디터 종료 시)
  void clearImageUrlMapping() {
    final count = _urlToImageId.length;
    if (count > 0) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🧹 [이미지 매핑 맵 전체 정리]');
      print('정리 전 매핑 개수: $count');
      _urlToImageId.clear();
      print('✅ 매핑 맵 초기화 완료');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      notifyListeners();
    }
  }

  // 현재 선택된 노드 ID (과거 호환: 이미지 기준 네이밍 유지)
  String? _selectedImageId;
  // 편집된 이미지 바이트 저장소 (nodeId -> bytes)
  final Map<String, Uint8List> _editedBytesByNodeId = <String, Uint8List>{};
  // 텍스트 범위 선택에 포함된 이미지/이미지행 하이라이트 id 집합
  final Set<String> _selectionHighlightedImageIds = <String>{};

  // Getters
  String? get selectedImageId => _selectedImageId;
  // 신규 API(의미 반영): 선택된 노드 ID
  String? get selectedNodeId => _selectedImageId;
  Uint8List? getEditedBytes(String nodeId) => _editedBytesByNodeId[nodeId];
  Set<String> get selectionHighlightedIds => _selectionHighlightedImageIds;

  bool get hasSelectedImage => _selectedImageId != null;

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
