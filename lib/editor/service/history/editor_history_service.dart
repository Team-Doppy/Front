import 'dart:async';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/service/history/document_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 🎯 Undo/Redo 히스토리 관리 전담 서비스
class EditorHistoryService {
  final MutableDocument _document;
  final Function(DocumentNode) _copyNode;

  // 히스토리 스택
  final List<DocumentSnapshot> _undoStack = [];
  final List<DocumentSnapshot> _redoStack = [];

  // 상태 플래그
  bool _isExecutingHistory = false;
  bool _initialStateSaved = false;

  // 타이머
  Timer? _historyTimer;

  EditorHistoryService({
    required MutableDocument document,
    required Function(DocumentNode) copyNode,
  }) : _document = document,
       _copyNode = copyNode;

  /// 🎯 히스토리 실행 중인지 확인
  bool get isExecutingHistory => _isExecutingHistory;

  /// 🎯 히스토리 실행 플래그 설정 (외부에서 제어 가능)
  set isExecutingHistory(bool value) => _isExecutingHistory = value;

  /// Undo 가능 여부
  bool get canUndo => _undoStack.length > 1;

  /// Redo 가능 여부
  bool get canRedo => _redoStack.isNotEmpty;

  /// 초기 상태 저장 여부
  bool get initialStateSaved => _initialStateSaved;

  /// 🎯 초기 상태 저장 (비동기로 처리하여 UI 블로킹 방지)
  Future<void> saveInitialState() async {
    if (_isExecutingHistory || _initialStateSaved) {
      return; // 🎯 이미 저장되었으면 중복 실행 방지
    }

    // 🎯 노드 복사를 비동기로 처리
    final snapshot = await _copyAllNodesAsync();
    _undoStack.add(snapshot);
    _initialStateSaved = true; // 🎯 저장 완료 표시
    debugPrint(
      '[HistoryService] 📸 초기 상태 저장 (nodes: ${snapshot.nodes.length})',
    );
  }

  /// 🎯 현재 상태를 히스토리에 저장
  void saveCurrentState({bool immediate = false, VoidCallback? onSaved}) {
    if (_isExecutingHistory) return;

    if (immediate) {
      // 즉시 저장 (엔터, 삭제, 이동 등) - 비동기로 처리하여 UI 블로킹 방지
      _historyTimer?.cancel();

      // 🎯 비동기로 노드 복사 (UI 블로킹 방지)
      Future.microtask(() async {
        final snapshot = await _copyAllNodesAsyncFast();

        // 🎯 중복 방지: 마지막 스냅샷과 같으면 저장하지 않음
        if (_undoStack.isNotEmpty &&
            _areSnapshotsEqual(_undoStack.last, snapshot)) {
          debugPrint('[HistoryService] ⚠️ 중복 상태 - 저장 스킵');
          return;
        }

        _undoStack.add(snapshot);
        _redoStack.clear();

        // 🎯 성능 최적화: 최대 20개까지만 유지 (메모리 사용량 감소)
        if (_undoStack.length > 20) {
          _undoStack.removeAt(0);
        }

        debugPrint(
          '[HistoryService] 📸 즉시 저장 (total: ${_undoStack.length}, nodes: ${snapshot.nodes.length})',
        );

        // 🎯 Undo/Redo 버튼 상태 업데이트 콜백
        if (onSaved != null) {
          onSaved();
        }
      });
    } else {
      // 디바운싱 (텍스트 입력)
      _historyTimer?.cancel();
      _historyTimer = Timer(Duration(seconds: 1), () {
        final snapshot = _copyAllNodes();

        // 🎯 중복 방지: 마지막 스냅샷과 같으면 저장하지 않음
        if (_undoStack.isNotEmpty &&
            _areSnapshotsEqual(_undoStack.last, snapshot)) {
          debugPrint('[HistoryService] ⚠️ 중복 상태 - 저장 스킵');
          return;
        }

        _undoStack.add(snapshot);
        _redoStack.clear();

        // 🎯 성능 최적화: 최대 20개까지만 유지 (메모리 사용량 감소)
        if (_undoStack.length > 20) {
          _undoStack.removeAt(0);
        }

        debugPrint('[HistoryService] 📸 디바운싱 저장 (total: ${_undoStack.length})');

        // 🎯 Undo/Redo 버튼 상태 업데이트 콜백
        if (onSaved != null) {
          onSaved();
        }
      });
    }
  }

  /// 🎯 Undo 실행
  void undo({
    required VoidCallback onSuccess,
    required VoidCallback onRestoreSnapshot,
  }) {
    // 🎯 이미 실행 중이면 무시 (연속 실행 방지)
    if (_isExecutingHistory) {
      debugPrint('[HistoryService] ⚠️ Undo 실행 중 - 무시');
      return;
    }

    if (!canUndo) {
      debugPrint('[HistoryService] ❌ Undo 불가 (첫 상태)');
      return;
    }

    try {
      _isExecutingHistory = true;
      _historyTimer?.cancel();

      // 🎯 현재 상태를 redo 스택에 저장
      final currentSnapshot = _undoStack.removeLast();
      _redoStack.add(currentSnapshot);

      // 🎯 이전 상태로 복원 (스냅샷은 외부에서 접근)
      onRestoreSnapshot();

      debugPrint('[HistoryService] ⬅️ Undo 완료 (남은: ${_undoStack.length})');
    } catch (e) {
      debugPrint('[HistoryService] Undo 실패: $e');
      // 🎯 에러 발생 시 스택 복구 시도
      if (_redoStack.isNotEmpty) {
        try {
          _undoStack.add(_redoStack.removeLast());
        } catch (_) {}
      }
    } finally {
      _isExecutingHistory = false;
      onSuccess();
    }
  }

  /// 🎯 Redo 실행
  void redo({
    required VoidCallback onSuccess,
    required VoidCallback onRestoreSnapshot,
  }) {
    // 🎯 이미 실행 중이면 무시 (연속 실행 방지)
    if (_isExecutingHistory) {
      debugPrint('[HistoryService] ⚠️ Redo 실행 중 - 무시');
      return;
    }

    if (!canRedo) {
      debugPrint('[HistoryService] ❌ Redo 불가 (없음)');
      return;
    }

    try {
      _isExecutingHistory = true;
      _historyTimer?.cancel();

      // 🎯 Redo 스택에서 다음 상태 가져오기
      final nextSnapshot = _redoStack.removeLast();
      _undoStack.add(nextSnapshot);

      // 🎯 다음 상태로 복원
      onRestoreSnapshot();

      debugPrint('[HistoryService] ➡️ Redo 완료 (남은 redo: ${_redoStack.length})');
    } catch (e) {
      debugPrint('[HistoryService] Redo 실패: $e');
      // 🎯 에러 발생 시 스택 복구 시도
      if (_undoStack.length > 1) {
        try {
          _redoStack.add(_undoStack.removeLast());
        } catch (_) {}
      }
    } finally {
      _isExecutingHistory = false;
      onSuccess();
    }
  }

  /// 🎯 히스토리 초기화 (임시저장 불러오기, 문서 교체 시 사용)
  void clearHistory() {
    _historyTimer?.cancel();
    _undoStack.clear();
    _redoStack.clear();
    _initialStateSaved = false; // 초기 상태 저장 플래그도 리셋
    debugPrint('[HistoryService] 🧹 히스토리 초기화 완료');
  }

  /// 🎯 즉시 히스토리 저장 (외부에서 호출 가능)
  void saveHistoryNow({VoidCallback? onSaved}) {
    _historyTimer?.cancel();
    saveCurrentState(immediate: true, onSaved: onSaved);
  }

  /// 🎯 리소스 정리
  void dispose() {
    _historyTimer?.cancel();
    _undoStack.clear();
    _redoStack.clear();
    debugPrint('[HistoryService] 🧹 리소스 정리 완료');
  }

  /// 🎯 마지막 스냅샷 가져오기 (복원용)
  DocumentSnapshot? get lastSnapshot =>
      _undoStack.isNotEmpty ? _undoStack.last : null;

  // ========== Private Methods ==========

  /// 🎯 노드가 저장 가능한지 확인 (공통 필터링 로직)
  bool _shouldSaveNode(DocumentNode node) {
    // 🎯 빈 문단은 저장하지 않음 (제목 제외)
    if (node is ParagraphNode) {
      final isTitle = node.metadata['isTitle'] == true;
      final isEmpty = node.text.text.trim().isEmpty;
      if (!isTitle && isEmpty) {
        return false;
      }
    }

    // 🎯 플레이스홀더(업로드 중)는 저장하지 않음
    if (_isPlaceholderNode(node)) {
      return false;
    }

    return true;
  }

  /// 🎯 모든 노드를 비동기로 deep copy (초기 상태 저장용, UI 블로킹 방지)
  Future<DocumentSnapshot> _copyAllNodesAsync() async {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < _document.nodeCount; i++) {
      final node = _document.getNodeAt(i);
      if (node != null && _shouldSaveNode(node)) {
        nodes[node.id] = _copyNode(node);
        order.add(node.id);

        // 🎯 10개마다만 지연 (200ms → 100ms, 총 시간 대폭 감소)
        if (i < _document.nodeCount - 1 && i % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    return DocumentSnapshot(nodes: nodes, order: order, selection: null);
  }

  /// 🎯 모든 노드를 빠르게 비동기로 deep copy (즉시 저장용, 지연 최소화)
  Future<DocumentSnapshot> _copyAllNodesAsyncFast() async {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < _document.nodeCount; i++) {
      final node = _document.getNodeAt(i);
      if (node != null && _shouldSaveNode(node)) {
        // 🎯 직접 복사 (microtask 오버헤드 제거)
        nodes[node.id] = _copyNode(node);
        order.add(node.id);

        // 🎯 50개마다만 지연 (성능 향상)
        if (i < _document.nodeCount - 1 && i % 50 == 0) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
    }

    return DocumentSnapshot(nodes: nodes, order: order, selection: null);
  }

  /// 🎯 모든 노드를 deep copy (커서는 저장하지 않음)
  DocumentSnapshot _copyAllNodes() {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < _document.nodeCount; i++) {
      final node = _document.getNodeAt(i);
      if (node != null && _shouldSaveNode(node)) {
        nodes[node.id] = _copyNode(node);
        order.add(node.id);
      }
    }

    return DocumentSnapshot(nodes: nodes, order: order, selection: null);
  }

  /// 🎯 스냅샷 비교 (가볍고 빠른 체크)
  bool _areSnapshotsEqual(DocumentSnapshot a, DocumentSnapshot b) {
    // 1️⃣ 노드 개수가 다르면 즉시 다름
    if (a.order.length != b.order.length) return false;

    // 2️⃣ 비어있으면 같음 (빠른 종료)
    if (a.order.isEmpty) return true;

    // 3️⃣ 첫/마지막 노드 ID만 빠르게 체크
    if (a.order.first != b.order.first || a.order.last != b.order.last) {
      return false;
    }

    // 4️⃣ 첫/마지막 노드의 핵심 내용만 체크 (대부분 여기서 차이 발견)
    final firstA = a.nodes[a.order.first];
    final firstB = b.nodes[b.order.first];
    final lastA = a.nodes[a.order.last];
    final lastB = b.nodes[b.order.last];

    if (firstA == null || firstB == null || lastA == null || lastB == null) {
      return false;
    }

    // 첫 노드 비교
    if (!_areNodesContentEqual(firstA, firstB)) return false;

    // 마지막 노드 비교 (첫/마지막이 같은 경우는 스킵)
    if (a.order.length > 1) {
      if (!_areNodesContentEqual(lastA, lastB)) return false;
    }

    // 5️⃣ 노드가 많으면 샘플링해서 비교 (전체 비교는 비용이 큼)
    if (a.order.length > 10) {
      // 중간 노드 2개만 샘플링
      final mid1 = a.order.length ~/ 3;
      final mid2 = (a.order.length * 2) ~/ 3;

      final midA1 = a.nodes[a.order[mid1]];
      final midB1 = b.nodes[b.order[mid1]];
      if (midA1 != null && midB1 != null) {
        if (!_areNodesContentEqual(midA1, midB1)) return false;
      }

      final midA2 = a.nodes[a.order[mid2]];
      final midB2 = b.nodes[b.order[mid2]];
      if (midA2 != null && midB2 != null) {
        if (!_areNodesContentEqual(midA2, midB2)) return false;
      }
    } else {
      // 노드가 적으면 전체 비교
      for (int i = 1; i < a.order.length - 1; i++) {
        final nodeA = a.nodes[a.order[i]];
        final nodeB = b.nodes[b.order[i]];
        if (nodeA == null || nodeB == null) return false;
        if (!_areNodesContentEqual(nodeA, nodeB)) return false;
      }
    }

    return true;
  }

  /// 🎯 두 노드의 핵심 내용이 같은지 빠르게 비교
  bool _areNodesContentEqual(DocumentNode a, DocumentNode b) {
    // 타입이 다르면 다름
    if (a.runtimeType != b.runtimeType) return false;

    // 타입별로 핵심 속성만 비교
    if (a is ParagraphNode && b is ParagraphNode) {
      return a.text.text == b.text.text;
    } else if (a is ImageNode && b is ImageNode) {
      return a.imageUrl == b.imageUrl;
    } else if (a is ImageRowNode && b is ImageRowNode) {
      if (a.imageUrls.length != b.imageUrls.length) return false;
      // 첫/마지막 URL만 체크 (전체 비교는 비용이 큼)
      return a.imageUrls.first == b.imageUrls.first &&
          a.imageUrls.last == b.imageUrls.last;
    } else if (a is ClipNode && b is ClipNode) {
      return a.url == b.url;
    } else if (a is LinkNode && b is LinkNode) {
      return a.url == b.url;
    } else if (a is PageViewImageNode && b is PageViewImageNode) {
      if (a.imageUrls.length != b.imageUrls.length) return false;
      return a.imageUrls.first == b.imageUrls.first &&
          a.imageUrls.last == b.imageUrls.last;
    } else if (a is AppImageNode && b is AppImageNode) {
      return a.imageUrl == b.imageUrl;
    }

    return true;
  }

  /// 🎯 플레이스홀더 노드인지 확인
  bool _isPlaceholderNode(DocumentNode? node) {
    if (node == null) return false;

    // 🎯 그룹 이미지 플레이스홀더 확인
    if (node is ImageRowNode || node is PageViewImageNode) {
      final meta = (node as dynamic).metadata as Map<String, dynamic>?;
      if (meta != null && meta['isPlaceholder'] == true) {
        return true;
      }
    }

    // 이미지 플레이스홀더 확인
    if (node is ImageNode) {
      final meta = (node as dynamic).metadata as Map<String, dynamic>?;
      if (meta != null && meta['isPlaceholder'] == true) {
        return true;
      }
      final dynamic dyn = node;
      final imageUrl = (dyn.imageUrl as String?) ?? '';
      if (imageUrl.isEmpty && meta?['localPath'] != null) {
        return true;
      }
    }

    // 비디오 플레이스홀더 확인
    if (node is ClipNode) {
      if (node.url.isEmpty && node.localPath.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// 🎯 노드가 변경되었는지 확인 (특히 ImageRowNode의 imageUrls 변경 확인)
  /// 🎯 최적화: 빠른 early return 및 효율적인 비교
  bool hasNodeChanged(DocumentNode current, DocumentNode saved) {
    // 🎯 최적화: 타입과 ID를 먼저 확인 (가장 빠른 체크)
    if (current.runtimeType != saved.runtimeType || current.id != saved.id) {
      return true;
    }

    // 🎯 최적화: 타입별로 효율적인 비교
    if (current is ImageRowNode && saved is ImageRowNode) {
      final currentUrls = current.imageUrls;
      final savedUrls = saved.imageUrls;
      if (currentUrls.length != savedUrls.length) return true;
      // 🎯 최적화: 리스트 직접 비교 (동일 참조 체크)
      if (identical(currentUrls, savedUrls)) return false;
      // 🎯 최적화: 첫/마지막만 빠르게 체크 후 전체 비교
      if (currentUrls.isNotEmpty && savedUrls.isNotEmpty) {
        if (currentUrls.first != savedUrls.first ||
            currentUrls.last != savedUrls.last) {
          return true;
        }
      }
      // 전체 비교는 마지막에 (대부분 첫/마지막에서 차이 발견)
      for (int i = 0; i < currentUrls.length; i++) {
        if (currentUrls[i] != savedUrls[i]) return true;
      }
      return false;
    }

    if (current is PageViewImageNode && saved is PageViewImageNode) {
      final currentUrls = current.imageUrls;
      final savedUrls = saved.imageUrls;
      if (currentUrls.length != savedUrls.length) return true;
      if (identical(currentUrls, savedUrls)) return false;
      if (currentUrls.isNotEmpty && savedUrls.isNotEmpty) {
        if (currentUrls.first != savedUrls.first ||
            currentUrls.last != savedUrls.last) {
          return true;
        }
      }
      for (int i = 0; i < currentUrls.length; i++) {
        if (currentUrls[i] != savedUrls[i]) return true;
      }
      return false;
    }

    // 🎯 최적화: 단일 속성 비교는 직접 비교
    if (current is ImageNode && saved is ImageNode) {
      return current.imageUrl != saved.imageUrl;
    }

    if (current is ClipNode && saved is ClipNode) {
      return current.url != saved.url;
    }

    if (current is LinkNode && saved is LinkNode) {
      return current.url != saved.url;
    }

    // 기본적으로는 변경 없음으로 간주 (ParagraphNode 등은 텍스트 변경과 무관)
    return false;
  }

  /// 🎯 스냅샷으로 문서 복원
  void restoreFromSnapshot(
    DocumentSnapshot snapshot, {
    required Editor editor,
    required Function(DocumentNode) isSpecialNode,
    required Function(DocumentNode) copyNode,
  }) {
    // 🎯 1. Selection 먼저 클리어 (iOS 핸들 에러 방지)
    try {
      editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[HistoryService] Selection 클리어 실패: $e');
    }

    // 🎯 2. 모든 노드 삭제
    while (_document.nodeCount > 0) {
      final node = _document.getNodeAt(0);
      if (node != null) {
        _document.deleteNode(node.id);
      }
    }

    // 🎯 4. 저장된 순서대로 노드 복원
    for (final id in snapshot.order) {
      final node = snapshot.nodes[id];
      if (node != null) {
        final restoredNode = copyNode(node);
        _document.insertNodeAt(_document.nodeCount, restoredNode);
      }
    }

    // 🎯 5. 제목 보호 - 제목이 없으면 빈 제목 추가
    if (_document.nodeCount == 0 ||
        (_document.getNodeAt(0) is! ParagraphNode) ||
        ((_document.getNodeAt(0) as ParagraphNode).metadata['isTitle'] !=
            true)) {
      final titleNode = ParagraphNode(
        id: '1',
        text: AttributedText(''),
        metadata: {'textAlign': 'center', 'isTitle': true},
      );
      _document.insertNodeAt(0, titleNode);
      debugPrint('[HistoryService] 🛡️ 제목 복원 (빈 제목 추가)');
    }

    // 🎯 6. 커서 숨기기
    try {
      editor.composer.clearSelection();
      debugPrint('[HistoryService] ✅ 커서 숨김');
    } catch (e) {
      debugPrint('[HistoryService] 커서 숨기기 실패: $e');
    }
  }
}
