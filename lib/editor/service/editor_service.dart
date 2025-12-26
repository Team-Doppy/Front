import 'dart:async';
import 'dart:convert';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

/// 특수 노드인지 확인하는 전역 함수
bool _isSpecialNode(DocumentNode? node) {
  if (node == null) return false;
  return node is ClipNode ||
      node is LinkNode ||
      node is ImageRowNode ||
      node is PageViewImageNode ||
      node is AppImageNode ||
      node is ImageNode;
}

/// 특수 노드 정보 저장 구조체
class _SpecialNodeInfo {
  final DocumentNode node;
  final int index;
  final DocumentSelection? selection;
  final bool isAtDownstream;

  _SpecialNodeInfo({
    required this.node,
    required this.index,
    this.selection,
    required this.isAtDownstream,
  });
}

class EditorService extends ChangeNotifier {
  late final Editor editor;
  late final MutableDocument document;
  GlobalKey? _documentLayoutKey;
  // 마지막 유효 selection 캐시 (포커스가 잠시 사라져도 사용)
  DocumentSelection? _lastSelection;

  // 특수 노드 정보를 노드 ID로 관리 (키 기반 정확한 추적)
  final Map<String, _SpecialNodeInfo> _specialNodeRegistry = {};

  // 🎯 실제 삭제 버튼으로 삭제된 노드 ID 추적 (복원 방지용)
  final Set<String> _explicitlyDeletedNodes = {};

  // 🎯 postFrameCallback으로 삭제 예약된 노드 ID들 (중복 삭제 방지, 여러 삭제 동시 대응)
  final Set<String> _pendingDeletionNodeIds = {};

  // 최근 저장 스냅샷 지문
  String? _lastSavedFingerprint;

  // 제목 스타일 전파 방지용 스냅샷(간소화 이후 미사용)
  // ignore: unused_field
  int _lastTitleTextLength = 0;

  // 🎯 Undo/Redo 히스토리 (전체 스냅샷)
  final List<_DocumentSnapshot> _undoStack = [];
  final List<_DocumentSnapshot> _redoStack = [];
  bool _isExecutingHistory = false;
  Timer? _historyTimer;
  bool _initialStateSaved = false; // 🎯 초기 상태 저장 완료 플래그 (중복 방지)
  bool _isDeletingNode = false; // 🎯 노드 삭제 중 플래그 (중복 저장 방지)
  bool _firstChangeAfterLoad = false; // 🎯 임시저장 불러온 직후 첫 변경사항 플래그

  // 🎯 NodeComponentService 참조 (노드 선택 해제용)
  BuildContext? _context;

  EditorService({
    required this.editor,
    required this.document,
    BuildContext? context,
    bool enableInitialStateSave = true, // 🎯 초기 상태 저장 활성화 여부
  }) : _context = context {
    document.addListener(_onDocumentChanged);
    editor.composer.selectionNotifier.addListener(_onSelectionChanged);

    if (enableInitialStateSave) {
      // 초기 상태 저장 (여러 프레임 후 실행하여 UI 블로킹 방지)
      // 🎯 사용자가 실제로 편집을 시작할 때까지 충분히 지연
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 첫 프레임 후 추가 지연 (UI 렌더링 완료 보장)
        // 🎯 500ms 후 저장 (사용자가 빠르게 편집해도 첫 상태 기록)
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_initialStateSaved) {
            _saveInitialState();
          }
        });
      });
    } else {
      // 읽기 모드: 초기 상태 저장 비활성화
      _initialStateSaved = true;
    }
  }

  // 🎯 BuildContext 설정 (initState 이후에 설정 가능)
  void setContext(BuildContext context) {
    _context = context;
  }

  // 🎯 초기 상태 저장 (비동기로 처리하여 UI 블로킹 방지)
  Future<void> _saveInitialState() async {
    if (_isExecutingHistory || _initialStateSaved)
      return; // 🎯 이미 저장되었으면 중복 실행 방지

    // 🎯 추가 지연 (UI 렌더링 완료 보장)
    await Future.delayed(const Duration(milliseconds: 200));

    // 🎯 노드 복사를 비동기로 처리 (각 노드 사이에 지연 추가)
    final snapshot = await _copyAllNodesAsync();
    _undoStack.add(snapshot);
    _initialStateSaved = true; // 🎯 저장 완료 표시
    debugPrint('[EditorService] 📸 초기 상태 저장 (nodes: ${snapshot.nodes.length})');
  }

  // 🎯 빈 문단인지 확인 (중복 코드 제거)
  bool _shouldSkipNode(DocumentNode node) {
    if (node is ParagraphNode) {
      final isTitle = node.metadata['isTitle'] == true;
      final isEmpty = node.text.text.trim().isEmpty;
      // 제목이 아니고 비어있으면 스킵
      return !isTitle && isEmpty;
    }
    return false;
  }

  // 🎯 모든 노드를 비동기로 deep copy (초기 상태 저장용, UI 블로킹 방지)
  Future<_DocumentSnapshot> _copyAllNodesAsync() async {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;

      // 🎯 빈 문단은 저장하지 않음 (제목 제외) - 중복 코드 제거
      if (_shouldSkipNode(node)) continue;

      // 🎯 노드 복사 전 지연 (UI 업데이트 기회 제공)
      await Future.delayed(const Duration(milliseconds: 50));

      // 🎯 노드 복사를 microtask로 분산하여 UI 블로킹 방지
      await Future.microtask(() {
        nodes[node.id] = _copyNode(node);
        order.add(node.id);
      });

      // 🎯 각 노드 복사 후 UI 업데이트 기회 제공 (Hang 방지)
      // 더 긴 지연으로 UI 스레드에 충분한 시간 제공
      if (i < document.nodeCount - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    return _DocumentSnapshot(
      nodes: nodes,
      order: order,
      selection: null, // 🎯 커서 숨기기
    );
  }

  // 🎯 모든 노드를 빠르게 비동기로 deep copy (즉시 저장용, 지연 최소화)
  Future<_DocumentSnapshot> _copyAllNodesAsyncFast() async {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;

      // 🎯 빈 문단은 저장하지 않음 (제목 제외) - 중복 코드 제거
      if (_shouldSkipNode(node)) continue;

      // 🎯 노드 복사를 microtask로 분산하여 UI 블로킹 방지
      await Future.microtask(() {
        nodes[node.id] = _copyNode(node);
        order.add(node.id);
      });

      // 🎯 각 노드 복사 후 짧은 지연 (UI 업데이트 기회 제공, Hang 방지)
      // 20개마다만 지연하여 성능 최적화 (100 노드 시 20ms)
      if (i < document.nodeCount - 1 && i % 20 == 0) {
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }

    return _DocumentSnapshot(
      nodes: nodes,
      order: order,
      selection: null, // 🎯 커서 숨기기
    );
  }

  // 🎯 현재 상태를 히스토리에 저장
  void _saveCurrentState({bool immediate = false}) {
    if (_isExecutingHistory) return;

    if (immediate) {
      // 즉시 저장 (엔터, 삭제, 이동 등) - 비동기로 처리하여 UI 블로킹 방지
      _historyTimer?.cancel();

      // 🎯 비동기로 노드 복사 (UI 블로킹 방지)
      Future.microtask(() async {
        final snapshot = await _copyAllNodesAsyncFast();
        _addToHistoryStack(snapshot, '즉시 저장');
      });
    } else {
      // 디바운싱 (텍스트 입력/삭제)
      _historyTimer?.cancel();
      debugPrint('[EditorService] ⏱️ 디바운싱 타이머 시작 (1초 후 저장 예정)');
      _historyTimer = Timer(Duration(seconds: 1), () {
        // 🎯 타이머 실행 시점에 다시 체크 (이미 실행 중이면 스킵)
        if (_isExecutingHistory) {
          debugPrint('[EditorService] ⚠️ 디바운싱 저장 스킵 (히스토리 실행 중)');
          return;
        }

        final snapshot = _copyAllNodes();

        // 중복 방지
        if (_undoStack.isNotEmpty &&
            _areSnapshotsEqual(_undoStack.last, snapshot)) {
          debugPrint('[EditorService] ⚠️ 디바운싱 저장 스킵 (중복 스냅샷)');
          return;
        }

        _addToHistoryStack(snapshot, '디바운싱 저장');
      });
    }
  }

  /// 🎯 히스토리 스택에 스냅샷 추가 (중복 코드 제거)
  void _addToHistoryStack(_DocumentSnapshot snapshot, String logLabel) {
    _undoStack.add(snapshot);
    _redoStack.clear();

    // 최대 30개까지만 유지
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }

    debugPrint(
      '[EditorService] 📸 $logLabel (total: ${_undoStack.length}, nodes: ${snapshot.nodes.length})',
    );

    // 🎯 Undo/Redo 버튼 상태 업데이트
    notifyListeners();
  }

  // 🚀 스냅샷 비교 (해시 기반 O(1) 최적화)
  bool _areSnapshotsEqual(_DocumentSnapshot a, _DocumentSnapshot b) {
    // 1. 🚀 해시 비교 (가장 빠름 - O(1))
    if (a.hashCode != b.hashCode) return false;

    // 2. 🎯 해시가 같으면 추가 검증 (해시 충돌 방지)
    if (a.order.length != b.order.length) return false;

    // 3. 🎯 빠른 샘플링 체크 (첫/마지막 노드만 확인)
    if (a.order.isNotEmpty && b.order.isNotEmpty) {
      if (a.order.first != b.order.first || a.order.last != b.order.last) {
        return false;
      }
    }

    return true;
  }

  // 🎯 ChangeLog에서 변경 추적
  void _trackChangeFromLog(DocumentChange change) {
    // 🎯 히스토리 실행 중이면 저장하지 않음 (무한 루프 방지)
    if (_isExecutingHistory) {
      debugPrint('[EditorService] ⚠️ 히스토리 실행 중 - 변경 추적 스킵: $change');
      return;
    }

    try {
      // 🎯 히스토리가 비어있으면 현재 상태를 초기 상태로 저장 (임시저장 불러온 직후에도 동작)
      if (_undoStack.isEmpty) {
        debugPrint('[EditorService] 🎯 히스토리 비어있음 - 현재 상태를 초기 상태로 저장');
        _saveCurrentState(immediate: true);
        // 🎯 초기 상태 저장 후에도 변경 이벤트는 계속 처리해야 함 (return 하지 않음)
      }

      // TextInsertionEvent, TextDeletedEvent - 디바운싱 적용 (1초 후 저장)
      // 🎯 단, 임시저장 불러온 직후 첫 변경사항만 즉시 저장, 그 다음부터는 디바운싱
      if (change is TextInsertionEvent || change is TextDeletedEvent) {
        if (_firstChangeAfterLoad) {
          // 🎯 임시저장 불러온 직후 첫 변경사항은 즉시 저장 (히스토리 누락 방지)
          debugPrint('[EditorService] 🎯 임시저장 불러온 직후 첫 변경 - 즉시 저장');
          _saveCurrentState(immediate: true);
          _firstChangeAfterLoad = false; // 🎯 플래그 해제 (다음부터는 디바운싱)
        } else {
          // 🎯 그 다음부터는 디바운싱 적용
          _saveCurrentState(immediate: false);
        }
        return;
      }

      // 🎯 NodeRemovedEvent는 _deleteNode에서 이미 삭제 전 상태를 저장했으므로 중복 저장 방지
      if (change is NodeRemovedEvent) {
        // 🎯 삭제 전 상태가 이미 저장되었으면 삭제 후 상태도 저장 (undo/redo를 위해)
        if (_isDeletingNode) {
          _isDeletingNode = false; // 플래그 해제
          // 🎯 삭제 후 상태 저장 (redo를 위해)
          _saveCurrentState(immediate: true);
        }
        // 🎯 _deleteNode에서 저장하지 않은 경우 (다른 경로로 삭제된 경우)는 즉시 저장
        else {
          _saveCurrentState(immediate: true);
        }
        return;
      }

      // 🎯 NodeInsertedEvent (엔터, 이미지/영상 추가), NodeChangeEvent (노드 변경), NodeMovedEvent (이동) - 즉시 저장!
      if (change is NodeInsertedEvent ||
          change is NodeChangeEvent ||
          change is NodeMovedEvent) {
        _saveCurrentState(immediate: true);
        return;
      }
    } catch (e) {
      debugPrint('[EditorService] 변경 추적 실패: $e');
    }
  }

  // 🎯 모든 노드를 deep copy (커서는 저장하지 않음)
  _DocumentSnapshot _copyAllNodes() {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;

      // 🎯 빈 문단은 저장하지 않음 (제목 제외) - 중복 코드 제거
      if (_shouldSkipNode(node)) continue;

      nodes[node.id] = _copyNode(node);
      order.add(node.id);
    }

    return _DocumentSnapshot(
      nodes: nodes,
      order: order,
      selection: null, // 🎯 커서 숨기기
    );
  }

  // 🎯 노드 deep copy
  DocumentNode _copyNode(DocumentNode node) {
    if (node is ParagraphNode) {
      // metadata에는 textAlign, isTitle, fontFamily 등이 포함됨
      final copiedMetadata = Map<String, dynamic>.from(node.metadata);
      final isMention = copiedMetadata['mention'] == true;

      // 🎯 AttributedText 전체 복사 (모든 스타일 유지: bold, italic, color, font, highlight, spoiler 등)
      final AttributedText attributed = node.text.copyText(0, node.text.length);

      // 🎯 멘션 노드인데 볼드가 없으면 추가
      if (isMention && node.text.text.isNotEmpty) {
        final hasBold =
            attributed
                .getAttributionSpansInRange(
                  attributionFilter: (attr) => attr == boldAttribution,
                  range: SpanRange(0, node.text.text.length - 1),
                )
                .isNotEmpty;

        if (!hasBold) {
          attributed.addAttribution(
            boldAttribution,
            SpanRange(0, node.text.text.length - 1),
          );
        }
      }

      return ParagraphNode(
        id: node.id,
        text: attributed,
        metadata: copiedMetadata, // ✅ 정렬, 제목 여부 등 모두 복사됨
      );
    }
    if (node is ImageNode) {
      return AppImageNode(
        id: node.id,
        imageUrl: node.imageUrl,
        altText: node.altText,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is ImageRowNode) {
      return ImageRowNode(
        id: node.id,
        imageUrls: List<String>.from(node.imageUrls),
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is LinkNode) {
      return LinkNode(
        id: node.id,
        url: node.url,
        title: node.title,
        description: node.description,
        thumbnailUrl: node.thumbnailUrl,
      );
    }
    if (node is ClipNode) {
      final cleanLabel = node.label;
      return ClipNode(
        id: node.id,
        url: node.url,
        label: cleanLabel,
        colorHex: node.colorHex,
        localPath: node.localPath,
        thumbnailPath: node.thumbnailPath,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    if (node is DividerNode) {
      return DividerNode(id: node.id);
    }
    // 기본: 그대로 반환
    return node;
  }

  void setDocumentLayoutKey(GlobalKey key) {
    _documentLayoutKey = key;
  }

  GlobalKey? get documentLayoutKey => _documentLayoutKey;

  // 🎯 문서의 모든 특수 노드를 레지스트리에 등록 (임시저장 불러오기 등에서 사용)
  void registerAllSpecialNodes() {
    _specialNodeRegistry.clear();
    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node != null && _isSpecialNode(node)) {
        _specialNodeRegistry[node.id] = _SpecialNodeInfo(
          node: _copyNode(node),
          index: i,
          selection: null,
          isAtDownstream: false,
        );
        debugPrint(
          '[EditorService] ✅ 특수 노드 레지스트리 등록: nodeId=${node.id}, index=$i',
        );
      }
    }
  }

  // 🎯 레지스트리에서 삭제된 노드 정리 (메모리 누수 방지)
  void _cleanupRegistry() {
    final existingNodeIds = <String>{};
    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node != null) {
        existingNodeIds.add(node.id);
      }
    }

    // 문서에 없는 노드 ID는 레지스트리에서 제거
    final toRemove = <String>[];
    for (final id in _specialNodeRegistry.keys) {
      if (!existingNodeIds.contains(id)) {
        toRemove.add(id);
      }
    }

    for (final id in toRemove) {
      _specialNodeRegistry.remove(id);
      debugPrint('[EditorService] 🧹 레지스트리 정리: 삭제된 노드 제거 $id');
    }

    // 명시적 삭제 목록도 정리
    _explicitlyDeletedNodes.removeWhere((id) => !existingNodeIds.contains(id));
  }

  /// 🎯 특수 노드를 레지스트리에서 제거 (외부에서 호출 가능)
  /// [explicitlyDeleted]가 true이면 실제 삭제 버튼으로 삭제된 것으로 표시하여 복원 방지
  void removeSpecialNodeFromRegistry(
    String nodeId, {
    bool explicitlyDeleted = false,
  }) {
    if (_specialNodeRegistry.containsKey(nodeId)) {
      debugPrint(
        '[EditorService] 특수 노드 레지스트리에서 제거: nodeId=$nodeId, explicitlyDeleted=$explicitlyDeleted',
      );
      _specialNodeRegistry.remove(nodeId);
    }

    // 🎯 실제 삭제 버튼으로 삭제된 경우 추적
    if (explicitlyDeleted) {
      _explicitlyDeletedNodes.add(nodeId);
      // 🎯 일정 시간 후 자동 정리 (메모리 누수 방지, 빠른 연속 삭제 대응)
      Future.delayed(const Duration(seconds: 30), () {
        _explicitlyDeletedNodes.remove(nodeId);
      });
    }
  }

  // 🎯 Undo 가능 여부
  bool get canUndo => _undoStack.length > 1;

  // 🎯 Redo 가능 여부
  bool get canRedo => _redoStack.isNotEmpty;

  // 🎯 즉시 히스토리 저장 (외부에서 호출 가능)
  void saveHistoryNow() {
    _historyTimer?.cancel();
    _saveCurrentState(immediate: true);
  }

  /// 🎯 노드 삭제 전 상태를 동기적으로 저장 (삭제 전 상태 확실히 보존)
  /// NodeRemovedEvent가 비동기로 처리되기 전에 삭제 전 상태를 저장
  void saveHistoryBeforeDelete() {
    if (_isExecutingHistory) return;

    // 🎯 삭제 중 플래그 설정 (NodeRemovedEvent에서 중복 저장 방지)
    _isDeletingNode = true;

    // 🎯 동기적으로 노드 복사 (삭제 전 상태를 확실히 저장)
    final snapshot = _copyAllNodes();
    _addToHistoryStack(snapshot, '노드 삭제 전 상태 저장');
  }

  // 🎯 Undo 실행
  void undo() {
    _executeHistoryOperation(
      canExecute: canUndo,
      errorMessage: 'Undo 불가 (첫 상태)',
      operation: () {
        // 🎯 현재 상태를 redo 스택에 저장
        final currentSnapshot = _undoStack.removeLast();
        _redoStack.add(currentSnapshot);

        // 🎯 이전 상태로 복원
        final previousSnapshot = _undoStack.last;
        _restoreFromSnapshot(previousSnapshot);

        // 🎯 초기 상태로 복원된 경우에만 redo 스택 비우기
        // 🎯 _undoStack.length == 1이면 초기 상태만 남은 것이므로 초기 상태로 복원된 것
        if (_undoStack.isNotEmpty && _undoStack.length == 1) {
          _redoStack.clear();
        }
      },
      onError: () {
        // 🎯 에러 발생 시 스택 복구 시도
        if (_redoStack.isNotEmpty) {
          try {
            _undoStack.add(_redoStack.removeLast());
          } catch (_) {}
        }
      },
    );
  }

  // 🎯 Redo 실행
  void redo() {
    _executeHistoryOperation(
      canExecute: canRedo,
      errorMessage: 'Redo 불가 (없음)',
      operation: () {
        // 🎯 Redo 스택에서 다음 상태 가져오기
        final nextSnapshot = _redoStack.removeLast();
        _undoStack.add(nextSnapshot);

        // 🎯 다음 상태로 복원
        _restoreFromSnapshot(nextSnapshot);

        debugPrint(
          '[EditorService] ➡️ Redo 완료 (남은 redo: ${_redoStack.length})',
        );

        // 🎯 레지스트리 정리 (삭제된 노드 제거)
        _cleanupRegistry();
      },
      onError: () {
        // 🎯 에러 발생 시 스택 복구 시도
        if (_undoStack.length > 1) {
          try {
            _redoStack.add(_undoStack.removeLast());
          } catch (_) {}
        }
      },
    );
  }

  /// 🎯 히스토리 작업 실행 공통 로직 (undo/redo 중복 코드 제거)
  void _executeHistoryOperation({
    required bool canExecute,
    required String errorMessage,
    required VoidCallback operation,
    VoidCallback? onError,
  }) {
    // 🎯 이미 실행 중이면 무시 (연속 실행 방지)
    if (_isExecutingHistory) {
      debugPrint('[EditorService] ⚠️ 히스토리 실행 중 - 무시');
      return;
    }

    if (!canExecute) {
      debugPrint('[EditorService] ❌ $errorMessage');
      return;
    }

    try {
      _isExecutingHistory = true;
      _historyTimer?.cancel();
      operation();
    } catch (e) {
      debugPrint('[EditorService] 히스토리 작업 실패: $e');
      onError?.call();
    } finally {
      _isExecutingHistory = false;
      notifyListeners();
    }
  }

  /// 🗑️ Undo/Redo 히스토리 완전 초기화
  void clearHistory() {
    _historyTimer?.cancel();
    _undoStack.clear();
    _redoStack.clear();
    _initialStateSaved = false;
    _firstChangeAfterLoad = false; // 🎯 플래그도 초기화
    debugPrint('[EditorService] 🗑️ 히스토리 클리어 완료');
    notifyListeners();
  }

  /// 🎯 초기 상태를 동기적으로 저장 (임시저장 불러올 때 사용)
  /// 비동기로 실행되면 불러온 직후 노드 삭제 시 히스토리가 제대로 저장되지 않음
  void saveInitialStateSync() {
    if (_isExecutingHistory) return;

    // 🎯 동기적으로 노드 복사 (임시저장 불러올 때는 즉시 저장 필요)
    final snapshot = _copyAllNodes();
    _addToHistoryStack(snapshot, '초기 상태 동기 저장 완료');
    _initialStateSaved = true;
    _firstChangeAfterLoad = true; // 🎯 임시저장 불러온 직후 첫 변경사항 플래그 설정
  }

  // 🎯 스냅샷으로 문서 복원
  void _restoreFromSnapshot(_DocumentSnapshot snapshot) {
    // 🎯 1. Selection 먼저 클리어 (iOS 핸들 에러 방지)
    try {
      editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[EditorService] Selection 클리어 실패: $e');
    }

    // 🎯 2. 레지스트리 및 명시적 삭제 목록 초기화 (복원 전 정리)
    _specialNodeRegistry.clear();
    _explicitlyDeletedNodes.clear();

    // 🎯 3. 모든 노드 삭제
    while (document.nodeCount > 0) {
      final node = document.getNodeAt(0);
      if (node != null) {
        document.deleteNode(node.id);
      }
    }

    // 🎯 4. 저장된 순서대로 노드 복원
    for (final id in snapshot.order) {
      final node = snapshot.nodes[id];
      if (node != null) {
        final restoredNode = _copyNode(node);
        document.insertNodeAt(document.nodeCount, restoredNode);

        // 🎯 복원된 노드가 특수 노드이면 레지스트리에 등록
        if (_isSpecialNode(restoredNode)) {
          final nodeIndex = document.nodeCount - 1;
          _specialNodeRegistry[restoredNode.id] = _SpecialNodeInfo(
            node: _copyNode(restoredNode),
            index: nodeIndex,
            selection: null,
            isAtDownstream: false,
          );
        }
      }
    }

    // 🎯 4. 제목 보호 - 제목이 없으면 빈 제목 추가
    if (document.nodeCount == 0 ||
        (document.getNodeAt(0) is! ParagraphNode) ||
        ((document.getNodeAt(0) as ParagraphNode).metadata['isTitle'] !=
            true)) {
      final titleNode = ParagraphNode(
        id: '1',
        text: AttributedText(''),
        metadata: {'textAlign': 'center', 'isTitle': true},
      );
      document.insertNodeAt(0, titleNode);
      debugPrint('[EditorService] 🛡️ 제목 복원 (빈 제목 추가)');
    }

    // 🎯 5. 커서 숨기기
    try {
      editor.composer.clearSelection();
      debugPrint('[EditorService] ✅ 커서 숨김');
    } catch (e) {
      debugPrint('[EditorService] 커서 숨기기 실패: $e');
    }
  }

  // 문서 변경 리스너: 구조가 변했을 때만 마진 재계산
  void _onDocumentChanged(DocumentChangeLog changeLog) {
    final change = changeLog.changes[0];
    debugPrint('changeLog.changes[0]: $change');

    // 🎯 변경된 노드 추적
    _trackChangeFromLog(change);

    // 🎯 텍스트 입력/삭제 시 노드 선택 자동 해제 (가볍게 처리)
    if ((change is TextInsertionEvent || change is TextDeletedEvent) &&
        _context != null) {
      try {
        final nodeService = _context!.read<NodeComponentService>();
        if (nodeService.selectedNodeId != null) {
          nodeService.clearSelectionSilently(); // 조용히 해제 (불필요한 리빌드 방지)
          debugPrint('[EditorService] 텍스트 변경 감지 -> 노드 선택 자동 해제');
        }
      } catch (e) {
        // NodeComponentService가 없을 수 있음 (무시)
      }
    }

    // 🎯 멘션 노드에서 텍스트 입력 시, 멘션 부분만 볼드로 유지하고 나머지는 일반 텍스트로 처리
    if (change is TextInsertionEvent) {
      try {
        String? targetNodeId;
        try {
          targetNodeId = (change as dynamic).nodeId as String?;
        } catch (_) {}

        if (targetNodeId == null) {
          final selection = editor.composer.selectionNotifier.value;
          if (selection != null && selection.extent.nodeId.isNotEmpty) {
            targetNodeId = selection.extent.nodeId;
          }
        }

        if (targetNodeId != null && targetNodeId.isNotEmpty) {
          final node = document.getNodeById(targetNodeId);
          if (node != null && node is ParagraphNode) {
            final isMention = node.metadata['mention'] == true;
            final List<dynamic> usernames =
                (node.metadata['usernames'] as List?) ?? const [];

            // 멘션 노드이고 usernames가 있으면 처리
            if (isMention && usernames.isNotEmpty) {
              // 멘션 텍스트 길이 계산 (@username)
              final mentionText = '@${usernames.first}';
              final mentionLength = mentionText.length;

              // 현재 노드의 텍스트 길이 확인
              final currentText = node.text.text;

              // 멘션 텍스트 이후에 텍스트가 입력되었는지 확인
              if (currentText.length > mentionLength) {
                // 멘션 부분 이후의 텍스트에서 볼드 attribution 제거
                final savedNodeId = targetNodeId; // null이 아님을 보장 (위에서 체크함)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  try {
                    final updatedNode = document.getNodeById(savedNodeId);
                    if (updatedNode != null && updatedNode is ParagraphNode) {
                      final text = updatedNode.text;
                      final textLength = text.text.length;

                      // 멘션 부분 이후의 텍스트에서만 볼드 제거
                      if (textLength > mentionLength) {
                        // 새로운 AttributedText 생성
                        final newText = AttributedText(text.text);

                        // 기존 attribution 복사 (멘션 부분만)
                        for (
                          int i = 0;
                          i < mentionLength && i < textLength;
                          i++
                        ) {
                          final attributions = text.getAllAttributionsAt(i);
                          for (final attr in attributions) {
                            newText.addAttribution(attr, SpanRange(i, i));
                          }
                        }

                        // 멘션 부분 이후는 볼드를 제외한 다른 attribution만 복사
                        for (int i = mentionLength; i < textLength; i++) {
                          final attributions = text.getAllAttributionsAt(i);
                          for (final attr in attributions) {
                            // 볼드가 아닌 attribution만 추가
                            if (attr != boldAttribution) {
                              newText.addAttribution(attr, SpanRange(i, i));
                            }
                          }
                        }

                        // 노드 업데이트
                        final newNode = ParagraphNode(
                          id: updatedNode.id,
                          text: newText,
                          metadata: Map<String, dynamic>.from(
                            updatedNode.metadata,
                          ),
                        );

                        editor.execute([
                          ReplaceNodeRequest(
                            existingNodeId: updatedNode.id,
                            newNode: newNode,
                          ),
                        ]);
                      }
                    }
                  } catch (e) {
                    debugPrint('[EditorService] 멘션 텍스트 스타일 조정 실패: $e');
                  }
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[EditorService] 멘션 텍스트 입력 처리 중 오류: $e');
      }
    }

    // 🎯 멘션 문단(ParagraphNode with metadata.mention == true)에서 삭제가 발생하면
    // 노드를 한 번에 삭제하도록 처리
    if (change is TextDeletedEvent) {
      try {
        // TextDeletedEvent에서 nodeId 가져오기
        String? targetNodeId;
        try {
          targetNodeId = (change as dynamic).nodeId as String?;
        } catch (_) {}

        // 현재 selection에서 가져오기
        if (targetNodeId == null) {
          final selection = editor.composer.selectionNotifier.value;
          if (selection != null && selection.extent.nodeId.isNotEmpty) {
            targetNodeId = selection.extent.nodeId;
          }
        }

        if (targetNodeId != null && targetNodeId.isNotEmpty) {
          final node = document.getNodeById(targetNodeId);
          debugPrint(
            '[EditorService] TextDeletedEvent: targetNodeId=$targetNodeId, node=${node?.runtimeType}',
          );

          // 🎯 노드가 존재하지 않으면 처리 중단
          if (node == null) {
            debugPrint(
              '[EditorService] ⚠️ TextDeletedEvent: 노드가 존재하지 않음: $targetNodeId',
            );
            return;
          }

          // 특수 노드 위의 ParagraphNode에서 텍스트 삭제 시 특수 노드 정보 저장
          if (node is ParagraphNode) {
            final nodeIndex = document.getNodeIndexById(targetNodeId);
            debugPrint(
              '[EditorService] TextDeletedEvent: nodeIndex=$nodeIndex, text="${node.text.text}", isEmpty=${node.text.text.trim().isEmpty}',
            );

            // 🎯 인덱스 유효성 확인
            if (nodeIndex < 0 || nodeIndex >= document.nodeCount) {
              debugPrint(
                '[EditorService] ⚠️ TextDeletedEvent: 잘못된 인덱스: $nodeIndex',
              );
              return;
            }

            if (nodeIndex > 0) {
              final prevNode = document.getNodeAt(nodeIndex - 1);
              debugPrint(
                '[EditorService] TextDeletedEvent: prevNode=${prevNode?.runtimeType}, id=${prevNode?.id}',
              );

              if (prevNode != null && _isSpecialNode(prevNode)) {
                // 🎯 플레이스홀더도 레지스트리에 등록 (선택 시 툴바 변경을 위해)
                debugPrint(
                  '[EditorService] 이전 노드가 특수 노드임: ${prevNode.runtimeType}',
                );

                // 🎯 삭제 예약/명시적 삭제된 노드는 등록하지 않음
                if (_explicitlyDeletedNodes.contains(prevNode.id) ||
                    _pendingDeletionNodeIds.contains(prevNode.id)) {
                  debugPrint(
                    '[EditorService] ⚠️ 삭제 예약/명시적 삭제된 노드 - 등록 스킵: ${prevNode.id}',
                  );
                } else {
                  // 🎯 이전 노드가 특수 노드이면 항상 정보 저장 (비어있지 않아도 저장)
                  // 사용자가 계속 텍스트를 삭제하다가 특수 노드까지 삭제할 수 있으므로
                  final currentSelection =
                      editor.composer.selectionNotifier.value;
                  final isAtDownstream =
                      currentSelection != null &&
                      currentSelection.extent.nodeId == prevNode.id &&
                      currentSelection.extent.nodePosition
                          is UpstreamDownstreamNodePosition &&
                      currentSelection.extent.nodePosition ==
                          const UpstreamDownstreamNodePosition.downstream();

                  _specialNodeRegistry[prevNode.id] = _SpecialNodeInfo(
                    node: _copyNode(prevNode),
                    index: nodeIndex - 1,
                    selection: currentSelection,
                    isAtDownstream: isAtDownstream,
                  );

                  debugPrint(
                    '[EditorService] ✅ 특수 노드 정보 등록: nodeId=${prevNode.id}, index=${nodeIndex - 1}, isAtDownstream=$isAtDownstream, paragraphText="${node.text.text}"',
                  );
                }
              } else {
                debugPrint(
                  '[EditorService] 이전 노드가 특수 노드가 아님: ${prevNode.runtimeType}',
                );
              }
            } else {
              debugPrint('[EditorService] nodeIndex가 0 이하: $nodeIndex');
            }

            // 🎯 멘션 노드 처리 (같은 ParagraphNode 블록 내에서 처리)
            final isMention = node.metadata['mention'] == true;
            final List<dynamic> usernames =
                (node.metadata['usernames'] as List?) ?? const [];

            // 멘션이고 usernames가 있으면 처리
            if (isMention && usernames.isNotEmpty) {
              final isMention = node.metadata['mention'] == true;
              final List<dynamic> usernames =
                  (node.metadata['usernames'] as List?) ?? const [];

              // 멘션이고 usernames가 있으면 처리
              if (isMention && usernames.isNotEmpty) {
                // 멘션 텍스트 길이 계산 (@username)
                final mentionText = '@${usernames.first}';
                final mentionLength = mentionText.length;

                // 삭제 이벤트에서 삭제된 정보 확인
                int? deletedOffset;
                int? deletedLength;
                try {
                  deletedOffset = (change as dynamic).offset as int?;
                  deletedLength = (change as dynamic).length as int?;
                } catch (_) {}

                // 현재 커서 위치 확인 (삭제 후 위치)
                final selection = editor.composer.selectionNotifier.value;
                int? cursorOffset;
                if (selection != null &&
                    selection.extent.nodeId == targetNodeId) {
                  try {
                    cursorOffset =
                        (selection.extent.nodePosition as TextNodePosition)
                            .offset;
                  } catch (_) {}
                }

                // 현재 텍스트 길이 확인 (삭제 후)
                final currentText = node.text.text;

                // 삭제 전 텍스트 길이 추정
                final previousTextLength =
                    currentText.length + (deletedLength ?? 1);

                // 삭제 위치 확인
                // 삭제된 위치가 멘션 텍스트 이후에 있으면 일반적인 텍스트 삭제 동작 허용
                // 또는 삭제 전 텍스트가 멘션보다 길었고, 삭제 후 커서가 멘션 텍스트 길이와 같거나 크면 일반 삭제
                final isDeletingAfterMention =
                    (deletedOffset != null && deletedOffset >= mentionLength) ||
                    (previousTextLength > mentionLength &&
                        cursorOffset != null &&
                        cursorOffset >= mentionLength);

                if (isDeletingAfterMention) {
                  // 멘션 텍스트 이후에서 삭제하는 경우 일반 삭제 동작 허용
                  debugPrint(
                    '[EditorService] 멘션 텍스트 이후에서 삭제: deletedOffset=$deletedOffset, cursorOffset=$cursorOffset, mentionLength=$mentionLength',
                  );
                  return;
                }

                // 멘션 텍스트 내부에서 삭제가 발생한 경우
                // 멘션 이후에 텍스트가 남아있으면 멘션 부분만 제거하고 나머지 유지
                // 멘션 텍스트만 있으면 노드 전체 삭제
                if (currentText.length > mentionLength) {
                  // 멘션 이후에 텍스트가 남아있음 → 멘션 부분만 제거하고 나머지 유지
                  final remainingText = currentText.substring(mentionLength);

                  final nodeIndex = document.getNodeIndexById(targetNodeId);
                  if (nodeIndex == -1) {
                    debugPrint('[EditorService] 멘션 부분 삭제: 유효하지 않은 노드 인덱스');
                    return;
                  }

                  // 나머지 텍스트의 attribution 복사 (볼드 제외)
                  final newText = AttributedText(remainingText);
                  final originalText = node.text;

                  for (
                    int i = mentionLength;
                    i < originalText.text.length;
                    i++
                  ) {
                    final attributions = originalText.getAllAttributionsAt(i);
                    for (final attr in attributions) {
                      // 볼드가 아닌 attribution만 추가
                      if (attr != boldAttribution) {
                        final newIndex = i - mentionLength;
                        if (newIndex >= 0 && newIndex < remainingText.length) {
                          newText.addAttribution(
                            attr,
                            SpanRange(newIndex, newIndex),
                          );
                        }
                      }
                    }
                  }

                  // 일반 문단으로 변환 (mention 메타데이터 제거)
                  final newParagraph = ParagraphNode(
                    id: targetNodeId,
                    text: newText,
                    metadata: {
                      'textAlign': node.metadata['textAlign'] ?? 'center',
                    },
                  );

                  // 노드 교체
                  editor.execute([
                    ReplaceNodeRequest(
                      existingNodeId: targetNodeId,
                      newNode: newParagraph,
                    ),
                  ]);

                  // 커서를 나머지 텍스트의 시작 위치로 이동
                  final savedNodeId = targetNodeId;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    try {
                      editor.execute([
                        ChangeSelectionRequest(
                          DocumentSelection.collapsed(
                            position: DocumentPosition(
                              nodeId: savedNodeId,
                              nodePosition: const TextNodePosition(offset: 0),
                            ),
                          ),
                          SelectionChangeType.placeCaret,
                          SelectionReason.userInteraction,
                        ),
                      ]);
                    } catch (e) {
                      debugPrint('[EditorService] 커서 이동 실패: $e');
                    }
                  });

                  // 🎯 editor.execute()가 이미 document 리스너를 호출하므로 notifyListeners() 불필요
                  return;
                }
                // 멘션 텍스트만 있으면 (currentText.length <= mentionLength)
                // 아래의 노드 전체 삭제 로직으로 진행

                // 멘션 노드 전체 삭제 로직 (나머지 텍스트가 없을 때만)
                final nodeIndex = document.getNodeIndexById(targetNodeId);

                // 유효한 인덱스인지 확인
                if (nodeIndex == -1) {
                  debugPrint('[EditorService] 멘션 삭제: 유효하지 않은 노드 인덱스');
                  return;
                }

                // 다음 노드로 커서 이동할 위치 찾기
                DocumentPosition? targetPosition;

                // 다음 노드 확인
                if (nodeIndex + 1 < document.nodeCount) {
                  try {
                    final nextNode = document.getNodeAt(nodeIndex + 1);
                    if (nextNode != null &&
                        nextNode is ParagraphNode &&
                        nextNode.metadata['isTitle'] != true) {
                      targetPosition = DocumentPosition(
                        nodeId: nextNode.id,
                        nodePosition: const TextNodePosition(offset: 0),
                      );
                    }
                  } catch (e) {
                    debugPrint('[EditorService] 다음 노드 확인 실패: $e');
                  }
                }

                // 이전 노드로 이동
                if (targetPosition == null && nodeIndex > 1) {
                  try {
                    final prevNode = document.getNodeAt(nodeIndex - 1);
                    if (prevNode != null &&
                        prevNode is ParagraphNode &&
                        prevNode.metadata['isTitle'] != true) {
                      final prevText = prevNode.text.text;
                      targetPosition = DocumentPosition(
                        nodeId: prevNode.id,
                        nodePosition: TextNodePosition(
                          offset: prevText.length.clamp(0, prevText.length),
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('[EditorService] 이전 노드 확인 실패: $e');
                  }
                }

                // 노드 삭제 전에 커서 위치 저장
                final savedTargetPosition = targetPosition;
                final savedNodeIndex = nodeIndex;

                // 🎯 노드가 여전히 존재하는지 확인 (이중 삭제 방지)
                if (document.getNodeById(targetNodeId) == null) {
                  debugPrint('[EditorService] ⚠️ 멘션 노드가 이미 삭제됨: $targetNodeId');
                  return;
                }

                // 🎯 먼저 커서를 클리어하여 IME 위치 매핑 오류 방지
                try {
                  editor.composer.clearSelection();
                } catch (e) {
                  debugPrint('[EditorService] 커서 클리어 실패: $e');
                }

                // 노드 삭제
                try {
                  document.deleteNode(targetNodeId);
                  debugPrint('[EditorService] 멘션 노드 삭제 완료: $targetNodeId');
                } catch (e) {
                  debugPrint('[EditorService] 멘션 노드 삭제 실패: $e');
                  return;
                }

                // 🎯 커서 이동 (삭제 후 여러 프레임을 기다려 안전하게 처리)
                if (savedTargetPosition != null) {
                  // 첫 번째 프레임: 문서 구조 안정화 대기
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    // 두 번째 프레임: IME 초기화 대기
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      // 세 번째 프레임: 안전하게 커서 이동
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        try {
                          // 삭제 후에도 노드가 존재하는지 확인
                          final targetNode = document.getNodeById(
                            savedTargetPosition.nodeId,
                          );
                          if (targetNode != null &&
                              targetNode is ParagraphNode) {
                            // 노드가 여전히 존재하고 유효한지 확인
                            final currentIndex = document.getNodeIndexById(
                              savedTargetPosition.nodeId,
                            );
                            if (currentIndex != -1) {
                              editor.execute([
                                ChangeSelectionRequest(
                                  DocumentSelection.collapsed(
                                    position: savedTargetPosition,
                                  ),
                                  SelectionChangeType.placeCaret,
                                  SelectionReason.userInteraction,
                                ),
                              ]);
                              return;
                            }
                          }

                          // 타겟 노드가 없으면 안전한 위치로 이동
                          // 삭제된 노드의 인덱스를 기준으로 다음 또는 이전 노드 찾기
                          DocumentPosition? fallbackPosition;

                          // 삭제된 노드의 다음 위치 확인
                          if (savedNodeIndex < document.nodeCount) {
                            try {
                              final nextNode = document.getNodeAt(
                                savedNodeIndex,
                              );
                              if (nextNode != null &&
                                  nextNode is ParagraphNode &&
                                  nextNode.metadata['isTitle'] != true) {
                                fallbackPosition = DocumentPosition(
                                  nodeId: nextNode.id,
                                  nodePosition: const TextNodePosition(
                                    offset: 0,
                                  ),
                                );
                              }
                            } catch (_) {}
                          }

                          // 이전 노드 확인
                          if (fallbackPosition == null && savedNodeIndex > 1) {
                            try {
                              final prevNode = document.getNodeAt(
                                savedNodeIndex - 1,
                              );
                              if (prevNode != null &&
                                  prevNode is ParagraphNode &&
                                  prevNode.metadata['isTitle'] != true) {
                                final prevText = prevNode.text.text;
                                fallbackPosition = DocumentPosition(
                                  nodeId: prevNode.id,
                                  nodePosition: TextNodePosition(
                                    offset: prevText.length.clamp(
                                      0,
                                      prevText.length,
                                    ),
                                  ),
                                );
                              }
                            } catch (_) {}
                          }

                          // 최후의 수단: 문서 끝으로 이동
                          if (fallbackPosition == null &&
                              document.nodeCount > 0) {
                            try {
                              final lastNode = document.getNodeAt(
                                document.nodeCount - 1,
                              );
                              if (lastNode is ParagraphNode &&
                                  lastNode.metadata['isTitle'] != true) {
                                final lastText = lastNode.text.text;
                                fallbackPosition = DocumentPosition(
                                  nodeId: lastNode.id,
                                  nodePosition: TextNodePosition(
                                    offset: lastText.length.clamp(
                                      0,
                                      lastText.length,
                                    ),
                                  ),
                                );
                              }
                            } catch (_) {}
                          }

                          if (fallbackPosition != null) {
                            editor.execute([
                              ChangeSelectionRequest(
                                DocumentSelection.collapsed(
                                  position: fallbackPosition,
                                ),
                                SelectionChangeType.placeCaret,
                                SelectionReason.userInteraction,
                              ),
                            ]);
                          }
                        } catch (e, stackTrace) {
                          debugPrint('[EditorService] 커서 이동 실패: $e');
                          debugPrint('[EditorService] 스택 트레이스: $stackTrace');
                        }
                      });
                    });
                  });
                } else {
                  // 커서 위치가 없으면 그냥 클리어만 유지
                  debugPrint('[EditorService] 멘션 삭제: 커서 이동 위치 없음, 클리어 상태 유지');
                }

                // 🎯 document.deleteNode()이 이미 document 리스너를 호출하므로 notifyListeners() 불필요
                return;
              }
            }
          }
        }
      } catch (e, stackTrace) {
        debugPrint('[EditorService] 멘션 삭제 처리 중 오류: $e');
        debugPrint('[EditorService] 스택 트레이스: $stackTrace');
      }
    }

    if (change is NodeRemovedEvent) {
      if (getEditingIndex() == 0) {
        // 타이틀 문단 삭제 방지
        _ensureTitleAtTop();
        // 🎯 _ensureTitleAtTop()이 document.insertNodeAt()을 호출하므로 notifyListeners() 불필요
        return;
      }

      final removedNodeId = change.nodeId;
      debugPrint('[EditorService] NodeRemovedEvent: nodeId=$removedNodeId');

      // 🎯 마지막에 한 번만 notifyListeners 호출하기 위한 플래그
      bool shouldNotify = false;

      // 🎯 삭제된 노드가 빈 ParagraphNode인지 확인
      // 빈 ParagraphNode가 삭제되면 이전/다음 노드가 특수 노드인지 확인하고 레지스트리에 등록
      final isRemovedNodeSpecial =
          removedNodeId.startsWith('imageRow_') ||
          removedNodeId.startsWith('clip_') ||
          removedNodeId.startsWith('link_') ||
          removedNodeId.startsWith('img_') ||
          removedNodeId.startsWith('group_'); // 🎯 PageViewImageNode 추가

      if (!isRemovedNodeSpecial) {
        // 삭제된 노드가 특수 노드가 아니면, 빈 ParagraphNode일 가능성이 높음
        // 현재 selection에서 이전/다음 노드 확인
        final selection = editor.composer.selectionNotifier.value;
        if (selection != null) {
          final currentNodeId = selection.extent.nodeId;
          final currentNodeIndex = document.getNodeIndexById(currentNodeId);

          // 🎯 인덱스 유효성 확인
          if (currentNodeIndex < 0 || currentNodeIndex >= document.nodeCount) {
            debugPrint('[EditorService] ⚠️ 잘못된 현재 노드 인덱스: $currentNodeIndex');
            return;
          }

          // 이전 노드가 특수 노드인지 확인 (빈 ParagraphNode 위에 특수 노드가 있었을 가능성)
          if (currentNodeIndex > 0) {
            final prevNode = document.getNodeAt(currentNodeIndex - 1);
            if (prevNode != null && _isSpecialNode(prevNode)) {
              // 🎯 플레이스홀더도 레지스트리에 등록 (선택 시 툴바 변경을 위해)
              // 🎯 삭제 예약/명시적 삭제된 노드는 등록하지 않음
              if (!_specialNodeRegistry.containsKey(prevNode.id) &&
                  !_explicitlyDeletedNodes.contains(prevNode.id) &&
                  !_pendingDeletionNodeIds.contains(prevNode.id)) {
                final isAtDownstream =
                    selection.extent.nodeId == prevNode.id &&
                    selection.extent.nodePosition
                        is UpstreamDownstreamNodePosition &&
                    selection.extent.nodePosition ==
                        const UpstreamDownstreamNodePosition.downstream();

                _specialNodeRegistry[prevNode.id] = _SpecialNodeInfo(
                  node: _copyNode(prevNode),
                  index: currentNodeIndex - 1,
                  selection: selection,
                  isAtDownstream: isAtDownstream,
                );

                debugPrint(
                  '[EditorService] ✅ 빈 ParagraphNode 삭제 후 이전 특수 노드 정보 등록: nodeId=${prevNode.id}, index=${currentNodeIndex - 1}, isAtDownstream=$isAtDownstream',
                );
              }
            }
          }

          // 다음 노드가 특수 노드인지 확인 (빈 ParagraphNode 아래에 특수 노드가 있었을 가능성)
          if (currentNodeIndex < document.nodeCount) {
            final nextNode = document.getNodeAt(currentNodeIndex);
            if (nextNode != null && _isSpecialNode(nextNode)) {
              // 🎯 플레이스홀더도 레지스트리에 등록 (선택 시 툴바 변경을 위해)
              // 🎯 삭제 예약/명시적 삭제된 노드는 등록하지 않음
              if (!_specialNodeRegistry.containsKey(nextNode.id) &&
                  !_explicitlyDeletedNodes.contains(nextNode.id) &&
                  !_pendingDeletionNodeIds.contains(nextNode.id)) {
                final isAtDownstream =
                    selection.extent.nodeId == nextNode.id &&
                    selection.extent.nodePosition
                        is UpstreamDownstreamNodePosition &&
                    selection.extent.nodePosition ==
                        const UpstreamDownstreamNodePosition.downstream();

                _specialNodeRegistry[nextNode.id] = _SpecialNodeInfo(
                  node: _copyNode(nextNode),
                  index: currentNodeIndex,
                  selection: selection,
                  isAtDownstream: isAtDownstream,
                );

                debugPrint(
                  '[EditorService] ✅ 빈 ParagraphNode 삭제 후 다음 특수 노드 정보 등록: nodeId=${nextNode.id}, index=$currentNodeIndex, isAtDownstream=$isAtDownstream (플레이스홀더 포함)',
                );
              }
            }
          }
        }
      }

      // 🎯 삭제 예약된 노드면 복원하지 않음
      if (_pendingDeletionNodeIds.contains(removedNodeId)) {
        _pendingDeletionNodeIds.remove(removedNodeId);
        _specialNodeRegistry.remove(removedNodeId);
        debugPrint('[EditorService] 🎯 삭제 예약된 노드 - 복원 안 함: $removedNodeId');
        return; // 재빌드 불필요
      }

      // 🎯 실제 삭제 버튼으로 삭제된 경우 복원하지 않음 (최우선 체크)
      if (_explicitlyDeletedNodes.contains(removedNodeId)) {
        _specialNodeRegistry.remove(removedNodeId);
        _explicitlyDeletedNodes.remove(removedNodeId);
        shouldNotify = true;
      }
      // 🎯 레지스트리에 정보가 있는 경우만 복원 시도
      else {
        final nodeInfo = _specialNodeRegistry[removedNodeId];
        if (nodeInfo == null) {
          // 🎯 노드가 실제로 존재하는지 확인 (교체 중일 수 있음)
          final stillExists = document.getNodeById(removedNodeId) != null;
          if (stillExists) {
            // 노드가 여전히 존재하면 교체 중이므로 재빌드 불필요
            return;
          }

          shouldNotify = true;
        } else {
          // 🎯 downstream 위치에서 삭제된 경우는 삭제 허용
          final currentSelection = editor.composer.selectionNotifier.value;
          final isDownstream =
              currentSelection != null &&
              currentSelection.extent.nodeId == removedNodeId &&
              currentSelection.extent.nodePosition
                  is UpstreamDownstreamNodePosition &&
              currentSelection.extent.nodePosition ==
                  const UpstreamDownstreamNodePosition.downstream();

          if (isDownstream) {
            _specialNodeRegistry.remove(removedNodeId);
            debugPrint(
              '[EditorService] 🎯 downstream 위치에서 삭제됨 (백스페이스): nodeId=$removedNodeId',
            );
            shouldNotify = true;
          } else {
            // 🎯 복원 시도
            try {
              if (_explicitlyDeletedNodes.contains(removedNodeId)) {
                debugPrint('[EditorService] ⚠️ 삭제 버튼으로 삭제됨 - 복원하지 않음');
                _specialNodeRegistry.remove(removedNodeId);
                _explicitlyDeletedNodes.remove(removedNodeId);
                shouldNotify = true;
              } else if (document.getNodeById(removedNodeId) != null) {
                _specialNodeRegistry.remove(removedNodeId);
                return; // 이미 존재하면 재빌드 불필요
              } else {
                final restoredNode = _copyNode(nodeInfo.node);
                final insertIndex = nodeInfo.index.clamp(0, document.nodeCount);

                // 🎯 복원 전 삼중 체크 (이중 복원 완전 방지)
                if (_explicitlyDeletedNodes.contains(removedNodeId)) {
                  _specialNodeRegistry.remove(removedNodeId);
                  debugPrint(
                    '[EditorService] ❌ 명시적 삭제 - 복원 취소: $removedNodeId',
                  );
                  return;
                }

                if (_pendingDeletionNodeIds.contains(removedNodeId)) {
                  _specialNodeRegistry.remove(removedNodeId);
                  debugPrint(
                    '[EditorService] ❌ 삭제 예약됨 - 복원 취소: $removedNodeId',
                  );
                  return;
                }

                if (document.getNodeById(restoredNode.id) != null) {
                  _specialNodeRegistry.remove(removedNodeId);
                  debugPrint(
                    '[EditorService] ❌ 이미 존재함 - 복원 취소: $removedNodeId',
                  );
                  return;
                }

                // 노드 복원
                document.insertNodeAt(insertIndex, restoredNode);

                // 레지스트리 재등록
                if (_isSpecialNode(restoredNode)) {
                  _specialNodeRegistry[restoredNode.id] = _SpecialNodeInfo(
                    node: _copyNode(restoredNode),
                    index: insertIndex,
                    selection: null,
                    isAtDownstream: false,
                  );
                  debugPrint(
                    '[EditorService] ✅ 노드 복원 완료: nodeId=$removedNodeId',
                  );
                } else {
                  _specialNodeRegistry.remove(removedNodeId);
                }

                // 커서 이동 (비동기, 삼중 체크)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  try {
                    // 🎯 노드가 여전히 존재하고, 삭제 예약도 없고, 명시적 삭제도 아닌지 확인
                    if (document.getNodeById(restoredNode.id) != null &&
                        !_explicitlyDeletedNodes.contains(restoredNode.id) &&
                        !_pendingDeletionNodeIds.contains(restoredNode.id)) {
                      editor.composer.setSelectionWithReason(
                        DocumentSelection.collapsed(
                          position: DocumentPosition(
                            nodeId: restoredNode.id,
                            nodePosition:
                                const UpstreamDownstreamNodePosition.downstream(),
                          ),
                        ),
                        SelectionReason.userInteraction,
                      );
                    } else {
                      debugPrint(
                        '[EditorService] ⚠️ 복원된 노드 커서 이동 취소: $removedNodeId (노드 삭제됨 또는 예약됨)',
                      );
                    }
                  } catch (e) {
                    debugPrint('[EditorService] 커서 이동 실패: $e');
                  }
                });

                shouldNotify = true;
              }
            } catch (e) {
              debugPrint('[EditorService] 복원 실패: $e');
              _specialNodeRegistry.remove(removedNodeId);
              _explicitlyDeletedNodes.remove(removedNodeId);
              shouldNotify = true;
            }
          }
        }
      }

      // 🎯 최종: 한 번만 notifyListeners 호출
      if (shouldNotify) {
        notifyListeners();
      }
      return;
    }

    if (change is NodeInsertedEvent) {
      // 🎯 멘션 노드 다음에 문단이 생성되면 볼드 attribution 제거
      try {
        final insertedNode = document.getNodeAt(change.insertionIndex);
        if (insertedNode is ParagraphNode &&
            insertedNode.metadata['mention'] != true &&
            change.insertionIndex > 0) {
          // 이전 노드가 멘션 노드인지 확인
          final prevNode = document.getNodeAt(change.insertionIndex - 1);
          if (prevNode is ParagraphNode &&
              prevNode.metadata['mention'] == true) {
            // 멘션 노드 다음에 생성된 문단이면 composer의 bold preference 제거
            if (editor.composer.preferences.currentAttributions.contains(
              boldAttribution,
            )) {
              editor.composer.preferences.removeStyle(boldAttribution);
              debugPrint('[EditorService] 멘션 노드 다음 문단 생성: 볼드 preference 제거');
            }

            // 🎯 새로 생성된 문단의 텍스트에서도 볼드 attribution 제거
            final text = insertedNode.text;
            if (text.text.isNotEmpty) {
              // 텍스트에 볼드 attribution이 있는지 확인
              bool hasBold = false;
              for (int i = 0; i < text.text.length; i++) {
                if (text.getAllAttributionsAt(i).contains(boldAttribution)) {
                  hasBold = true;
                  break;
                }
              }

              if (hasBold) {
                // 볼드 attribution 제거
                final newText = AttributedText(text.text);
                // 볼드가 아닌 다른 attribution만 복사
                for (int i = 0; i < text.text.length; i++) {
                  final attributions = text.getAllAttributionsAt(i);
                  for (final attr in attributions) {
                    if (attr != boldAttribution) {
                      newText.addAttribution(attr, SpanRange(i, i));
                    }
                  }
                }

                // 노드 업데이트
                final newNode = ParagraphNode(
                  id: insertedNode.id,
                  text: newText,
                  metadata: Map<String, dynamic>.from(insertedNode.metadata),
                );

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  try {
                    editor.execute([
                      ReplaceNodeRequest(
                        existingNodeId: insertedNode.id,
                        newNode: newNode,
                      ),
                    ]);
                  } catch (e) {
                    debugPrint('[EditorService] 멘션 노드 다음 문단 볼드 제거 실패: $e');
                  }
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[EditorService] 멘션 노드 다음 문단 볼드 제거 실패: $e');
      }

      // 새 문단의 정렬 승계
      _ensureParagraphAlignmentForIndex(change.insertionIndex);
      // 삽입 지점 주변(상/하/본인)만 마진 재계산
      //_recomputeParagraphMarginsAround(change.insertionIndex);
      _ensureOnlyFirstIsTitle();
      // 문서 구조가 변했으므로 UI 갱신 필요
      notifyListeners();
      return;
    }

    if (change is NodeMovedEvent) {
      // 이동 전/후 주변만 마진 재계산
      //_recomputeParagraphMarginsAround(change.from);
      //_recomputeParagraphMarginsAround(change.to);
      _ensureOnlyFirstIsTitle();
      // 문서 구조가 변했으므로 UI 갱신 필요
      notifyListeners();
      return;
    }

    if (change is NodeChangeEvent) {
      // 타입 변경 등 구조 영향 가능 → 해당 인덱스만 우선 보정, 없으면 전체
      final idx = document.getNodeIndexById(change.nodeId);
      if (idx != -1) {
        //_recomputeParagraphMarginsAround(idx);
        _ensureParagraphAlignmentForIndex(getEditingIndex());
        _ensureOnlyFirstIsTitle();
      } else {
        // _recomputeParagraphMargins();
        _ensureOnlyFirstIsTitle();
      }
      // 문서 구조/내용이 변했으므로 UI 갱신 필요
      notifyListeners();
      return;
    }

    if (change is TextInsertionEvent || change is TextDeletedEvent) {
      _ensureOnlyFirstIsTitle();
      // 본문 텍스트 변경으로 UI 갱신 통지
      notifyListeners(); // 🎯 한 번만 호출
      return;
    }
  }

  @override
  void dispose() {
    _historyTimer?.cancel(); // 🎯 타이머 정리

    // 🎯 Undo/Redo 스택 정리
    _undoStack.clear();
    _redoStack.clear();
    debugPrint('[EditorService] 🧹 히스토리 스택 정리 완료');

    // 🎯 레지스트리 및 삭제 추적 정리
    _specialNodeRegistry.clear();
    _explicitlyDeletedNodes.clear();
    _pendingDeletionNodeIds.clear();
    debugPrint('[EditorService] 🧹 레지스트리 정리 완료');

    try {
      document.removeListener(_onDocumentChanged);
      editor.composer.selectionNotifier.removeListener(_onSelectionChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onSelectionChanged() {
    final sel = editor.composer.selectionNotifier.value;

    // 🎯 케이스 1: 선택 완전 해제
    if (sel == null) {
      if (_context != null) {
        try {
          final nodeService = _context!.read<NodeComponentService>();
          if (nodeService.selectedNodeId != null) {
            nodeService.clearSelectionSilently();
            nodeService.clearHighlightedSelectionSilently();
            debugPrint('[EditorService] Selection null → 특수 노드 선택 해제');
          }
        } catch (e) {
          // NodeComponentService가 없을 수 있음 (무시)
        }
      }
      return;
    }

    // 🎯 케이스 2: 범위 선택 (드래그)
    // 백스페이스 로직만 스킵, NodeComponentService는 유지 (특수 노드 경계인 경우)
    if (!sel.isCollapsed) {
      // 🎯 범위 선택의 extent가 특수 노드 경계가 아니면 해제
      final extentNodeId = sel.extent.nodeId;
      final extentNode = document.getNodeById(extentNodeId);
      final isExtentSpecial = _isSpecialNode(extentNode);

      if (!isExtentSpecial && _context != null) {
        try {
          final nodeService = _context!.read<NodeComponentService>();
          if (nodeService.selectedNodeId != null) {
            nodeService.clearSelectionSilently();
            nodeService.clearHighlightedSelectionSilently();
            debugPrint(
              '[EditorService] 범위 선택 (extent가 특수노드 아님) → NodeComponentService 해제',
            );
          }
        } catch (e) {
          // NodeComponentService가 없을 수 있음 (무시)
        }
      }
      // 백스페이스 로직 스킵
      return;
    }

    // 🎯 여기부터는 collapsed 선택만 도달 (백스페이스 보정 로직)
    _lastSelection = sel;

    // 특수 노드에서 커서 위치 변경 시 저장 (삭제 전 위치 확인용)
    try {
      final nodeId = sel.extent.nodeId;

      // 🎯 노드 존재 확인 (삭제된 노드 접근 방지)
      final node = document.getNodeById(nodeId);
      if (node == null) {
        debugPrint('[EditorService] ⚠️ 노드가 존재하지 않음: $nodeId');
        return;
      }

      if (_isSpecialNode(node)) {
        // 🎯 특수 노드에 커서가 있을 때 항상 레지스트리에 등록/업데이트
        final nodeIndex = document.getNodeIndexById(nodeId);
        final position = sel.extent.nodePosition;
        final isAtDownstream =
            position is UpstreamDownstreamNodePosition &&
            position == const UpstreamDownstreamNodePosition.downstream();
        final isAtUpstream =
            position is UpstreamDownstreamNodePosition &&
            position == const UpstreamDownstreamNodePosition.upstream();

        // 🎯 레지스트리에 등록 (백스페이스 복원용)
        _specialNodeRegistry[nodeId] = _SpecialNodeInfo(
          node: _copyNode(node),
          index: nodeIndex,
          selection: sel,
          isAtDownstream: isAtDownstream,
        );

        debugPrint(
          '[EditorService] 특수 노드 정보 업데이트: nodeId=$nodeId, index=$nodeIndex, isAtDownstream=$isAtDownstream, isAtUpstream=$isAtUpstream',
        );

        // 🎯 upstream/downstream 위치일 때 NodeComponentService에 선택 설정 (보정 없이 그냥 선택만)
        if (_context != null) {
          try {
            final nodeService = _context!.read<NodeComponentService>();
            if (isAtDownstream || isAtUpstream) {
              if (nodeService.selectedImageId != nodeId) {
                nodeService.selectNode(nodeId);
                debugPrint(
                  '[EditorService] 특수 노드 선택 설정: nodeId=$nodeId, upstream=$isAtUpstream, downstream=$isAtDownstream',
                );
              }

              // 🎯 downstream 위치로 이동했을 때만 아래 빈 ParagraphNode 삭제 (백스페이스 처리)
              if (isAtDownstream) {
                try {
                  // 이전 레지스트리 정보 확인
                  final previousInfo = _specialNodeRegistry[nodeId];
                  final wasAtDownstream = previousInfo?.isAtDownstream ?? false;

                  // 🎯 인덱스 범위 체크 강화
                  if (nodeIndex < 0 || nodeIndex >= document.nodeCount) {
                    debugPrint('[EditorService] ⚠️ 잘못된 노드 인덱스: $nodeIndex');
                    return;
                  }

                  // downstream 위치로 이동했을 때 (이전에 downstream이 아니었거나, 이미 downstream이어도)
                  // 아래 ParagraphNode가 비어있으면 삭제
                  if (nodeIndex + 1 < document.nodeCount) {
                    final nextNode = document.getNodeAt(nodeIndex + 1);
                    if (nextNode != null &&
                        nextNode is ParagraphNode &&
                        nextNode.text.text.trim().isEmpty &&
                        nextNode.metadata['isTitle'] != true &&
                        nextNode.metadata['mention'] != true &&
                        !_pendingDeletionNodeIds.contains(nextNode.id)) {
                      // 🎯 이미 삭제 예약되지 않았는지 확인
                      // 🎯 이전에 downstream이 아니었다가 지금 downstream으로 이동한 경우
                      // 또는 이미 downstream이었지만 아래 노드가 완전히 빈 문자열("")인 경우 (백스페이스로 지워진 경우)
                      final isEmpty = nextNode.text.text.isEmpty;
                      if (!wasAtDownstream || isEmpty) {
                        // 빈 ParagraphNode 삭제 예약
                        debugPrint(
                          '[EditorService] downstream 위치에서 아래 빈 ParagraphNode 자동 삭제 예약: nodeId=${nextNode.id}, wasAtDownstream=$wasAtDownstream, isEmpty=$isEmpty',
                        );

                        // 🎯 삭제 예약 (Set으로 관리하여 여러 삭제 동시 처리)
                        final nodeIdToDelete = nextNode.id;
                        _pendingDeletionNodeIds.add(nodeIdToDelete);

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          try {
                            // 🎯 삭제 예약이 취소되지 않았는지 확인
                            if (_pendingDeletionNodeIds.contains(
                                  nodeIdToDelete,
                                ) &&
                                document.getNodeById(nodeIdToDelete) != null) {
                              document.deleteNode(nodeIdToDelete);
                              _pendingDeletionNodeIds.remove(nodeIdToDelete);
                              debugPrint(
                                '[EditorService] ✅ 빈 ParagraphNode 삭제 완료: nodeId=$nodeIdToDelete',
                              );
                            } else {
                              debugPrint(
                                '[EditorService] 빈 ParagraphNode 삭제 취소됨: nodeId=$nodeIdToDelete',
                              );
                              _pendingDeletionNodeIds.remove(nodeIdToDelete);
                            }
                          } catch (e) {
                            debugPrint(
                              '[EditorService] 빈 ParagraphNode 삭제 실패: $e',
                            );
                            _pendingDeletionNodeIds.remove(nodeIdToDelete);
                          }
                        });
                      }
                    }
                  }
                } catch (e) {
                  debugPrint(
                    '[EditorService] downstream 위치에서 빈 ParagraphNode 확인 실패: $e',
                  );
                }
              } else {
                // 🎯 upstream으로 이동 시 해당 노드의 삭제 예약 취소
                if (isAtUpstream && nodeIndex + 1 < document.nodeCount) {
                  final nextNode = document.getNodeAt(nodeIndex + 1);
                  if (nextNode != null &&
                      _pendingDeletionNodeIds.contains(nextNode.id)) {
                    debugPrint(
                      '[EditorService] upstream 이동으로 삭제 예약 취소: nodeId=${nextNode.id}',
                    );
                    _pendingDeletionNodeIds.remove(nextNode.id);
                  }
                }
              }
            } else {
              // upstream/downstream 위치가 아니면 선택 해제
              if (nodeService.selectedImageId == nodeId) {
                nodeService.selectNode(null);
                debugPrint(
                  '[EditorService] upstream/downstream 위치가 아니어서 NodeComponentService 선택 해제: nodeId=$nodeId',
                );
              }
            }
          } catch (e) {
            // NodeComponentService가 없을 수 있음 (무시)
            debugPrint('[EditorService] NodeComponentService 접근 실패: $e');
          }
        }
      } else if (node is ParagraphNode && node.text.text.trim().isEmpty) {
        // 🎯 빈 ParagraphNode에 커서가 있을 때, 위/아래 특수 노드 정보를 항상 저장
        // 이렇게 하면 빈 ParagraphNode가 삭제되기 전에 특수 노드 정보가 레지스트리에 저장됨
        final nodeIndex = document.getNodeIndexById(nodeId);

        // 🎯 인덱스 유효성 확인
        if (nodeIndex < 0 || nodeIndex >= document.nodeCount) {
          debugPrint('[EditorService] ⚠️ 빈 ParagraphNode: 잘못된 인덱스: $nodeIndex');
          return;
        }

        // 위쪽 특수 노드 확인
        if (nodeIndex > 0) {
          final prevNode = document.getNodeAt(nodeIndex - 1);
          if (prevNode != null &&
              _isSpecialNode(prevNode) &&
              !_explicitlyDeletedNodes.contains(prevNode.id) &&
              !_pendingDeletionNodeIds.contains(prevNode.id)) {
            // selection이 특수 노드를 가리키고 있는지 확인
            final isAtDownstream =
                sel.extent.nodeId == prevNode.id &&
                sel.extent.nodePosition is UpstreamDownstreamNodePosition &&
                sel.extent.nodePosition ==
                    const UpstreamDownstreamNodePosition.downstream();

            _specialNodeRegistry[prevNode.id] = _SpecialNodeInfo(
              node: _copyNode(prevNode),
              index: nodeIndex - 1,
              selection: sel,
              isAtDownstream: isAtDownstream,
            );

            debugPrint(
              '[EditorService] ✅ 빈 ParagraphNode 위 특수 노드 정보 저장: nodeId=${prevNode.id}, index=${nodeIndex - 1}, isAtDownstream=$isAtDownstream',
            );
          }
        }

        // 아래쪽 특수 노드 확인
        if (nodeIndex < document.nodeCount - 1) {
          final nextNode = document.getNodeAt(nodeIndex + 1);
          if (nextNode != null &&
              _isSpecialNode(nextNode) &&
              !_explicitlyDeletedNodes.contains(nextNode.id) &&
              !_pendingDeletionNodeIds.contains(nextNode.id)) {
            // selection이 특수 노드를 가리키고 있는지 확인
            final isAtDownstream =
                sel.extent.nodeId == nextNode.id &&
                sel.extent.nodePosition is UpstreamDownstreamNodePosition &&
                sel.extent.nodePosition ==
                    const UpstreamDownstreamNodePosition.downstream();

            _specialNodeRegistry[nextNode.id] = _SpecialNodeInfo(
              node: _copyNode(nextNode),
              index: nodeIndex + 1,
              selection: sel,
              isAtDownstream: isAtDownstream,
            );

            debugPrint(
              '[EditorService] ✅ 빈 ParagraphNode 아래 특수 노드 정보 저장: nodeId=${nextNode.id}, index=${nodeIndex + 1}, isAtDownstream=$isAtDownstream',
            );
          }
        }
      } else {
        // 🎯 특수 노드가 아니고 빈 ParagraphNode도 아니면 NodeComponentService 선택 해제
        if (_context != null) {
          try {
            final nodeService = _context!.read<NodeComponentService>();
            if (nodeService.selectedImageId != null) {
              nodeService.selectNode(null);
              debugPrint(
                '[EditorService] 일반 노드로 이동하여 NodeComponentService 선택 해제',
              );
            }
          } catch (e) {
            // NodeComponentService가 없을 수 있음 (무시)
          }
        }
      }
    } catch (e) {
      // 에러 무시
    }
  }

  /// 제목이 비어있지 않은지 판단
  bool hasNonEmptyTitle() {
    final node = document.getNodeAt(0);
    if (node is ParagraphNode && (node.metadata['isTitle'] == true)) {
      final text = node.text.text.trim();
      return text.isNotEmpty;
    }
    return false;
  }

  /// 본문(제목 제외)에 유의미한 내용이 있는지 판단
  bool hasNonEmptyBody({BuildContext? context}) {
    // 🎯 스티커가 있으면 본문이 있다고 간주
    if (context != null) {
      final stickerService = context.read<StickerService>();
      if (stickerService.stickers.isNotEmpty) return true;
    }

    for (int i = 1; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      if (node is ParagraphNode) {
        if (node.text.text.trim().isNotEmpty) return true;
      } else if (_isSpecialNode(node)) {
        return true;
      } else if (node is ParagraphNode && node.metadata['mention'] == true) {
        return true;
      } else {
        // 기타 노드가 존재하면 본문이 있다고 간주
        return true;
      }
    }
    return false;
  }

  /// 🎯 업로드되지 않은 이미지가 있는지 확인 (UploadService의 task 기반 실제 업로드 상태만 확인)
  /// 🚀 플레이스홀더 개념 제거 - UploadService의 활성 업로드만 체크하여 가볍고 정확하게 판단
  bool hasUnuploadedImages() {
    if (_context == null) return false;

    try {
      final uploadService = _context!.read<UploadService>();
      // 🚀 에디터 관련 활성 업로드(pending, uploading)가 있는지만 확인
      return uploadService.hasActiveUploads();
    } catch (e) {
      // UploadService 접근 실패 시 false 반환 (업로드 없음으로 간주)
      debugPrint(
        '[EditorService] hasUnuploadedImages: UploadService 접근 실패: $e',
      );
      return false;
    }
  }

  /// 🎯 네트워크 URL인지 확인하는 static 메서드 (외부에서 사용 가능)
  static bool isNetworkUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// 문서 내용을 간단 스냅샷으로 직렬화하여 지문(fingerprint)을 생성
  String computeDocumentFingerprint() {
    final nodes = <Map<String, dynamic>>[];
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      if (node is ParagraphNode) {
        nodes.add({
          't': 'p',
          'title': node.metadata['isTitle'] == true,
          'align': node.metadata['textAlign'],
          'fontFamily': node.metadata['fontFamily'], // 폰트 정보 포함
          'text': node.text.text,
        });
      } else if (node is AppImageNode) {
        nodes.add({'t': 'img', 'url': node.imageUrl});
      } else if (node is ImageNode) {
        nodes.add({'t': 'img', 'url': node.imageUrl});
      } else if (node is ImageRowNode) {
        nodes.add({'t': 'row', 'urls': List<String>.from(node.imageUrls)});
      } else if (node is LinkNode) {
        nodes.add({'t': 'link', 'url': node.url, 'title': node.title});
      } else if (node is ParagraphNode && node.metadata['mention'] == true) {
        final List<dynamic> namesDyn =
            (node.metadata['usernames'] as List?) ?? const [];
        nodes.add({
          't': 'mention',
          'users': namesDyn.map((e) => e.toString()).toList(),
        });
      } else {
        nodes.add({'t': node.runtimeType.toString(), 'id': node.id});
      }
    }
    return jsonEncode({'nodes': nodes});
  }

  /// 현재 문서 상태를 저장 스냅샷으로 마크
  void markSavedSnapshot() {
    _lastSavedFingerprint = computeDocumentFingerprint();
  }

  /// 종료 시 임시저장 다이얼로그 노출 필요 여부
  bool shouldPromptSaveOnExit(BuildContext context) {
    final hasStickerChanges = context.read<StickerService>().hasChanges;
    // 제목 또는 본문 중 하나라도 유효한 입력이 있어야 함
    final bool anyContent =
        hasNonEmptyTitle() || hasNonEmptyBody(context: context);
    if (!anyContent) return false;
    final now = computeDocumentFingerprint();
    if (_lastSavedFingerprint == null || hasStickerChanges) {
      // 저장 이력이 없다면 변경이 있는 상태로 간주
      return true;
    }
    return now != _lastSavedFingerprint;
  }

  void reorderNode(String nodeId, int targetIndex) {
    final node = document.getNodeById(nodeId);
    if (node == null) return;

    // 현재 노드의 인덱스 찾기
    int currentIndex = -1;
    for (int i = 0; i < document.length; i++) {
      if (document.getNodeAt(i)?.id == nodeId) {
        currentIndex = i;
        break;
      }
    }

    if (currentIndex == -1) return;

    // 같은 위치면 이동하지 않음
    if (currentIndex == targetIndex) return;

    // 🎯 reorder 작업 중에는 히스토리 추적 일시 중단
    _isExecutingHistory = true;

    try {
      // 문서 끝에 삽입하는 경우 처리
      if (targetIndex >= document.length) {
        document.deleteNode(nodeId);
        document.insertNodeAt(document.length, node);
      } else {
        // 노드 삭제 후 새 위치에 삽입
        document.deleteNode(nodeId);
        final insertIndex =
            targetIndex > currentIndex ? targetIndex - 1 : targetIndex;
        document.insertNodeAt(insertIndex, node);
      }
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint(
        '[EditorService] 🔄 노드 순서 변경 완료 (${currentIndex} → ${targetIndex})',
      );
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  /// 두 이미지를 가로 배치로 합치는 함수
  void mergeImagesIntoRow(
    String draggingImageId,
    String targetImageId, {
    bool isFromLeft = true,
  }) {
    final draggingNode = document.getNodeById(draggingImageId);
    final targetNode = document.getNodeById(targetImageId);

    if (draggingNode == null || targetNode == null) return;

    // 타겟 노드가 ImageRowNode인 경우
    if (targetNode is ImageRowNode) {
      _addImageToRow(draggingImageId, targetImageId, isFromLeft);
      return;
    }

    // 드래그 중인 노드가 ImageRowNode인 경우
    if (draggingNode is ImageRowNode) {
      _addImageToRow(targetImageId, draggingImageId, !isFromLeft);
      return;
    }

    // 둘 다 단일 이미지인 경우
    if (draggingNode is! ImageNode || targetNode is! ImageNode) return;

    // 네트워크 URL만 허용 (file:// 또는 로컬 경로는 행에 포함 금지)
    bool _isNetworkUrl(String u) =>
        u.startsWith('http://') || u.startsWith('https://');
    if (!_isNetworkUrl(draggingNode.imageUrl) ||
        !_isNetworkUrl(targetNode.imageUrl)) {
      return; // 업로드 완료 후 다시 시도
    }

    // 두 이미지의 URL 수집 (최대 3개)
    final imageUrls = <String>[];

    // 드래그 중인 이미지가 타겟 이미지보다 앞에 있으면 먼저 추가
    int draggingIndex = -1;
    int targetIndex = -1;

    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node?.id == draggingImageId) draggingIndex = i;
      if (node?.id == targetImageId) targetIndex = i;
    }

    if (draggingIndex == -1 || targetIndex == -1) return;

    // 🎯 각 이미지의 mediaId 추출
    String? draggingMediaId;
    String? targetMediaId;
    try {
      final draggingMeta =
          (draggingNode as dynamic).metadata as Map<String, dynamic>?;
      draggingMediaId = draggingMeta?['mediaId']?.toString();
    } catch (_) {}
    try {
      final targetMeta =
          (targetNode as dynamic).metadata as Map<String, dynamic>?;
      targetMediaId = targetMeta?['mediaId']?.toString();
    } catch (_) {}

    // 방향에 따라 이미지 순서 결정
    List<String> mediaIds = [];
    if (isFromLeft) {
      // 왼쪽에서 오는 경우: 드래그 이미지가 왼쪽에
      imageUrls.add(draggingNode.imageUrl);
      imageUrls.add(targetNode.imageUrl);
      if (draggingMediaId != null) mediaIds.add(draggingMediaId);
      if (targetMediaId != null) mediaIds.add(targetMediaId);
    } else {
      // 오른쪽에서 오는 경우: 타겟 이미지가 왼쪽에
      imageUrls.add(targetNode.imageUrl);
      imageUrls.add(draggingNode.imageUrl);
      if (targetMediaId != null) mediaIds.add(targetMediaId);
      if (draggingMediaId != null) mediaIds.add(draggingMediaId);
    }

    debugPrint('[EditorService] ImageRow 생성 - mediaIds: $mediaIds');

    // 🎯 imageCommentInfo 맵 생성 (PostExporter가 기대하는 형식)
    final imageCommentInfo = <String, Map<String, dynamic>>{};
    for (int i = 0; i < imageUrls.length; i++) {
      final url = imageUrls[i];
      if (i < mediaIds.length && mediaIds[i].isNotEmpty) {
        imageCommentInfo[url] = {
          'mediaId': mediaIds[i],
          'hasComments': false,
          'commentCount': 0,
        };
      }
    }

    debugPrint('[EditorService] 🔍 생성된 imageCommentInfo: $imageCommentInfo');

    // ImageRowNode 생성 (이미 3개 제한이 적용됨)
    final imageRowNode = ImageRowNode(
      id: 'imageRow_${DateTime.now().millisecondsSinceEpoch}',
      imageUrls: imageUrls,
      spacing: 8.0,
      metadata:
          imageCommentInfo.isNotEmpty
              ? {'imageCommentInfo': imageCommentInfo}
              : null,
    );

    // 🎯 이미지 병합 작업 중에는 히스토리 추적 일시 중단
    _isExecutingHistory = true;

    try {
      // 기존 이미지들 삭제
      document.deleteNode(draggingImageId);
      document.deleteNode(targetImageId);

      // ImageRowNode 삽입 (더 작은 인덱스 위치에)
      final insertIndex =
          draggingIndex < targetIndex ? draggingIndex : targetIndex;
      document.insertNodeAt(insertIndex, imageRowNode);
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 🖼️ 이미지 병합 완료');
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  void _addImageToRow(String imageId, String rowId, bool isFromLeft) {
    final imageNode = document.getNodeById(imageId);
    final rowNode = document.getNodeById(rowId);

    if (imageNode == null || rowNode == null) return;
    if (imageNode is! ImageNode || rowNode is! ImageRowNode) return;

    // 네트워크 URL만 허용
    bool _isNetworkUrl(String u) =>
        u.startsWith('http://') || u.startsWith('https://');
    if (!_isNetworkUrl(imageNode.imageUrl)) {
      return;
    }

    // 이미 3개가 있으면 추가하지 않음
    if (rowNode.imageUrls.length >= 3) return;

    // 🎯 추가되는 이미지의 mediaId 추출
    String? newImageMediaId;
    try {
      final imageMeta =
          (imageNode as dynamic).metadata as Map<String, dynamic>?;
      newImageMediaId = imageMeta?['mediaId']?.toString();
    } catch (_) {}

    // 🎯 기존 row의 imageCommentInfo 추출
    Map<String, Map<String, dynamic>> existingCommentInfo = {};
    try {
      final rowMeta = rowNode.metadata;
      final commentInfo = rowMeta['imageCommentInfo'] as Map<String, dynamic>?;
      if (commentInfo != null) {
        existingCommentInfo = commentInfo.map(
          (key, value) => MapEntry(key, (value as Map).cast<String, dynamic>()),
        );
      }
    } catch (_) {}

    // 새로운 이미지 URL 리스트 생성
    final newImageUrls = List<String>.from(rowNode.imageUrls);
    final newImageCommentInfo = Map<String, Map<String, dynamic>>.from(
      existingCommentInfo,
    );

    if (isFromLeft) {
      newImageUrls.insert(0, imageNode.imageUrl);
      if (newImageMediaId != null && newImageMediaId.isNotEmpty) {
        newImageCommentInfo[imageNode.imageUrl] = {
          'mediaId': newImageMediaId,
          'hasComments': false,
          'commentCount': 0,
        };
      }
    } else {
      newImageUrls.add(imageNode.imageUrl);
      if (newImageMediaId != null && newImageMediaId.isNotEmpty) {
        newImageCommentInfo[imageNode.imageUrl] = {
          'mediaId': newImageMediaId,
          'hasComments': false,
          'commentCount': 0,
        };
      }
    }

    // 🎯 이미지 행 추가 작업 중에는 히스토리 추적 일시 중단
    _isExecutingHistory = true;

    try {
      // ImageRowNode 업데이트 (이미 3개 제한이 적용됨)
      final updatedRowNode = rowNode.copyWith(
        imageUrls: newImageUrls,
        metadata:
            newImageCommentInfo.isNotEmpty
                ? {'imageCommentInfo': newImageCommentInfo}
                : null,
      );
      document.replaceNodeById(rowId, updatedRowNode);

      // 기존 이미지 삭제
      document.deleteNode(imageId);
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 🖼️ ImageRow에 이미지 추가 완료');
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  NodeType getNodeType(String nodeId) {
    final node = document.getNodeById(nodeId);
    switch (node) {
      case ParagraphNode():
        return NodeType.paragraph;
      case ImageNode():
        return NodeType.image;
      case ImageRowNode():
        return NodeType.imageRow;
      default:
        return NodeType.unknown;
    }
  }

  int getEditingIndex() {
    final selection = editor.composer.selectionNotifier.value;
    if (selection == null) return -1;
    final nodeId = selection.extent.nodeId;
    return document.getNodeIndexById(nodeId);
  }

  /// 링크 노드를 현재 커서 다음 슬롯에 삽입
  void addLinkNode({
    required String url,
    String? title,
    String? description,
    String? thumbnailUrl,
  }) {
    final node = LinkNode(
      id: 'link_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      title: title ?? '',
      description: description ?? '',
      thumbnailUrl: thumbnailUrl ?? '',
    );
    _insertComponentNodeAtNextLine(node);
  }

  /// 지정 인덱스에 빈 문단을 삽입하고 캐럿을 그 문단 앞으로 이동
  /// 빈 문단을 지정된 인덱스에 추가하고, 0.1초 후 포커스를 설정합니다.
  /// 새로 추가된 노드 ID를 반환합니다.
  String? insertEmptyParagraphAtIndex(int index) {
    try {
      final doc = editor.document;
      int insertIndex = index;
      if (insertIndex < 0) insertIndex = 0;
      if (insertIndex > doc.nodeCount) insertIndex = doc.nodeCount;

      final String align = _getPreviousParagraphAlign(insertIndex);
      final String paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';

      final ParagraphNode newParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: {'textAlign': align},
      );

      editor.execute([
        InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: newParagraph),
      ]);

      // 🎯 안정화를 위해 0.1초 대기 후 포커스 설정 및 키보드 올리기
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: paragraphId,
                  nodePosition: const TextNodePosition(offset: 0),
                ),
              ),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
          // 🎯 키보드 올리기
          FocusManager.instance.primaryFocus?.requestFocus();
        } catch (_) {}
      });
      // 🎯 editor.execute()가 자동으로 document 리스너를 호출하므로 notifyListeners() 불필요
      return paragraphId;
    } catch (_) {
      return null;
    }
  }

  /// 언급 노드를 문단(Paragraph) 기반으로 삽입한다.
  /// - 전체 텍스트는 굵게(bold)
  /// - 메타데이터로 mention 플래그와 usernames를 보관
  /// - 컴포넌트처럼 현재 라인 다음 슬롯에 삽입(필요 시 끝에 빈 문단 생성)
  /// - 각 멘션은 개별 노드로 생성되어 세로로 표시됨
  void addMentionNode(List<String> usernames) {
    if (usernames.isEmpty) return;

    // 🎯 멘션 추가 작업 중에는 히스토리 추적 일시 중단
    _isExecutingHistory = true;

    try {
      final doc = editor.document;
      final safeIndex = _getCaretNodeIndexSafe();
      int insertIndex = safeIndex;

      // 🎯 제목 노드(index 0)에 커서가 있으면 강제로 다음 라인에 삽입
      if (insertIndex == 0) {
        insertIndex = 1;
        debugPrint('🎯 [Mention] 제목 노드에 커서가 있음, 다음 라인(index 1)에 삽입');

        // 제목 다음에 빈 문단이 없으면 먼저 생성
        if (doc.nodeCount < 2) {
          final paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
          final ParagraphNode newParagraph = ParagraphNode(
            id: paragraphId,
            text: AttributedText(''),
            metadata: {'textAlign': 'center'},
          );
          doc.insertNodeAt(1, newParagraph);
          debugPrint('📝 [Mention] 제목 다음에 빈 문단 생성');
        }
      } else {
        // 🎯 현재 커서가 있는 문단에 텍스트가 있으면 다음 줄에 삽입
        if (insertIndex < doc.nodeCount) {
          final currentNode = doc.getNodeAt(insertIndex);
          if (currentNode is ParagraphNode) {
            final hasText = currentNode.text.text.trim().isNotEmpty;
            if (hasText) {
              insertIndex = insertIndex + 1;
              debugPrint(
                '🎯 [Mention] 현재 문단에 텍스트가 있음, 다음 줄(index $insertIndex)에 삽입',
              );
            }
          }
        }
      }

      if (insertIndex > doc.nodeCount) insertIndex = doc.nodeCount;

      // 이전 문단 정렬을 승계
      final String inheritedAlign = _getPreviousParagraphAlign(insertIndex);

      // 🎯 각 username마다 별도의 ParagraphNode 생성 (metadata로 멘션 표시)
      final edits = <EditRequest>[];

      for (int i = 0; i < usernames.length; i++) {
        final username = usernames[i];
        final mentionId =
            'p_mention_${DateTime.now().millisecondsSinceEpoch}_$i';
        final mentionText = '@$username';

        // 🎯 볼드 attribution 추가
        final AttributedText attributed = AttributedText(mentionText);
        if (mentionText.isNotEmpty) {
          attributed.addAttribution(
            boldAttribution,
            SpanRange(0, mentionText.length - 1),
          );
        }

        final mentionParagraph = ParagraphNode(
          id: mentionId,
          text: attributed,
          metadata: {
            'textAlign': inheritedAlign,
            'mention': true,
            'usernames': [username], // 한 사람당 하나의 노드
          },
        );

        edits.add(
          InsertNodeAtIndexRequest(
            nodeIndex: insertIndex + i,
            newNode: mentionParagraph,
          ),
        );
      }

      // 🎯 멘션 노드 다음에 항상 빈 문단 추가 (텍스트 이어서 쓰기 위해)
      final String paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
      final ParagraphNode newParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: {'textAlign': inheritedAlign},
      );
      edits.add(
        InsertNodeAtIndexRequest(
          nodeIndex: insertIndex + usernames.length,
          newNode: newParagraph,
        ),
      );

      editor.execute(edits);

      // 🎯 항상 멘션 노드 다음 빈 문단으로 커서 이동 (텍스트 이어서 쓰기)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: paragraphId,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
      });
    } catch (e) {
      debugPrint('[EditorService] 멘션 추가 실패: $e');
    } finally {
      // 🎯 작업 완료 후 히스토리 추적 재개 + 한 번만 저장
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 📝 멘션 추가 완료');
    }
  }

  /// 🎯 비디오 클립 노드 추가 (로컬 경로 기반)
  /// 🎯 media_upload_handler 호환: 로컬 경로로 노드 추가
  String addVideoClipNode({
    required String localPath,
    String label = '',
    String? thumbnailPath,
    double? aspectRatio,
  }) {
    final id = 'clip_${DateTime.now().millisecondsSinceEpoch}';
    final metadata = <String, dynamic>{
      'padding': 'center',
      if (aspectRatio != null) 'aspectRatio': aspectRatio,
      if (thumbnailPath != null && thumbnailPath.isNotEmpty)
        'thumbnailPath': thumbnailPath,
    };

    final node = ClipNode(
      id: id,
      label: label,
      colorHex: '#FF5252',
      url: '',
      localPath: localPath,
      thumbnailPath: thumbnailPath ?? '',
      metadata: metadata,
    );
    _insertComponentNodeAtNextLine(node);
    return id;
  }

  /// 🎯 비디오 URL 교체 (로컬 경로를 네트워크 URL로)
  /// 🎯 media_upload_handler 호환: 로컬 경로를 네트워크 URL로 교체
  Future<void> replaceVideoUrlByPath({
    required String nodeId,
    required String url,
    String? fallbackLocalPath,
    String? processedLocalPath,
  }) async {
    _isExecutingHistory = true;
    try {
      DocumentNode? nodeFound = document.getNodeById(nodeId);
      if (nodeFound is! ClipNode) {
        // id로 못 찾았으면 localPath로 검색
        if (fallbackLocalPath != null && fallbackLocalPath.isNotEmpty) {
          for (int i = 0; i < document.length; i++) {
            final n = document.getNodeAt(i);
            if (n is ClipNode) {
              final lp = n.localPath;
              final isPlaceholder = (n.url.isEmpty && lp.isNotEmpty);
              if (isPlaceholder && lp == fallbackLocalPath) {
                nodeFound = n;
                break;
              }
            }
          }
        }
      }
      if (nodeFound is! ClipNode) return;

      final existingMetadata = Map<String, dynamic>.from(nodeFound.metadata);
      final originalLocalPath = nodeFound.localPath;
      final uploadedUrls = Map<String, String>.from(
        (existingMetadata['uploadedUrls'] as Map<String, dynamic>?)
                ?.cast<String, String>() ??
            {},
      );

      // 🎯 uploadedUrls에는 원본 경로를 키로 저장 (이미지와 동일한 패턴)
      if (originalLocalPath.isNotEmpty &&
          !(originalLocalPath.startsWith('http://') ||
              originalLocalPath.startsWith('https://'))) {
        uploadedUrls[originalLocalPath] = url;
        // 🎯 성능 최적화: 네트워크 URL도 키로 저장 (나중에 매칭 용이)
        uploadedUrls[url] = url; // 자기 자신을 가리킴 (일관성 유지)
      }

      // processedLocalPath가 있으면 ffmpeg 처리된 경로로 localPath 업데이트
      final finalLocalPath =
          processedLocalPath != null && processedLocalPath.isNotEmpty
              ? processedLocalPath
              : originalLocalPath;

      final updatedMetadata = <String, dynamic>{
        ...existingMetadata,
        'uploadedUrls': uploadedUrls,
        'padding': existingMetadata['padding'] as String? ?? 'center',
      };

      if (processedLocalPath != null &&
          processedLocalPath.isNotEmpty &&
          processedLocalPath != originalLocalPath) {
        updatedMetadata['originalLocalPath'] = originalLocalPath;
      }

      final newNode = ClipNode(
        id: nodeFound.id,
        label: nodeFound.label,
        colorHex: nodeFound.colorHex,
        url: url, // 네트워크 URL
        localPath: finalLocalPath, // ffmpeg 처리된 경로 사용
        thumbnailPath: nodeFound.thumbnailPath,
        metadata: updatedMetadata,
      );

      editor.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: newNode),
      ]);
    } catch (e) {
      debugPrint('replaceVideoUrlByPath error: $e');
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
    }
  }

  /// 🎯 비디오 썸네일 업데이트
  /// 🎯 media_upload_handler 호환: 썸네일 경로 업데이트
  void updateVideoThumbnail(String nodeId, String thumbnailPath) {
    final node = document.getNodeById(nodeId);
    if (node is ClipNode) {
      final existingMetadata = Map<String, dynamic>.from(node.metadata);
      existingMetadata['thumbnailPath'] = thumbnailPath;
      // 🎯 padding이 없으면 기본값 'center' 설정 (싱글 이미지와 동일)
      if (!existingMetadata.containsKey('padding')) {
        existingMetadata['padding'] = 'center';
      }

      final updated = ClipNode(
        id: node.id,
        label: node.label,
        colorHex: node.colorHex,
        url: node.url,
        localPath: node.localPath,
        thumbnailPath: thumbnailPath,
        metadata: existingMetadata,
      );
      document.replaceNodeById(nodeId, updated);
      notifyListeners();
    }
  }

  ///  노드 추가: 현재 캐럿 다음 슬롯에  삽입
  void addClipNode({
    String label = '',
    String colorHex = '#FF5252',
    required String url,
  }) {
    final node = ClipNode(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      colorHex: colorHex,
      url: url,
      metadata: {
        'padding': 'center', // 🎯 기본값 설정 (싱글 이미지와 동일)
      },
    );
    _insertComponentNodeAtNextLine(node);
  }

  DocumentNode? findNodeAtPosition(Offset position) {
    final documentLayout = _documentLayoutKey?.currentState as DocumentLayout?;
    if (documentLayout == null) {
      return null;
    }

    try {
      // 글로벌 좌표를 DocumentLayout의 로컬 좌표로 변환
      final renderObject =
          _documentLayoutKey?.currentContext?.findRenderObject();
      RenderBox? renderBox;
      if (renderObject is RenderSliverToBoxAdapter) {
        renderBox = renderObject.child;
      } else if (renderObject is RenderBox) {
        renderBox = renderObject;
      }

      if (renderBox == null) {
        return null;
      }

      // 글로벌 좌표를 DocumentLayout의 로컬 좌표로 변환
      final localPosition = renderBox.globalToLocal(position);

      // SuperEditor 내장 함수 사용 (안전한 처리)
      DocumentPosition? documentPosition;
      try {
        documentPosition = documentLayout.getDocumentPositionNearestToOffset(
          localPosition,
        );
      } catch (e) {
        return null;
      }

      if (documentPosition == null) {
        return null;
      }

      final node = document.getNodeById(documentPosition.nodeId);

      return node;
    } catch (e) {
      debugPrint("Error finding node at position: $e");
      return null;
    }
  }

  /// 🎯 직접 hit test 방식: 모든 노드의 실제 렌더링 영역을 확인하여 탭 위치가 어느 노드에 있는지 정확히 판단
  /// findNodeAtPosition과 달리 실제 렌더링된 컴포넌트의 글로벌 좌표를 사용하므로 더 정확함
  ///
  /// 반환값: (탭된 노드, 노드의 실제 렌더링 영역)
  /// 텍스트 노드가 최우선순위를 가지며, 텍스트 노드가 없을 때만 특수 노드를 확인
  MapEntry<DocumentNode?, Rect?>? findNodeByHitTest(
    Offset globalPosition,
    DragService dragService,
  ) {
    try {
      // 🎯 텍스트 노드를 먼저 확인하여 최우선순위 보장
      // 텍스트 노드가 감지되면 즉시 반환하여 특수 노드 선택 방지
      for (int i = 0; i < document.nodeCount; i++) {
        final node = document.getNodeAt(i);
        if (node == null) continue;

        // 🎯 텍스트 노드를 먼저 확인
        if (node is ParagraphNode &&
            node.metadata['mention'] != true &&
            node.metadata['isTitle'] != true) {
          final rect = dragService.getNodeGlobalRect(node.id);
          if (rect != null && rect.contains(globalPosition)) {
            // 텍스트 노드가 감지되면 즉시 반환 (특수 노드보다 우선)
            return MapEntry(node, rect);
          }
        }
      }

      // 텍스트 노드가 없을 때만 특수 노드 확인
      final specialNodes = <MapEntry<DocumentNode, Rect>>[];
      for (int i = 0; i < document.nodeCount; i++) {
        final node = document.getNodeAt(i);
        if (node == null) continue;

        final bool isSpecial =
            _isSpecialNode(node) ||
            (node is ParagraphNode && node.metadata['mention'] == true);

        if (isSpecial) {
          final rect = dragService.getNodeGlobalRect(node.id);
          if (rect != null && rect.contains(globalPosition)) {
            specialNodes.add(MapEntry(node, rect));
          }
        }
      }

      // 특수 노드가 있으면 위에서부터 반환
      if (specialNodes.isNotEmpty) {
        // 위에서부터 확인 (인덱스 순서대로)
        specialNodes.sort((a, b) {
          final indexA = document.getNodeIndexById(a.key.id);
          final indexB = document.getNodeIndexById(b.key.id);
          return indexA.compareTo(indexB);
        });
        return MapEntry(specialNodes.first.key, specialNodes.first.value);
      }

      return null;
    } catch (e) {
      debugPrint("Error in findNodeByHitTest: $e");
      return null;
    }
  }

  /// 이미지 행에서 특정 이미지를 분리하고 분리된 이미지 ID 반환
  /// insertIndex가 주어지면 해당 위치에 바로 삽입한다. 주어지지 않으면 행의 위치(rowIndex)에 삽입.
  String? splitImageFromRow(String rowId, int imageIndex, {int? insertIndex}) {
    final rowNode = document.getNodeById(rowId);
    if (rowNode == null || rowNode is! ImageRowNode) return null;
    if (imageIndex < 0 || imageIndex >= rowNode.imageUrls.length) return null;

    // 분리할 이미지 URL
    final imageUrl = rowNode.imageUrls[imageIndex];

    // 이미지 행의 인덱스 찾기
    int rowIndex = -1;
    for (int i = 0; i < document.length; i++) {
      if (document.getNodeAt(i)?.id == rowId) {
        rowIndex = i;
        break;
      }
    }
    if (rowIndex == -1) return null;

    // 분리할 이미지의 새 ID 생성
    final newImageId = 'image_${DateTime.now().millisecondsSinceEpoch}';
    final newImageNode = AppImageNode(id: newImageId, imageUrl: imageUrl);

    // 이미지 행에서 해당 이미지 제거
    final remainingUrls = List<String>.from(rowNode.imageUrls);
    remainingUrls.removeAt(imageIndex);

    // 🎯 이미지 분리 작업 중에는 히스토리 추적 일시 중단
    _isExecutingHistory = true;

    try {
      if (remainingUrls.length == 1) {
        // 이미지가 1개만 남으면 단일 이미지로 변경
        final singleImageNode = AppImageNode(
          id: rowId,
          imageUrl: remainingUrls.first,
        );
        document.replaceNodeById(rowId, singleImageNode);
      } else if (remainingUrls.isEmpty) {
        // 이미지가 없으면 행 삭제
        document.deleteNode(rowId);
      } else {
        // 이미지 행 업데이트
        final updatedRowNode = rowNode.copyWith(imageUrls: remainingUrls);
        document.replaceNodeById(rowId, updatedRowNode);
      }

      // 분리된 이미지를 원하는 위치에 삽입 (기본: 원래 행의 위치)
      final int targetInsertIndex = insertIndex ?? rowIndex;
      document.insertNodeAt(targetInsertIndex, newImageNode);
      // 🎯 notifyListeners는 finally 이후에 한 번만

      return newImageId;
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 🖼️ 이미지 분리 완료');
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  /// 이미지 추가: 현재 커서 다음 줄에 로컬 경로 기반 이미지 노드 삽입
  /// 🎯 media_upload_handler 호환: String 반환 (nodeId)
  String addImageNode(String thumbnailImageUrl) {
    try {
      debugPrint('이미지 추가: $thumbnailImageUrl');

      final id = 'image_${DateTime.now().millisecondsSinceEpoch}';
      final imageNode = AppImageNode(
        id: id,
        imageUrl: thumbnailImageUrl,
        altText: '',
      );
      _insertComponentNodeAtNextLine(imageNode);
      return id;
    } catch (e) {
      debugPrint('이미지 추가 중 오류: $e');
      rethrow;
    }
  }

  /// 🎯 그룹 이미지 노드 추가 (로컬 경로 기반)
  /// 🎯 media_upload_handler 호환: 로컬 경로로 노드 추가
  String addGroupImageNode({
    required List<String> localPaths,
    required GroupImageLayout layout,
  }) {
    final id = 'group_${DateTime.now().millisecondsSinceEpoch}';
    DocumentNode node;
    if (layout == GroupImageLayout.pageview) {
      node = PageViewImageNode(id: id, imageUrls: localPaths);
    } else {
      node = ImageRowNode(id: id, imageUrls: localPaths);
    }
    _insertComponentNodeAtNextLine(node);
    return id;
  }

  /// 🎯 단일 이미지의 네트워크 URL을 메타데이터에 저장
  /// 로컬 경로는 유지하고 metadata에만 networkUrl 추가
  Future<void> replaceImageUrlByPath({
    required String nodeId,
    required String localPath,
    required String url,
  }) async {
    _isExecutingHistory = true;
    try {
      final node = document.getNodeById(nodeId);
      if (node is ImageNode) {
        final meta = node.metadata;
        final uploadedUrls = Map<String, String>.from(
          (meta['uploadedUrls'] as Map<String, dynamic>?)
                  ?.cast<String, String>() ??
              {},
        );
        uploadedUrls[localPath] = url;

        final updated = AppImageNode(
          id: nodeId,
          imageUrl: node.imageUrl, // 로컬 경로 유지 (변경 없음)
          altText: node.altText,
          metadata: {...meta, 'uploadedUrls': uploadedUrls},
        );
        document.replaceNodeById(nodeId, updated);
        notifyListeners();
      }
    } finally {
      _isExecutingHistory = false;
    }
  }

  /// 🎯 그룹 이미지의 특정 로컬 경로에 대한 네트워크 URL을 metadata에 저장
  /// 로컬 경로는 유지하고 metadata에만 networkUrl 추가
  Future<void> replaceGroupImageUrlByPath({
    required String groupNodeId,
    required String localPath,
    required String url,
  }) async {
    await replaceGroupImageUrlsByPath(
      groupNodeId: groupNodeId,
      urlMap: {localPath: url},
    );
  }

  /// 🎯 성능 최적화: 여러 URL을 한 번에 배치 업데이트 (중복 document 읽기/쓰기 방지)
  Future<void> replaceGroupImageUrlsByPath({
    required String groupNodeId,
    required Map<String, String> urlMap, // localPath -> networkUrl 매핑
  }) async {
    if (urlMap.isEmpty) return;

    _isExecutingHistory = true;
    try {
      final node = editor.document.getNodeById(groupNodeId);

      if (node is ImageRowNode) {
        // 🎯 metadata에 업로드된 URL들을 저장 (imageUrls는 로컬 경로 유지)
        final meta = node.metadata;
        final uploadedUrls = Map<String, String>.from(
          (meta['uploadedUrls'] as Map<String, dynamic>?)
                  ?.cast<String, String>() ??
              {},
        );

        // 🎯 배치 업데이트: 여러 URL을 한 번에 추가
        uploadedUrls.addAll(urlMap);

        assert(() {
          debugPrint(
            '[EditorService] 🔄 ImageRow URL 배치 저장 (${uploadedUrls.length}/${node.imageUrls.length}): ${urlMap.length}개 추가',
          );
          return true;
        }());

        final updated = node.copyWith(
          metadata: {...meta, 'uploadedUrls': uploadedUrls},
        );
        editor.document.replaceNodeById(groupNodeId, updated);
      } else if (node is PageViewImageNode) {
        // 🎯 metadata에 업로드된 URL들을 저장 (imageUrls는 로컬 경로 유지)
        final meta = node.metadata;
        final uploadedUrls = Map<String, String>.from(
          (meta['uploadedUrls'] as Map<String, dynamic>?)
                  ?.cast<String, String>() ??
              {},
        );

        // 🎯 배치 업데이트: 여러 URL을 한 번에 추가
        uploadedUrls.addAll(urlMap);

        assert(() {
          debugPrint(
            '[EditorService] 🔄 PageView URL 배치 저장 (${uploadedUrls.length}/${node.imageUrls.length}): ${urlMap.length}개 추가',
          );
          return true;
        }());

        final updated = node.copyWith(
          metadata: {...meta, 'uploadedUrls': uploadedUrls},
        );
        editor.document.replaceNodeById(groupNodeId, updated);
      }
    } finally {
      _isExecutingHistory = false;
    }
  }

  // selection이 null이거나 nodeId를 찾지 못해도 문서 끝을 반환하여 안전
  int _getCaretNodeIndexSafe() {
    final doc = editor.document;
    final sel = editor.composer.selectionNotifier.value ?? _lastSelection;
    if (sel == null) return doc.nodeCount;
    final idx = doc.getNodeIndexById(sel.extent.nodeId);
    return idx == -1 ? doc.nodeCount : idx;
  }

  /// 공통 삽입 유틸: 현재 커서 위치에 컴포넌트 노드를 삽입한다.
  /// 만약 삽입 지점이 문서의 마지막(끝)이면, 그 아래에 빈 문단을 추가하고
  /// 커서를 그 빈 문단 앞으로 이동한다.
  void _insertComponentNodeAtNextLine(DocumentNode componentNode) {
    debugPrint('DEBUG: _insertComponentNodeAtNextLine: $componentNode');
    final doc = editor.document;
    final safeIndex = _getCaretNodeIndexSafe();
    int insertIndex = safeIndex;

    // 제목 노드(index 0)에 커서가 있으면 강제로 다음 라인에 삽입
    if (insertIndex == 0) {
      insertIndex = 1;
      debugPrint('🎯 제목 노드에 커서가 있음, 다음 라인(index 1)에 삽입');

      // 제목 다음에 빈 문단이 없으면 먼저 생성
      if (doc.nodeCount < 2) {
        final paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
        final ParagraphNode newParagraph = ParagraphNode(
          id: paragraphId,
          text: AttributedText(''),
          metadata: {'textAlign': 'center'},
        );
        doc.insertNodeAt(1, newParagraph);
        debugPrint('📝 제목 다음에 빈 문단 생성');
      }
    } else {
      // 현재 커서가 있는 문단에 텍스트가 있으면 다음 줄에 삽입
      if (insertIndex < doc.nodeCount) {
        final currentNode = doc.getNodeAt(insertIndex);
        if (currentNode is ParagraphNode) {
          final hasText = currentNode.text.text.trim().isNotEmpty;
          if (hasText) {
            insertIndex = insertIndex + 1;
            debugPrint('🎯 현재 문단에 텍스트가 있음, 다음 줄(index $insertIndex)에 삽입');
          }
        }
      }
    }

    if (insertIndex > doc.nodeCount) insertIndex = doc.nodeCount;

    final bool insertingAtEnd = insertIndex == doc.nodeCount;

    final edits = <EditRequest>[
      InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: componentNode),
    ];

    if (insertingAtEnd) {
      final String paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
      // 직전 문단의 정렬을 승계
      final String inheritedAlign = _getPreviousParagraphAlign(insertIndex);
      final ParagraphNode trailingParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: {'textAlign': inheritedAlign},
      );
      edits.add(
        InsertNodeAtIndexRequest(
          nodeIndex: insertIndex + 1,
          newNode: trailingParagraph,
        ),
      );
      // selection 이동은 프레임 이후로 지연하여 iOS 핸들 레이어의 NPE 방지
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: paragraphId,
                nodePosition: const TextNodePosition(offset: 0),
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
      });
    }

    editor.execute(edits);
    // 🎯 editor.execute()가 자동으로 document 리스너를 호출하므로 notifyListeners() 불필요
  }

  String _getPreviousParagraphAlign(int beforeIndex) {
    for (int i = beforeIndex - 1; i >= 0; i--) {
      final node = editor.document.getNodeAt(i);
      if (node is ParagraphNode) {
        final String? align = node.metadata['textAlign'] as String?;
        if (align != null) return align;
      }
    }
    return 'center';
  }

  // ===== 게시 가능 여부 판정 =====

  // 삽입된 문단 한 건만 이전 문단 정렬을 승계(O(1))
  void _ensureParagraphAlignmentForIndex(int index) {
    if (index < 0 || index >= document.length) return;
    final node = document.getNodeAt(index);
    if (node is! ParagraphNode) return;

    final Map<String, dynamic> meta = Map<String, dynamic>.from(node.metadata);
    final String? align = meta['textAlign'] as String?;
    if (align != null) return;

    String previousAlign = 'center';
    for (int i = index - 1; i >= 0; i--) {
      final prev = document.getNodeAt(i);
      if (prev is ParagraphNode) {
        final String? prevAlign = prev.metadata['textAlign'] as String?;
        if (prevAlign != null) {
          previousAlign = prevAlign;
        }
        break;
      }
    }

    meta['textAlign'] = previousAlign;
    final replaced = ParagraphNode(
      id: node.id,
      text: node.text,
      metadata: meta,
    );
    document.replaceNodeById(node.id, replaced);
  }

  // 제목 문단이 항상 존재하고 맨 위(index 0)에 있도록 보정한다.
  // 변경이 있었으면 true를 반환한다.
  void _ensureTitleAtTop() {
    int titleIndex = -1;
    ParagraphNode? titleNode;

    // 0,1번까지만 체크
    for (int i = 0; i < document.length && i < 2; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode && node.metadata['isTitle'] == true) {
        titleIndex = i;
        titleNode = node;
        break;
      }
    }

    if (titleIndex == -1) {
      // 제목 없으면 새로 추가
      document.insertNodeAt(
        0,
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(),
          // 기본 정렬을 중앙으로 보정
          metadata: {'isTitle': true, 'textAlign': 'center'},
        ),
      );
    } else if (titleIndex > 0) {
      // 이미 맨 위에 있지 않으면 위치만 교체
      final node = titleNode!;
      document
        ..deleteNode(titleNode.id) // 이벤트 발생 막고
        ..insertNodeAt(0, node); // 최종 이벤트는 1번만
    }

    // 제목 보정 후, 제목은 다른 텍스트의 정렬에 맞춰 보정
    final title = document.getNodeAt(0);
    if (title is ParagraphNode && title.metadata['isTitle'] == true) {
      // 다른 텍스트 문단의 정렬을 찾아서 제목에 적용
      String targetAlignment = 'center'; // 기본값(중앙)
      for (int i = 1; i < document.length; i++) {
        final node = document.getNodeAt(i);
        if (node is ParagraphNode) {
          final String? align = node.metadata['textAlign'] as String?;
          if (align != null) {
            targetAlignment = align;
            break;
          }
        }
      }

      final meta = Map<String, dynamic>.from(title.metadata);
      meta['textAlign'] = targetAlignment;
      final updated = ParagraphNode(
        id: title.id,
        text: title.text,
        metadata: meta,
      );
      document.replaceNodeById(title.id, updated);
    }
  }

  void _ensureOnlyFirstIsTitle() {
    try {
      // 0번째 문단은 제목 유지
      if (document.isNotEmpty) {
        final node0 = document.getNodeAt(0);
        if (node0 is ParagraphNode && node0.metadata['isTitle'] == true) {
          _lastTitleTextLength = node0.text.text.length;
        }

        if (node0 is ParagraphNode) {
          final meta0 = Map<String, dynamic>.from(node0.metadata);
          if (meta0['isTitle'] != true) {
            meta0['isTitle'] = true;
            document.replaceNodeById(
              node0.id,
              ParagraphNode(id: node0.id, text: node0.text, metadata: meta0),
            );
          }
        }
      }

      // 1번째 문단부터는 제목 금지(최소 수정: 바로 아래 문단만 확인)
      if (document.length > 1) {
        final node1 = document.getNodeAt(1);
        if (node1 is ParagraphNode) {
          final meta1 = Map<String, dynamic>.from(node1.metadata);
          if (meta1['isTitle'] == true) {
            meta1.remove('isTitle');
            document.replaceNodeById(
              node1.id,
              ParagraphNode(id: node1.id, text: node1.text, metadata: meta1),
            );
          }
        }
      }
    } catch (_) {}
  }

  bool isNodeUploading(String id) {
    if (_context == null) return false;
    final uploadService = _context!.read<UploadService>();
    return uploadService.hasActiveUploadForRef(id);
  }
}

// 🎯 문서 스냅샷 (전체 노드 + 순서 + 커서)
class _DocumentSnapshot {
  final Map<String, DocumentNode> nodes; // nodeId -> node
  final List<String> order; // 노드 순서
  final DocumentSelection? selection; // 커서 위치
  final int _cachedHashCode; // 🚀 캐시된 해시 (O(1) 비교용)

  _DocumentSnapshot({required this.nodes, required this.order, this.selection})
    : _cachedHashCode = _computeHash(nodes, order);

  // 🚀 해시 계산 (생성 시 한 번만)
  static int _computeHash(Map<String, DocumentNode> nodes, List<String> order) {
    // 노드 개수 + 순서 + 각 노드의 텍스트 해시
    final values = <int>[order.length, order.join(',').hashCode];

    // 샘플링: 첫/중간/마지막 노드만 체크 (성능 최적화)
    if (order.isNotEmpty) {
      final indices = [
        0,
        if (order.length > 1) order.length ~/ 2,
        if (order.length > 1) order.length - 1,
      ];

      for (final i in indices) {
        final id = order[i];
        final node = nodes[id];
        if (node is ParagraphNode) {
          values.add(node.text.text.hashCode);
        } else {
          values.add(node.runtimeType.hashCode);
        }
      }
    }

    return Object.hashAll(values);
  }

  @override
  int get hashCode => _cachedHashCode;
}
