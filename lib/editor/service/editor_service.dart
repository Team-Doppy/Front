import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/image/group_image_layout_selector.dart';
import 'package:doppy/editor/postwrite_screen.dart' show NodeType;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
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
  // ===== 디버그 로깅 =====
  // 히스토리/스킵/복구 판정은 매우 미묘한 타이밍 이슈가 많아서,
  // 문제 재현 시 "왜 스택에 안 쌓였는지"를 로그로 1:1 추적할 수 있도록 한다.
  static const bool _kHistoryVerboseLogs = kDebugMode;

  void _hlog(String message) {
    if (!_kHistoryVerboseLogs) return;
    debugPrint('[HistoryDbg] $message');
  }

  late final Editor editor;
  late final MutableDocument document;
  GlobalKey? _documentLayoutKey;
  ScrollController? _scrollController;
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

  // 🎯 Undo/Redo 히스토리 (전체 스냅샷)
  final List<_DocumentSnapshot> _undoStack = [];
  final List<_DocumentSnapshot> _redoStack = [];
  bool _isExecutingHistory = false;
  Timer? _historyTimer;
  bool _initialStateSaved = false; // 🎯 초기 상태 저장 완료 플래그 (중복 방지)
  bool _isDisposed =
      false; // ✅ dispose 이후 비동기 작업이 notifyListeners() 호출하는 크래시 방지
  bool _isDeletingNode = false; // 🎯 노드 삭제 중 플래그 (중복 저장 방지)
  bool _firstChangeAfterLoad = false; // 🎯 임시저장 불러온 직후 첫 변경사항 플래그
  bool _isSanitizingInvalidSelection =
      false; // 🎯 삭제된 노드를 가리키는 selection 강제 정리 중(재진입 방지)

  // ✅ 멘션 노드는 "전체가 하나의 특수 텍스트 블록"처럼 취급하지만,
  // 선택 핸들로 범위 삭제(DeleteSelection) 시에는 super_editor가 한 번에 많은 TextDeletedEvent를 낼 수 있다.
  // 이때 기존 멘션 삭제 로직이 노드 삭제/selection 이동까지 수행하면 re-entrancy로 편집기가 불안정해질 수 있어,
  // 범위 삭제에서는 멘션 메타데이터를 'post-frame'으로 안전하게 제거(일반 문단으로 강등)한다.
  final Set<String> _pendingMentionDemotions = <String>{};

  // ✅ "실제 변경이 있었으면 반드시 히스토리에 들어가야 한다"를 보장하기 위한 버전 값
  // - 문서에 의미있는 변경이 발생할 때마다 증가
  // - 스냅샷에 버전을 기록하고, undo/redo 직전에 현재 버전이 스택에 없으면 동기 저장으로 보강한다.
  int _documentVersion = 0;

  // ✅ "현재 상태가 히스토리에 아직 반영되지 않음" 플래그
  // - 사용자에 의한 DocumentChange가 발생하면 true
  // - 스냅샷이 스택에 push되면 false
  // - undo/redo 직전 flush는 이 값이 true일 때만 수행 (undo 후 무한 flush 방지)
  bool _hasPendingHistoryChanges = false;

  // ===== 안정형 삭제 히스토리(트랜잭션) =====
  // 기존: saveHistoryBeforeDelete()에서 before-state를 스택에 push + NodeRemovedEvent에서 after-state를 (비동기로) push
  // 문제:
  // - after-state가 microtask로 늦게 들어오면 "삭제 직후 undo 버튼 비활성"처럼 보인다.
  // - 삭제가 실제로 일어나지 않은 경우에도 before-state가 스택에 들어가 "유명무실한 undo step"이 생길 수 있다.
  //
  // 개선:
  // - before-state는 스택에 push하지 않고, baseline이 없을 때만 baseline(현재 상태)을 보장한다.
  // - 실제 삭제가 발생했을 때(NodeRemovedEvent) after-state를 **동기적으로** 1회만 push한다.
  bool _pendingDeleteHistory = false;

  // 제목은 썸네일 편집 화면에서 입력하므로 제목 노드 캐싱 로직 제거됨

  // ✅ 레지스트리 복구/자동 정리(빈 문단 삭제, 제목 보호 등)로 인한 문서 변경은
  // 히스토리에 담지 않는다. (유저가 한 변경이 아니며, Undo 스택을 오염시키기 때문)
  bool _isRecoveryOperation = false;

  // 🎯 NodeComponentService 참조 (노드 선택 해제용)
  BuildContext? _context;

  // ✅ 선택 범위 삭제(특수노드 포함) 처리 중에는 레지스트리 기반 자동 복원을 잠깐 막는다.
  // (삭제 요청이 들어오는 타이밍/대상 계산이 흔들려도 "삭제된 특수노드가 다시 살아나는" 불안정 방지)
  int _suppressSpecialNodeRestorationDepth = 0;
  bool get _isSuppressingSpecialNodeRestoration =>
      _suppressSpecialNodeRestorationDepth > 0;
  void _beginSuppressSpecialNodeRestoration() {
    _suppressSpecialNodeRestorationDepth++;
  }

  void _endSuppressSpecialNodeRestoration() {
    if (_suppressSpecialNodeRestorationDepth <= 0) return;
    _suppressSpecialNodeRestorationDepth--;
  }

  // ✅ 범위 삭제(여러 노드 삭제) 중에는 _trackChangeFromLog의 자동 스냅샷 저장을 막고,
  // 커맨드 끝에서 한 번만 after-state를 저장해서 undo step 오염을 방지한다.
  int _suppressHistoryTrackingDepth = 0;
  bool get _isSuppressingHistoryTracking => _suppressHistoryTrackingDepth > 0;
  void _beginSuppressHistoryTracking() {
    _suppressHistoryTrackingDepth++;
  }

  void _endSuppressHistoryTracking() {
    if (_suppressHistoryTrackingDepth <= 0) return;
    _suppressHistoryTrackingDepth--;
  }

  void _finalizeBatchDeleteHistory() {
    // saveHistoryBeforeDelete()가 세팅한 플래그가 남아있으면 다음 삭제에서 오동작할 수 있으므로 정리
    _isDeletingNode = false;
    _pendingDeleteHistory = false;
    _hlog(
      'finalizeBatchDeleteHistory: pending=false, isDeletingNode=false, suppressDepth=$_suppressHistoryTrackingDepth',
    );
    // ✅ 배치 삭제는 여러 NodeRemovedEvent가 연속으로 발생한다.
    // - 중간 단계에서 스냅샷을 계속 쌓으면 undo step이 오염된다.
    // - 그렇다고 비동기(microtask)로 after-state를 저장하면, 사용자가 즉시 Undo/Redo를 눌렀을 때
    //   "삭제 후 상태"가 누락되거나(redo가 안 먹음), Undo 이후 상태가 잘못 저장되어 redo 스택이 깨질 수 있다.
    //
    // 따라서 배치 삭제 커맨드가 끝나는 시점에 after-state를 **동기적으로** 1회 저장한다.
    if (_isExecutingHistory) return;
    _historyTimer?.cancel();
    final snapshot = _copyAllNodes();
    _addToHistoryStack(snapshot, '배치 삭제 후 상태 저장');
  }

  void _ensureParagraphAlignmentForNodeId(String nodeId) {
    final idx = document.getNodeIndexById(nodeId);
    if (idx == -1) return;
    _ensureParagraphAlignmentForIndex(idx);
  }

  void _logSelectionDeletionDebug(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  ({DocumentSelection selection, Set<String> coveredSpecialNodeIds})?
  _selectionAndSpecialNodesFromSelection(
    Document document,
    DocumentSelection selection,
  ) {
    if (selection.isCollapsed) return null;

    final coveredSpecialNodeIds = _getSpecialNodeIdsCoveredBySelection(
      document,
      selection,
    );
    if (coveredSpecialNodeIds.isEmpty) return null;

    return (selection: selection, coveredSpecialNodeIds: coveredSpecialNodeIds);
  }

  ({DocumentSelection selection, Set<String> coveredSpecialNodeIds})?
  _selectionAndSpecialNodesFromDocumentRange(
    Document document,
    DocumentRange range,
  ) {
    if (range.isCollapsed) return null;

    final selection =
        range is DocumentSelection
            ? range
            : DocumentSelection(base: range.start, extent: range.end);

    return _selectionAndSpecialNodesFromSelection(document, selection);
  }

  // ignore: prefer_function_declarations_over_variables
  late final EditRequestHandler _deleteSelectionWithSpecialNodesHandler = (
    ed,
    request,
  ) {
    if (request is! DeleteSelectionRequest) return null;

    final selection = ed.composer.selection;
    if (selection == null || selection.isCollapsed) return null;

    final coveredSpecialNodeIds = _getSpecialNodeIdsCoveredBySelection(
      ed.document,
      selection,
    );
    if (coveredSpecialNodeIds.isEmpty) return null;

    _logSelectionDeletionDebug(
      '[EditorService] 🧹 Intercept DeleteSelectionRequest: affinity=${request.affinity}, selection=$selection, coveredSpecialNodeIds=$coveredSpecialNodeIds',
    );

    return _DeleteSelectionAndSpecialNodesCommand(
      affinity: request.affinity,
      selectionForDeletion: selection,
      coveredSpecialNodeIds: coveredSpecialNodeIds,
      saveHistoryBeforeDelete: saveHistoryBeforeDelete,
      beginSuppressRestoration: _beginSuppressSpecialNodeRestoration,
      endSuppressRestoration: _endSuppressSpecialNodeRestoration,
      beginSuppressHistoryTracking: _beginSuppressHistoryTracking,
      endSuppressHistoryTracking: _endSuppressHistoryTracking,
      finalizeBatchDeleteHistory: _finalizeBatchDeleteHistory,
      ensureParagraphAlignmentForNodeId: _ensureParagraphAlignmentForNodeId,
      markSpecialNodeExplicitlyDeleted:
          (id) => removeSpecialNodeFromRegistry(id, explicitlyDeleted: true),
    );
  };

  // ignore: prefer_function_declarations_over_variables
  late final EditRequestHandler _deleteContentWithSpecialNodesHandler = (
    ed,
    request,
  ) {
    if (request is! DeleteContentRequest) return null;

    // 🎯 DeleteContentRequest의 실제 삭제 범위를 기준으로 "보라색으로 포함된" 특수노드들을 계산한다.
    // (IME/하드웨어 키보드 모두 DeleteContentRequest로 들어오므로 여기서 처리하면 플랫폼 무관)
    final range = request.documentRange;
    // ✅ 중요: 드래그 방향(아래→위 vs 위→아래)에 따라 `composer.selection`의 base/extent가 달라진다.
    // 반면 `documentRange.start/end`는 "문서상 앞/뒤"로 정규화될 수 있어 방향 정보가 사라질 수 있음.
    // 보라색 하이라이트 판정(특수노드 포함/미포함)과 동일한 기준을 유지하려면 composer.selection을 우선한다.
    final composerSel = ed.composer.selection;
    final parsed =
        (composerSel != null && !composerSel.isCollapsed)
            ? _selectionAndSpecialNodesFromSelection(ed.document, composerSel)
            : _selectionAndSpecialNodesFromDocumentRange(ed.document, range);
    if (parsed == null) return null;

    _logSelectionDeletionDebug(
      '[EditorService] 🧹 Intercept DeleteContentRequest: range=$range, selection=${parsed.selection}, coveredSpecialNodeIds=${parsed.coveredSpecialNodeIds}',
    );

    return _DeleteContentAndSpecialNodesCommand(
      documentRange: request.documentRange,
      selectionForCaretCalculation: parsed.selection,
      coveredSpecialNodeIds: parsed.coveredSpecialNodeIds,
      saveHistoryBeforeDelete: saveHistoryBeforeDelete,
      beginSuppressRestoration: _beginSuppressSpecialNodeRestoration,
      endSuppressRestoration: _endSuppressSpecialNodeRestoration,
      beginSuppressHistoryTracking: _beginSuppressHistoryTracking,
      endSuppressHistoryTracking: _endSuppressHistoryTracking,
      finalizeBatchDeleteHistory: _finalizeBatchDeleteHistory,
      ensureParagraphAlignmentForNodeId: _ensureParagraphAlignmentForNodeId,
      markSpecialNodeExplicitlyDeleted:
          (id) => removeSpecialNodeFromRegistry(id, explicitlyDeleted: true),
    );
  };

  // ignore: prefer_function_declarations_over_variables
  late final EditRequestHandler _deletePreviousDividerOnBackspaceHandler = (
    ed,
    request,
  ) {
    if (request is! DeleteContentRequest) return null;

    // ✅ "멀티 텍스트처럼" 동작:
    // - 다음 문단의 caret이 맨 앞(offset 0)일 때 Backspace를 누르면
    //   바로 이전 DividerNode를 즉시 삭제한다.
    final sel = ed.composer.selection;
    if (sel == null || !sel.isCollapsed) return null;

    final extent = sel.extent;
    final nodePos = extent.nodePosition;
    if (nodePos is! TextNodePosition) return null;
    if (nodePos.offset != 0) return null;

    final currentIndex = ed.document.getNodeIndexById(extent.nodeId);
    if (currentIndex <= 0) return null;

    final prevNode = ed.document.getNodeAt(currentIndex - 1);
    if (prevNode is! DividerNode) return null;

    return _DeletePreviousDividerOnBackspaceCommand(
      dividerNodeId: prevNode.id,
      caretNodeId: extent.nodeId,
      saveHistoryBeforeDelete: saveHistoryBeforeDelete,
    );
  };

  EditorService({
    required this.editor,
    required this.document,
    BuildContext? context,
    bool enableInitialStateSave = true, // 🎯 초기 상태 저장 활성화 여부
    bool useExternalTitleField = false,
  }) : _context = context {
    document.addListener(_onDocumentChanged);
    editor.composer.selectionNotifier.addListener(_onSelectionChanged);
    // 초기 제목 노드 id 캐시

    // ✅ 범위 삭제(특수노드 혼합) 보완 핸들러 설치
    // - 기본 DeleteContentRequest 처리 전에 가로채서, 누락된 특수노드까지 함께 삭제
    // - 레지스트리 복원 로직과 충돌하지 않도록 명시적 삭제로 표시
    if (!editor.requestHandlers.contains(
      _deleteSelectionWithSpecialNodesHandler,
    )) {
      editor.requestHandlers.insert(0, _deleteSelectionWithSpecialNodesHandler);
    }
    if (!editor.requestHandlers.contains(
      _deleteContentWithSpecialNodesHandler,
    )) {
      editor.requestHandlers.insert(0, _deleteContentWithSpecialNodesHandler);
    }
    // ✅ divider backspace 삭제 핸들러는 가장 먼저 실행되도록 마지막에 insert(0)
    if (!editor.requestHandlers.contains(
      _deletePreviousDividerOnBackspaceHandler,
    )) {
      editor.requestHandlers.insert(
        0,
        _deletePreviousDividerOnBackspaceHandler,
      );
    }

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
    if (_isDisposed) return;
    if (_isExecutingHistory || _initialStateSaved)
      return; // 🎯 이미 저장되었으면 중복 실행 방지

    // 🎯 추가 지연 (UI 렌더링 완료 보장)
    await Future.delayed(const Duration(milliseconds: 200));
    if (_isDisposed) return;

    // 🎯 노드 복사를 비동기로 처리 (각 노드 사이에 지연 추가)
    final snapshot = await _copyAllNodesAsync();
    if (_isDisposed) return;
    _addToHistoryStack(snapshot, '초기 상태 저장');
    _initialStateSaved = true; // 🎯 저장 완료 표시
    debugPrint('[EditorService] 📸 초기 상태 저장 (nodes: ${snapshot.nodes.length})');
  }

  // 🎯 빈 문단인지 확인 (중복 코드 제거)
  bool _shouldSkipNode(DocumentNode node) {
    if (node is ParagraphNode) {
      final isEmpty = node.text.text.trim().isEmpty;
      // 비어있으면 스킵
      return isEmpty;
    }
    return false;
  }

  // 🎯 모든 노드를 비동기로 deep copy (초기 상태 저장용, UI 블로킹 방지)
  Future<_DocumentSnapshot> _copyAllNodesAsync() async {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < document.nodeCount; i++) {
      if (_isDisposed) break;
      final node = document.getNodeAt(i);
      if (node == null) continue;

      // 🎯 빈 문단은 저장하지 않음 (제목 제외) - 중복 코드 제거
      if (_shouldSkipNode(node)) continue;

      // 🎯 노드 복사 전 지연 (UI 업데이트 기회 제공)
      await Future.delayed(const Duration(milliseconds: 50));
      if (_isDisposed) break;

      // 🎯 노드 복사를 microtask로 분산하여 UI 블로킹 방지
      await Future.microtask(() {
        if (_isDisposed) return;
        nodes[node.id] = _copyNode(node);
        order.add(node.id);
      });

      // 🎯 각 노드 복사 후 UI 업데이트 기회 제공 (Hang 방지)
      // 더 긴 지연으로 UI 스레드에 충분한 시간 제공
      if (i < document.nodeCount - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    final stickers = _copyAllStickersForSnapshot();

    return _DocumentSnapshot(
      nodes: nodes,
      order: order,
      stickers: stickers,
      version: _documentVersion,
      selection: null, // 🎯 커서 숨기기
      anchor:
          (editor.composer.selectionNotifier.value ?? _lastSelection)
              ?.extent, // ✅ 히스토리 UX용 앵커(스크롤 위치)
    );
  }

  // (삭제됨) _copyAllNodesAsyncFast:
  // 과거엔 즉시 저장을 microtask 기반 비동기로 수행했지만, undo/redo 타이밍 경합을 유발했다.
  // 안정성 우선 정책으로 즉시 저장은 동기 스냅샷(_copyAllNodes)만 사용한다.

  // 🎯 현재 상태를 히스토리에 저장
  void _saveCurrentState({bool immediate = false}) {
    if (_isExecutingHistory) return;

    if (immediate) {
      // ✅ 안정성 우선: 즉시 저장은 동기 스냅샷으로 저장한다.
      // (microtask 기반 비동기 저장은 undo/redo 타이밍 경합으로 누락/redo 파손을 만들 수 있음)
      _historyTimer?.cancel();
      final snapshot = _copyAllNodes();
      _hlog('saveCurrentState(immediate): pushing snapshot');
      _addToHistoryStack(snapshot, '즉시 저장');
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
          _hlog('debounce: skip push (equal snapshot)');
          _hasPendingHistoryChanges = false;
          return;
        }

        _addToHistoryStack(snapshot, '디바운싱 저장');
      });
    }
  }

  void _runRecoveryOperation(VoidCallback op) {
    final prev = _isRecoveryOperation;
    _isRecoveryOperation = true;
    try {
      op();
    } finally {
      _isRecoveryOperation = prev;
    }
  }

  // ✅ undo/redo 직전에 "현재 상태"가 아직 히스토리에 반영되지 않았으면 강제로 1회 저장
  // (텍스트 디바운스, 비동기 즉시 저장 타이밍에서 undo가 '안 먹는 것처럼' 보이는 문제 방지)
  void _flushHistoryIfNeeded({required String reason}) {
    if (_isExecutingHistory) return;
    _historyTimer?.cancel();

    // 사용자 변경이 없으면 flush 불필요 (undo 후 무한 flush 방지)
    if (!_hasPendingHistoryChanges) return;

    final snapshot = _copyAllNodes();
    if (_undoStack.isNotEmpty &&
        _areSnapshotsEqual(_undoStack.last, snapshot)) {
      _hlog('flush($reason): skip push (equal snapshot)');
      _hasPendingHistoryChanges = false;
      return;
    }
    _hlog('flush($reason): pushing snapshot');
    _addToHistoryStack(snapshot, 'flush($reason)');
  }

  /// 🎯 히스토리 스택에 스냅샷 추가 (중복 코드 제거)
  void _addToHistoryStack(_DocumentSnapshot snapshot, String logLabel) {
    if (_isDisposed) return;
    // ✅ 동일 스냅샷 중복 방지 (디바운스/flush 타이밍 보호)
    if (_undoStack.isNotEmpty &&
        _areSnapshotsEqual(_undoStack.last, snapshot)) {
      // ✅ 동일 상태라면 "대기 중인 변경"도 해소된 것으로 본다.
      // (그렇지 않으면 flush가 반복되거나, 불필요한 저장 시도가 계속될 수 있음)
      _hasPendingHistoryChanges = false;
      _hlog(
        'addToHistoryStack("$logLabel"): SKIP (equal)  undo=${_undoStack.length}, redo=${_redoStack.length}, version=${snapshot.version}',
      );
      return;
    }
    _undoStack.add(snapshot);
    _redoStack.clear();

    // ✅ 현재 상태가 히스토리에 반영됨
    _hasPendingHistoryChanges = false;

    // 최대 30개까지만 유지
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }

    debugPrint(
      '[EditorService] 📸 $logLabel (total: ${_undoStack.length}, nodes: ${snapshot.nodes.length})',
    );
    _hlog(
      'addToHistoryStack("$logLabel"): OK  undo=${_undoStack.length}, redo=cleared, version=${snapshot.version}',
    );

    // 🎯 Undo/Redo 버튼 상태 업데이트
    if (!_isDisposed) {
      notifyListeners();
    }
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
      _hlog('trackChange: SKIP (isExecutingHistory=true) change=$change');
      return;
    }
    // ✅ 복구/자동 정리로 인한 변화는 히스토리에 담지 않음
    if (_isRecoveryOperation) {
      _hlog('trackChange: SKIP (isRecoveryOperation=true) change=$change');
      return;
    }
    // ✅ 범위 삭제(배치 삭제) 중에는 after-state를 커맨드 끝에서 한 번만 저장한다.
    if (_isSuppressingHistoryTracking) {
      _hlog(
        'trackChange: SKIP (suppressHistoryTracking=true depth=$_suppressHistoryTrackingDepth) change=$change',
      );
      return;
    }

    _hlog(
      'trackChange: ENTER change=${change.runtimeType}, pendingDelete=$_pendingDeleteHistory, isDeletingNode=$_isDeletingNode, pendingHistory=$_hasPendingHistoryChanges',
    );

    try {
      // 🎯 히스토리가 비어있으면 현재 상태를 초기 상태로 저장 (임시저장 불러온 직후에도 동작)
      if (_undoStack.isEmpty) {
        debugPrint('[EditorService] 🎯 히스토리 비어있음 - 현재 상태를 초기 상태로 저장');
        _hlog(
          'trackChange: undoStack empty -> saveCurrentState(immediate=true) as baseline',
        );
        _saveCurrentState(immediate: true);
        // 🎯 초기 상태 저장 후에도 변경 이벤트는 계속 처리해야 함 (return 하지 않음)
      }

      // TextInsertionEvent, TextDeletedEvent - 디바운싱 적용 (1초 후 저장)
      // 🎯 단, 임시저장 불러온 직후 첫 변경사항만 즉시 저장, 그 다음부터는 디바운싱
      if (change is TextInsertionEvent || change is TextDeletedEvent) {
        final bool firstAfterLoad = _firstChangeAfterLoad;
        if (firstAfterLoad) {
          // 🎯 임시저장 불러온 직후 첫 변경사항은 즉시 저장 (히스토리 누락 방지)
          debugPrint('[EditorService] 🎯 임시저장 불러온 직후 첫 변경 - 즉시 저장');
          _saveCurrentState(immediate: true);
          _firstChangeAfterLoad = false; // 🎯 플래그 해제 (다음부터는 디바운싱)
        } else {
          // 🎯 그 다음부터는 디바운싱 적용
          _saveCurrentState(immediate: false);
        }
        _hlog(
          'trackChange: TEXT -> ${firstAfterLoad ? "immediate(firstAfterLoad)" : "debounce"}',
        );
        return;
      }

      // 🎯 NodeRemovedEvent는 _deleteNode에서 이미 삭제 전 상태를 저장했으므로 중복 저장 방지
      if (change is NodeRemovedEvent) {
        // ✅ 안정형: 삭제 후 상태(after-state)는 동기적으로 1회만 저장한다.
        // - _pendingDeleteHistory=true 인 경우: 삭제 버튼/특수노드 범위 삭제 등 "유저 삭제"의 after-state 저장
        // - 그 외: 다른 경로의 삭제도 즉시 저장(동기)
        if (_pendingDeleteHistory || _isDeletingNode) {
          _hlog(
            'trackChange: NodeRemovedEvent detected user-delete (pendingDelete=$_pendingDeleteHistory,isDeletingNode=$_isDeletingNode) -> after-state push',
          );
          _pendingDeleteHistory = false;
          _isDeletingNode = false;
        }
        _saveCurrentState(immediate: true);
        return;
      }

      // 🎯 NodeInsertedEvent (엔터, 이미지/영상 추가), NodeChangeEvent (노드 변경), NodeMovedEvent (이동) - 즉시 저장!
      if (change is NodeInsertedEvent ||
          change is NodeChangeEvent ||
          change is NodeMovedEvent) {
        _hlog('trackChange: NODE(${change.runtimeType}) -> immediate push');
        _saveCurrentState(immediate: true);
        return;
      }
    } catch (e) {
      debugPrint('[EditorService] 변경 추적 실패: $e');
      _hlog('trackChange: ERROR $e');
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

    final stickers = _copyAllStickersForSnapshot();

    return _DocumentSnapshot(
      nodes: nodes,
      order: order,
      stickers: stickers,
      version: _documentVersion,
      selection: null, // 🎯 커서 숨기기
      anchor:
          (editor.composer.selectionNotifier.value ?? _lastSelection)
              ?.extent, // ✅ 히스토리 UX용 앵커(스크롤 위치)
    );
  }

  List<Sticker> _copyAllStickersForSnapshot() {
    try {
      if (_context == null) return const <Sticker>[];
      final stickerService = _context!.read<StickerService>();
      final list = stickerService.stickers;
      if (list.isEmpty) return const <Sticker>[];
      return list
          .map((s) {
            final c = s.content;
            dynamic copiedContent = c;
            if (c is Uint8List) {
              copiedContent = Uint8List.fromList(c);
            } else if (c is Map) {
              copiedContent = Map<String, dynamic>.from(
                c.cast<String, dynamic>(),
              );
            }
            return Sticker(
              id: s.id,
              type: s.type,
              content: copiedContent,
              position: s.position,
              scale: s.scale,
              rotation: s.rotation,
              opacity: s.opacity,
              zIndex: s.zIndex,
              locked: s.locked,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const <Sticker>[];
    }
  }

  // 🎯 노드 deep copy
  DocumentNode _copyNode(DocumentNode node) {
    if (node is ParagraphNode) {
      // metadata에는 textAlign, isTitle, fontFamily 등이 포함됨
      final copiedMetadata = Map<String, dynamic>.from(node.metadata);

      // 🎯 AttributedText 전체 복사 (모든 스타일 유지: bold, italic, color, font, highlight, spoiler 등)
      final AttributedText attributed = node.text.copyText(0, node.text.length);

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

  /// 글쓰기 화면의 스크롤 컨트롤러를 주입한다.
  /// (Undo/Redo 시 히스토리 스냅샷에 저장된 문서 위치로 스크롤 UX 제공)
  void setScrollController(ScrollController controller) {
    _scrollController = controller;
  }

  void clearScrollController() {
    _scrollController = null;
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

  Set<String> _getSpecialNodeIdsCoveredBySelection(
    Document doc,
    DocumentSelection selection,
  ) {
    final baseIndex = doc.getNodeIndexById(selection.base.nodeId);
    final extentIndex = doc.getNodeIndexById(selection.extent.nodeId);
    if (baseIndex == -1 || extentIndex == -1) return <String>{};

    final start = math.min(baseIndex, extentIndex);
    final end = math.max(baseIndex, extentIndex);

    final ids = <String>{};
    for (int i = start; i <= end; i++) {
      final node = doc.getNodeAt(i);
      if (node == null) continue;
      if (!_isSpecialNode(node)) continue;
      if (_isNodeCoveredBySelection(doc, selection, node.id)) {
        ids.add(node.id);
      }
    }
    return ids;
  }

  // selection이 이 특수 노드를 포함하는지 계산. 경계가 특수노드인 경우 downstream일 때만 포함.
  // (각 컴포넌트의 보라색 하이라이트 판정과 동일해야 한다)
  bool _isNodeCoveredBySelection(
    Document doc,
    DocumentSelection selection,
    String nodeId,
  ) {
    final baseIndex = doc.getNodeIndexById(selection.base.nodeId);
    final extentIndex = doc.getNodeIndexById(selection.extent.nodeId);
    final myIndex = doc.getNodeIndexById(nodeId);
    if (baseIndex == -1 || extentIndex == -1 || myIndex == -1) return false;

    final start = math.min(baseIndex, extentIndex);
    final end = math.max(baseIndex, extentIndex);
    if (myIndex < start || myIndex > end) return false;

    // 시작 경계가 이 노드인 경우: base/extent 중 누가 start인지에 따라 affinity 체크
    if (myIndex == start) {
      final boundary = baseIndex == start ? selection.base : selection.extent;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        // ✅ start 경계는 upstream일 때 포함 (아래→위 드래그 대칭 보장)
        return pos.affinity == TextAffinity.upstream;
      }
    }

    // 끝 경계가 이 노드인 경우
    if (myIndex == end) {
      final boundary = extentIndex == end ? selection.extent : selection.base;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }

    // 범위 내부에 완전히 포함
    return true;
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

    _hlog(
      'saveHistoryBeforeDelete: ENTER undo=${_undoStack.length}, pendingHistory=$_hasPendingHistoryChanges, firstAfterLoad=$_firstChangeAfterLoad',
    );

    // ✅ 삭제 직전에는 "현재 상태가 히스토리에 반영되어 있는지"만 보장한다.
    // - 텍스트 디바운스 중이면 flush해서 baseline을 확정
    // - 히스토리가 비어있으면 현재 상태를 baseline으로 1회 저장
    _flushHistoryIfNeeded(reason: 'beforeDelete');
    if (_undoStack.isEmpty) {
      final baseline = _copyAllNodes();
      _addToHistoryStack(baseline, 'baseline(beforeDelete)');
      _initialStateSaved = true;
      _hlog(
        'saveHistoryBeforeDelete: baseline pushed (undo now=${_undoStack.length})',
      );
    }

    // 🎯 NodeRemovedEvent에서 after-state를 1회만 저장하도록 표시
    _pendingDeleteHistory = true;
    _isDeletingNode = true;
    _hlog(
      'saveHistoryBeforeDelete: flags set pendingDelete=true, isDeletingNode=true',
    );
  }

  // 🎯 Undo 실행
  void undo() {
    _flushHistoryIfNeeded(reason: 'undo');
    _executeHistoryOperation(
      canExecute: canUndo,
      errorMessage: 'Undo 불가 (첫 상태)',
      operation: () {
        // 🎯 현재 상태를 redo 스택에 저장
        // ✅ UX: Undo 시에는 "복원된(previous) 상태"의 앵커가 아니라,
        // 방금 되돌린 작업(current)의 앵커로 이동해야 사용자가 기대하는 위치(수정한 곳)를 유지한다.
        final undoneSnapshot = _undoStack.removeLast();
        _redoStack.add(undoneSnapshot);

        // 🎯 이전 상태로 복원
        final previousSnapshot = _undoStack.last;
        _restoreFromSnapshot(previousSnapshot);
        _scheduleScrollToSnapshotAnchor(
          undoneSnapshot,
          useJumpTo: true, // ✅ 요청: 이 케이스는 jumpTo로 즉시 이동
        );
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
    _flushHistoryIfNeeded(reason: 'redo');
    _executeHistoryOperation(
      canExecute: canRedo,
      errorMessage: 'Redo 불가 (없음)',
      operation: () {
        // 🎯 Redo 스택에서 다음 상태 가져오기
        final nextSnapshot = _redoStack.removeLast();
        _undoStack.add(nextSnapshot);

        // 🎯 다음 상태로 복원
        _restoreFromSnapshot(nextSnapshot);
        _scheduleScrollToSnapshotAnchor(
          nextSnapshot,
          useJumpTo: true, // ✅ Undo/Redo는 동일한 UX로 즉시 이동
        );

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

  void _scheduleScrollToSnapshotAnchor(
    _DocumentSnapshot snapshot, {
    double thresholdPx = 400.0,
    bool useJumpTo = false,
  }) {
    // ✅ undo/redo 직후 레이아웃이 안정화된 다음 프레임에서 스크롤한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSnapshotAnchorIfFar(
        snapshot,
        thresholdPx: thresholdPx,
        useJumpTo: useJumpTo,
      );
    });
  }

  Future<void> _scrollToSnapshotAnchorIfFar(
    _DocumentSnapshot snapshot, {
    required double thresholdPx,
    required bool useJumpTo,
  }) async {
    final ctrl = _scrollController;
    if (ctrl == null || !ctrl.hasClients) return;
    final anchor = snapshot.anchor;
    if (anchor == null) return;

    final layout = _documentLayoutKey?.currentState as DocumentLayout?;
    if (layout == null) return;

    Rect? rect;
    try {
      rect = layout.getRectForPosition(anchor);
    } catch (_) {
      rect = null;
    }
    if (rect == null) return;

    final viewport = ctrl.position.viewportDimension;
    if (viewport <= 0) return;

    final currentCenterY = ctrl.offset + viewport / 2.0;
    final targetCenterY = rect.center.dy;
    final delta = (targetCenterY - currentCenterY).abs();
    if (delta < thresholdPx) return;

    final targetOffset = (targetCenterY - viewport / 2.0).clamp(
      0.0,
      ctrl.position.maxScrollExtent,
    );

    try {
      if (useJumpTo) {
        ctrl.jumpTo(targetOffset);
      } else {
        await ctrl.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {
      // scroll 중 detach 등은 무시
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

    // ✅ undo/redo는 문서 스냅샷만 복원한다.
    // NodeComponentService는 "세션 캐시"(예: 스포일러 임시 해제)를 들고 있어
    // 문서 metadata와 충돌하면 undo/redo 직후 화면 상태가 어긋날 수 있다.
    // 따라서 복원 시작 시 세션 캐시를 조용히 비워 문서 상태와 동기화한다.
    try {
      NodeComponentService().clearSpoilers(notify: false);
    } catch (_) {}

    // 🎯 2. 레지스트리 및 명시적 삭제 목록 초기화 (복원 전 정리)
    _specialNodeRegistry.clear();
    _explicitlyDeletedNodes.clear();

    // 🎯 2-1. 스티커 복원 (문서 복원 전에 해도 무방)
    try {
      if (_context != null) {
        final stickerService = _context!.read<StickerService>();
        stickerService.restoreFromSnapshot(snapshot.stickers);
      }
    } catch (_) {}

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

    // 🎯 4. 커서 숨기기
    try {
      editor.composer.clearSelection();
      debugPrint('[EditorService] ✅ 커서 숨김');
    } catch (e) {
      debugPrint('[EditorService] 커서 숨기기 실패: $e');
    }
  }

  // 문서 변경 리스너: 구조가 변했을 때만 마진 재계산
  void _onDocumentChanged(DocumentChangeLog changeLog) {
    if (changeLog.changes.isEmpty) return;
    final primaryChange = changeLog.changes.first;
    assert(() {
      debugPrint(
        'changeLog.changes: ${changeLog.changes.map((c) => c.runtimeType).toList()}',
      );
      return true;
    }());

    String recoveryReason(DocumentChange change) {
      // ✅ 전역 recovery 구간이면 무조건 recovery
      if (_isRecoveryOperation) return 'globalRecovery';

      if (change is NodeInsertedEvent) {
        // ✅ "빈 문단 자동 추가"는 유저에게 숨겨야 하는 내부 보정이므로 히스토리에서 제외
        try {
          final inserted = document.getNodeById(change.nodeId);
          if (inserted is ParagraphNode) {
            final bool isTitle = inserted.metadata['isTitle'] == true;
            final bool isMention = inserted.metadata['mention'] == true;
            final bool isEmpty = inserted.text.text.trim().isEmpty;
            if (!isTitle && !isMention && isEmpty) {
              return 'autoEmptyParagraphInserted';
            }
          }
        } catch (_) {}
      }

      if (change is NodeRemovedEvent) {
        final removedId = change.nodeId;

        // 자동 삭제 예약으로 지워지는 빈 ParagraphNode는 복구/정리로 간주
        if (_pendingDeletionNodeIds.contains(removedId)) {
          return 'pendingEmptyParagraphDeletion';
        }

        // ✅ 삭제 버튼/범위 삭제 커맨드에서 시작된 "유저 삭제"는 복구(recovery)로 분류하면 안 된다.
        // (특수 노드가 레지스트리에 남아있는 순간/타이밍 이슈로 recovery로 오판되면
        //  삭제 직후 undo 스택이 안 쌓이는 문제가 발생할 수 있다)
        if (_pendingDeleteHistory || _isDeletingNode) return '';

        // 제목 노드 삭제는 제목 보호 복구로 간주

        // 레지스트리에 등록된 특수 노드가 "명시적 삭제 없이" 사라지면 자동 복구 후보
        if (_specialNodeRegistry.containsKey(removedId) &&
            !_explicitlyDeletedNodes.contains(removedId)) {
          final sel = editor.composer.selectionNotifier.value;
          final isDownstream =
              sel != null &&
              sel.extent.nodeId == removedId &&
              sel.extent.nodePosition is UpstreamDownstreamNodePosition &&
              sel.extent.nodePosition ==
                  const UpstreamDownstreamNodePosition.downstream();
          if (!isDownstream) {
            return 'registryRestorationCandidate';
          }
        }
      }

      return '';
    }

    // ✅ 중요한 변경이 여러 개 묶여서 들어오는 경우가 있다.
    // 예) 삭제 시 selection 정리 + 노드 삭제 이벤트가 같이 들어오는데,
    // 현재처럼 changes[0]만 보면 "노드 삭제"가 누락되어 undo 스택이 안 쌓일 수 있다.
    final nonRecoveryChanges = <DocumentChange>[];
    for (final c in changeLog.changes) {
      final reason = recoveryReason(c);
      if (reason.isEmpty) {
        nonRecoveryChanges.add(c);
      } else {
        _hlog('onDocChanged: recovery change=${c.runtimeType} reason=$reason');
      }
    }

    _hlog(
      'onDocChanged: primary=${primaryChange.runtimeType} changes=${changeLog.changes.length} nonRecovery=${nonRecoveryChanges.map((c) => c.runtimeType).toList()}',
    );

    // ✅ undo/redo 복원 과정 + 자동 복구는 "사용자 변경"이 아니므로 버전/플래그/히스토리 반영 제외
    if (!_isExecutingHistory && nonRecoveryChanges.isNotEmpty) {
      _documentVersion++;
      _hasPendingHistoryChanges = true;
    }

    // 🎯 변경된 노드 추적 (복구/자동 정리 변화는 스킵)
    // - 한 로그에 여러 변경이 섞여 들어오므로, 히스토리 저장 트리거가 되는 변경을 우선 선택한다.
    if (nonRecoveryChanges.isNotEmpty) {
      DocumentChange pick(DocumentChange a, DocumentChange b) {
        int rank(DocumentChange c) {
          if (c is NodeRemovedEvent) return 0;
          if (c is NodeInsertedEvent) return 1;
          if (c is NodeMovedEvent) return 2;
          if (c is NodeChangeEvent) return 3;
          if (c is TextInsertionEvent) return 4;
          if (c is TextDeletedEvent) return 4;
          return 10;
        }

        return rank(a) <= rank(b) ? a : b;
      }

      var chosen = nonRecoveryChanges.first;
      for (final c in nonRecoveryChanges.skip(1)) {
        chosen = pick(chosen, c);
      }

      _trackChangeFromLog(chosen);
    }

    // 제목 id 캐시 갱신 (구조 변경/복구 모두 포함)

    // 🎯 텍스트 입력/삭제 시 노드 선택 자동 해제 (가볍게 처리)
    if ((primaryChange is TextInsertionEvent ||
            primaryChange is TextDeletedEvent) &&
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

    // ✅ 멘션 스타일은 stylesheet에서 "본문 + bold"로 렌더링한다.
    // 따라서 멘션 노드의 bold attribution을 강제/부분 제거하는 로직은 제거한다.

    // 🎯 멘션 문단(ParagraphNode with metadata.mention == true)에서 삭제가 발생하면
    // 노드를 한 번에 삭제하도록 처리
    if (primaryChange is TextDeletedEvent) {
      try {
        // TextDeletedEvent에서 nodeId 가져오기
        String? targetNodeId;
        try {
          targetNodeId = (primaryChange as dynamic).nodeId as String?;
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
                  deletedOffset = (primaryChange as dynamic).offset as int?;
                  deletedLength = (primaryChange as dynamic).length as int?;
                } catch (_) {}

                // ✅ 범위 삭제(선택 핸들 백스페이스) 방어:
                // - deletedLength > 1 이면 "드래그로 선택된 구간 삭제"일 가능성이 높다.
                // - 이 경우 멘션 전용 삭제/노드삭제/selection 이동 로직이 re-entrancy를 일으켜
                //   키보드/selection이 꼬이고 편집기가 먹통이 되는 케이스가 있다.
                // - 따라서 범위 삭제에서는 멘션을 '일반 문단'으로 강등만 하고 나머지는 기본 삭제에 맡긴다.
                if ((deletedLength ?? 1) > 1) {
                  _scheduleDemoteMentionNode(targetNodeId);
                  return;
                }

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

                // ✅ 멘션 텍스트가 더 이상 온전하지 않으면(부분 삭제/편집) 멘션 메타데이터만 제거한다.
                // (이 상태에서 멘션 전용 로직을 계속 적용하면 selection 이동/노드 삭제가 꼬일 수 있음)
                if (!currentText.startsWith(mentionText)) {
                  _scheduleDemoteMentionNode(targetNodeId);
                  return;
                }

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
                  final dynamic rawAlign = node.metadata['textAlign'];
                  final newParagraph = ParagraphNode(
                    id: targetNodeId,
                    text: newText,
                    metadata: <String, dynamic>{
                      if (rawAlign is String) 'textAlign': rawAlign,
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

                // 🎯 노드가 여전히 존재하는지 확인 (이중 삭제 방지)
                if (document.getNodeById(targetNodeId) == null) {
                  debugPrint('[EditorService] ⚠️ 멘션 노드가 이미 삭제됨: $targetNodeId');
                  return;
                }

                // ✅ 키보드가 내려갔다가 올라오는 원인:
                // - clearSelection()은 IME 연결/selection 정책에 의해 키보드를 닫게 만들 수 있다.
                // - 멘션 노드를 삭제하기 전에 "다른 노드로 caret을 먼저 이동"해서
                //   selection이 삭제될 노드를 가리키지 않게 만들면, IME 매핑 오류도 피하면서
                //   키보드 플리커도 방지할 수 있다.
                if (savedTargetPosition != null) {
                  try {
                    editor.execute([
                      ChangeSelectionRequest(
                        DocumentSelection.collapsed(
                          position: savedTargetPosition,
                        ),
                        SelectionChangeType.placeCaret,
                        SelectionReason.userInteraction,
                      ),
                      const ClearComposingRegionRequest(),
                    ]);
                  } catch (e) {
                    debugPrint('[EditorService] 멘션 삭제 전 커서 이동 실패: $e');
                  }
                } else {
                  // 이동할 대상 노드가 없다면, 노드를 삭제하지 말고 일반 빈 문단으로 교체한다.
                  // (문서가 비는 순간 selection이 null이 되어 IME가 닫힐 수 있음)
                  try {
                    final dynamic rawAlign = node.metadata['textAlign'];
                    final newParagraph = ParagraphNode(
                      id: targetNodeId,
                      text: AttributedText(''),
                      metadata: <String, dynamic>{
                        if (rawAlign is String) 'textAlign': rawAlign,
                      },
                    );
                    editor.execute([
                      ReplaceNodeRequest(
                        existingNodeId: targetNodeId,
                        newNode: newParagraph,
                      ),
                      ChangeSelectionRequest(
                        DocumentSelection.collapsed(
                          position: DocumentPosition(
                            nodeId: targetNodeId,
                            nodePosition: const TextNodePosition(offset: 0),
                          ),
                        ),
                        SelectionChangeType.placeCaret,
                        SelectionReason.userInteraction,
                      ),
                      const ClearComposingRegionRequest(),
                    ]);
                  } catch (e) {
                    debugPrint('[EditorService] 멘션 노드 빈 문단 교체 실패: $e');
                  }
                  return;
                }

                // 노드 삭제
                try {
                  final idToDelete = targetNodeId;
                  _runRecoveryOperation(() {
                    document.deleteNode(idToDelete);
                  });
                  debugPrint('[EditorService] 멘션 노드 삭제 완료: $targetNodeId');
                } catch (e) {
                  debugPrint('[EditorService] 멘션 노드 삭제 실패: $e');
                  return;
                }

                // 삭제 직후, caret은 이미 다른 노드로 이동해 있으므로 추가 조작은 하지 않는다.
                // (불필요한 post-frame selection 변경은 IME/키보드 플리커를 유발할 수 있음)
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

    if (primaryChange is NodeRemovedEvent) {
      final removedNodeId = primaryChange.nodeId;

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
        // ✅ 선택 범위 삭제(특수노드 포함) 처리 중에는 레지스트리 기반 복원을 무조건 막는다.
        // - 커맨드에서 선마킹을 최대한 하지만, 계산 누락/타이밍 이슈가 있어도 "삭제→복원" 경쟁을 원천 차단.
        if (_isSuppressingSpecialNodeRestoration) {
          _specialNodeRegistry.remove(removedNodeId);
          shouldNotify = true;
        } else {
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
                  final insertIndex = nodeInfo.index.clamp(
                    0,
                    document.nodeCount,
                  );

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
                  _runRecoveryOperation(() {
                    document.insertNodeAt(insertIndex, restoredNode);
                  });

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
      }

      // 🎯 최종: 한 번만 notifyListeners 호출
      if (shouldNotify) {
        notifyListeners();
      }
      return;
    }

    if (primaryChange is NodeInsertedEvent) {
      // 🎯 멘션 노드 다음에 문단이 생성되면 볼드 attribution 제거
      try {
        final insertedNode = document.getNodeAt(primaryChange.insertionIndex);
        if (insertedNode is ParagraphNode &&
            insertedNode.metadata['mention'] != true &&
            primaryChange.insertionIndex > 0) {
          // 이전 노드가 멘션 노드인지 확인
          final prevNode = document.getNodeAt(primaryChange.insertionIndex - 1);
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
                    _runRecoveryOperation(() {
                      editor.execute([
                        ReplaceNodeRequest(
                          existingNodeId: insertedNode.id,
                          newNode: newNode,
                        ),
                      ]);
                    });
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
      _runRecoveryOperation(() {
        _ensureParagraphAlignmentForIndex(primaryChange.insertionIndex);
      });
      // 삽입 지점 주변(상/하/본인)만 마진 재계산
      //_recomputeParagraphMarginsAround(primaryChange.insertionIndex);
      // 문서 구조가 변했으므로 UI 갱신 필요
      notifyListeners();
      return;
    }

    if (primaryChange is NodeMovedEvent) {
      // 이동 전/후 주변만 마진 재계산
      //_recomputeParagraphMarginsAround(primaryChange.from);
      //_recomputeParagraphMarginsAround(primaryChange.to);
      // 문서 구조가 변했으므로 UI 갱신 필요
      notifyListeners();
      return;
    }

    if (primaryChange is NodeChangeEvent) {
      // 타입 변경 등 구조 영향 가능 → 해당 인덱스만 우선 보정, 없으면 전체
      final idx = document.getNodeIndexById(primaryChange.nodeId);
      if (idx != -1) {
        //_recomputeParagraphMarginsAround(idx);
        _runRecoveryOperation(() {
          _ensureParagraphAlignmentForIndex(getEditingIndex());
        });
      } else {
        // _recomputeParagraphMargins();
      }
      // 문서 구조/내용이 변했으므로 UI 갱신 필요
      notifyListeners();
      return;
    }

    if (primaryChange is TextInsertionEvent ||
        primaryChange is TextDeletedEvent) {
      // 본문 텍스트 변경으로 UI 갱신 통지
      notifyListeners(); // 🎯 한 번만 호출
      return;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
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

    // ✅ iOS IME(super_editor) 크래시 방지:
    // selection이 문서에 없는 nodeId를 가리키면 super_editor 내부에서 null-assertion 크래시가 발생할 수 있다.
    // (InspectDocumentSelection.selectUpstreamPosition 등)
    // 따라서 즉시 selection을 clear 해서 "유효하지 않은 selection" 상태를 외부가 관찰하지 못하게 한다.
    if (sel != null && !_isSanitizingInvalidSelection) {
      final baseExists = document.getNodeById(sel.base.nodeId) != null;
      final extentExists = document.getNodeById(sel.extent.nodeId) != null;
      if (!baseExists || !extentExists) {
        _isSanitizingInvalidSelection = true;
        debugPrint(
          '[EditorService] ⚠️ Invalid selection detected → force clear (baseExists=$baseExists, extentExists=$extentExists, base=${sel.base.nodeId}, extent=${sel.extent.nodeId})',
        );
        try {
          editor.composer.clearSelection();
        } catch (_) {}
        if (_context != null) {
          try {
            final nodeService = _context!.read<NodeComponentService>();
            nodeService.clearSelectionSilently();
            nodeService.clearHighlightedSelectionSilently();
          } catch (_) {}
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isSanitizingInvalidSelection = false;
        });
        return;
      }
    }

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
        // 여기까지 오면 selectionNotifier가 "삭제된 노드"를 가리키고 있음 → 강제 해제
        if (!_isSanitizingInvalidSelection) {
          _isSanitizingInvalidSelection = true;
          try {
            editor.composer.clearSelection();
          } catch (_) {}
          if (_context != null) {
            try {
              final nodeService = _context!.read<NodeComponentService>();
              nodeService.clearSelectionSilently();
              nodeService.clearHighlightedSelectionSilently();
            } catch (_) {}
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _isSanitizingInvalidSelection = false;
          });
        }
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
                              _runRecoveryOperation(() {
                                document.deleteNode(nodeIdToDelete);
                              });
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
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode && node.metadata['isTitle'] == true) {
        return node.text.text.trim().isNotEmpty;
      }
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

    // ✅ 과거에는 0번을 "제목"으로 가정하고 1번부터 검사했지만,
    // 현재는 제목이 외부(썸네일 편집 화면)에서 입력되는 케이스가 있어 0번이 본문일 수 있다.
    // 따라서 0번부터 검사하되, isTitle==true 노드만 본문 검사에서 제외한다.
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      if (node is ParagraphNode) {
        if (node.metadata['isTitle'] == true) continue;
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
    debugPrint(
      '[EditorService] 🔀 병합 시작: dragging=$draggingImageId, target=$targetImageId, isFromLeft=$isFromLeft',
    );

    final draggingNode = document.getNodeById(draggingImageId);
    final targetNode = document.getNodeById(targetImageId);

    if (draggingNode == null || targetNode == null) {
      debugPrint(
        '[EditorService] ❌ 병합 실패: 노드를 찾을 수 없음 (dragging: ${draggingNode != null}, target: ${targetNode != null})',
      );
      return;
    }

    debugPrint(
      '[EditorService] 📋 병합 대상 노드 타입: dragging=${draggingNode.runtimeType}, target=${targetNode.runtimeType}',
    );

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

    // ✅ 병합 가능한 URL:
    // - 네트워크(http/https)
    // - 로컬(file://, /var/... 등)
    // Row는 로컬도 렌더링/업로드 흐름을 지원하므로 병합을 막지 않는다.
    bool _isMergeableImageUrl(String u) {
      if (u.isEmpty) return false;
      return u.startsWith('http://') ||
          u.startsWith('https://') ||
          u.startsWith('file://') ||
          u.startsWith('/');
    }

    if (!_isMergeableImageUrl(draggingNode.imageUrl) ||
        !_isMergeableImageUrl(targetNode.imageUrl)) {
      debugPrint(
        '[EditorService] ❌ 병합 스킵: URL이 병합 불가 (draggingUrl=${draggingNode.imageUrl}, targetUrl=${targetNode.imageUrl})',
      );
      return;
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
    Map<String, dynamic>? draggingMeta;
    Map<String, dynamic>? targetMeta;
    try {
      draggingMeta =
          (draggingNode as dynamic).metadata as Map<String, dynamic>?;
      draggingMediaId = draggingMeta?['mediaId']?.toString();
      debugPrint('[EditorService] 📦 드래그 이미지 메타데이터: mediaId=$draggingMediaId');
      if (draggingMeta != null && draggingMeta.containsKey('imageDimensions')) {
        debugPrint(
          '[EditorService] 📏 드래그 이미지 imageDimensions: ${draggingMeta['imageDimensions']}',
        );
      }
    } catch (e) {
      debugPrint('[EditorService] ⚠️ 드래그 이미지 메타데이터 추출 실패: $e');
    }
    try {
      targetMeta = (targetNode as dynamic).metadata as Map<String, dynamic>?;
      targetMediaId = targetMeta?['mediaId']?.toString();
      debugPrint('[EditorService] 📦 타겟 이미지 메타데이터: mediaId=$targetMediaId');
      if (targetMeta != null && targetMeta.containsKey('imageDimensions')) {
        debugPrint(
          '[EditorService] 📏 타겟 이미지 imageDimensions: ${targetMeta['imageDimensions']}',
        );
      }
    } catch (e) {
      debugPrint('[EditorService] ⚠️ 타겟 이미지 메타데이터 추출 실패: $e');
    }

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

    debugPrint('[EditorService] 📋 ImageRow 생성 - imageUrls: $imageUrls');
    debugPrint('[EditorService] 📋 ImageRow 생성 - mediaIds: $mediaIds');

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

    // 🎯 기존 이미지들의 메타데이터 병합 (공통 함수 사용)
    final mergedMetadata = _mergeImageMetadata([draggingMeta, targetMeta]);
    final mergedImageDimensions =
        mergedMetadata['imageDimensions'] as Map<String, dynamic>? ?? {};

    // 메타데이터 구성
    final metadata = <String, dynamic>{};
    if (imageCommentInfo.isNotEmpty) {
      metadata['imageCommentInfo'] = imageCommentInfo;
    }
    // 병합된 메타데이터 추가 (imageDimensions, uploadedUrls)
    metadata.addAll(mergedMetadata);

    debugPrint(
      '[EditorService] 📦 최종 메타데이터: imageCommentInfo=${imageCommentInfo.isNotEmpty}, imageDimensions=${mergedImageDimensions.isNotEmpty}',
    );

    // ImageRowNode 생성 (이미 3개 제한이 적용됨)
    final imageRowNode = ImageRowNode(
      id: 'imageRow_${DateTime.now().millisecondsSinceEpoch}',
      imageUrls: imageUrls,
      spacing: 8.0,
      metadata: metadata.isNotEmpty ? metadata : null,
    );

    debugPrint(
      '[EditorService] 🆕 생성된 ImageRowNode: id=${imageRowNode.id}, imageUrls=${imageRowNode.imageUrls.length}개, metadata keys=${imageRowNode.metadata.keys.toList()}',
    );

    // 🎯 이미지 병합 작업 중에는 히스토리 추적 일시 중단
    _isExecutingHistory = true;

    // ImageRowNode 삽입 (더 작은 인덱스 위치에)
    final insertIndex =
        draggingIndex < targetIndex ? draggingIndex : targetIndex;

    try {
      // 기존 이미지들 삭제
      document.deleteNode(draggingImageId);
      document.deleteNode(targetImageId);

      document.insertNodeAt(insertIndex, imageRowNode);
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint(
        '[EditorService] ✅ 이미지 병합 완료: insertIndex=$insertIndex, newNodeId=${imageRowNode.id}',
      );
      notifyListeners(); // 🎯 최종: 한 번만 호출
    }
  }

  void _addImageToRow(String imageId, String rowId, bool isFromLeft) {
    debugPrint(
      '[EditorService] ➕ Row에 이미지 추가 시작: imageId=$imageId, rowId=$rowId, isFromLeft=$isFromLeft',
    );

    final imageNode = document.getNodeById(imageId);
    final rowNode = document.getNodeById(rowId);

    if (imageNode == null || rowNode == null) {
      debugPrint(
        '[EditorService] ❌ Row에 이미지 추가 실패: 노드를 찾을 수 없음 (image: ${imageNode != null}, row: ${rowNode != null})',
      );
      return;
    }
    if (imageNode is! ImageNode || rowNode is! ImageRowNode) {
      debugPrint(
        '[EditorService] ❌ Row에 이미지 추가 실패: 타입 불일치 (image: ${imageNode.runtimeType}, row: ${rowNode.runtimeType})',
      );
      return;
    }

    debugPrint(
      '[EditorService] 📋 기존 Row 이미지 개수: ${rowNode.imageUrls.length}, 이미지 URL: ${rowNode.imageUrls}',
    );

    // ✅ Row에 추가 가능한 URL (네트워크 + 로컬)
    bool _isMergeableImageUrl(String u) {
      if (u.isEmpty) return false;
      return u.startsWith('http://') ||
          u.startsWith('https://') ||
          u.startsWith('file://') ||
          u.startsWith('/');
    }

    if (!_isMergeableImageUrl(imageNode.imageUrl)) {
      debugPrint(
        '[EditorService] ❌ Row 추가 스킵: URL이 병합 불가 (imageUrl=${imageNode.imageUrl})',
      );
      return;
    }

    // 이미 3개가 있으면 추가하지 않음
    if (rowNode.imageUrls.length >= 3) return;

    // 🎯 메타데이터 추출 (한 번만)
    final imageMeta = (imageNode as dynamic).metadata as Map<String, dynamic>?;
    final rowMeta = rowNode.metadata;

    // 🎯 추가되는 이미지의 mediaId 추출
    String? newImageMediaId;
    try {
      newImageMediaId = imageMeta?['mediaId']?.toString();
    } catch (_) {}

    // 🎯 기존 row의 imageCommentInfo 추출
    Map<String, Map<String, dynamic>> existingCommentInfo = {};
    try {
      final commentInfo = rowMeta['imageCommentInfo'] as Map<String, dynamic>?;
      if (commentInfo != null) {
        existingCommentInfo = commentInfo.map(
          (key, value) => MapEntry(key, (value as Map).cast<String, dynamic>()),
        );
      }
    } catch (_) {}

    // 🎯 메타데이터 병합 (공통 함수 사용)
    final mergedMetadata = _mergeImageMetadata([rowMeta, imageMeta]);
    final existingImageDimensions =
        mergedMetadata['imageDimensions'] as Map<String, dynamic>? ?? {};

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
      // 메타데이터 구성
      final metadata = <String, dynamic>{};
      if (newImageCommentInfo.isNotEmpty) {
        metadata['imageCommentInfo'] = newImageCommentInfo;
      }
      // 병합된 메타데이터 추가 (imageDimensions, uploadedUrls)
      metadata.addAll(mergedMetadata);

      debugPrint(
        '[EditorService] 📦 업데이트된 메타데이터: imageCommentInfo=${newImageCommentInfo.isNotEmpty}, imageDimensions=${existingImageDimensions.isNotEmpty}, uploadedUrls=${mergedMetadata['uploadedUrls'] != null}',
      );
      debugPrint(
        '[EditorService] 📋 새로운 이미지 URL 리스트: $newImageUrls (${newImageUrls.length}개)',
      );

      // ImageRowNode 업데이트 (이미 3개 제한이 적용됨)
      final updatedRowNode = rowNode.copyWith(
        imageUrls: newImageUrls,
        metadata: metadata.isNotEmpty ? metadata : null,
      );
      document.replaceNodeById(rowId, updatedRowNode);

      debugPrint(
        '[EditorService] ✅ Row 업데이트 완료: rowId=$rowId, imageUrls=${updatedRowNode.imageUrls.length}개, metadata keys=${updatedRowNode.metadata.keys.toList()}',
      );

      // 기존 이미지 삭제
      document.deleteNode(imageId);
      // 🎯 notifyListeners는 finally 이후에 한 번만
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] ✅ ImageRow에 이미지 추가 완료: rowId=$rowId');
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

      final String? align = _getPreviousParagraphAlign(insertIndex);
      final String paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';

      final ParagraphNode newParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: <String, dynamic>{if (align != null) 'textAlign': align},
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

  /// ✅ 문서가 "특수 노드"로 끝나면, 마지막에 trailing 빈 문단을 보장한다.
  /// - 드래프트 로드 후 "맨 밑 여백 탭 → 빈 문단 생성" UX가 막히는 것을 방지
  /// - 복구 작업으로 간주하여 히스토리/undo step에 포함하지 않는다.
  void ensureTrailingParagraphAfterLastSpecialNode() {
    _runRecoveryOperation(() {
      final doc = editor.document;
      if (doc.nodeCount == 0) return;

      final last = doc.getNodeAt(doc.nodeCount - 1);
      if (last == null) return;

      // 이미 문단으로 끝나면 추가 불필요
      if (last is ParagraphNode) return;

      // 특수 노드로 끝날 때만 trailing paragraph 추가
      final isSpecial =
          _isSpecialNode(last) ||
          (last is ParagraphNode && last.metadata['mention'] == true);
      if (!isSpecial) return;

      final paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
      final String? inheritedAlign = _getPreviousParagraphAlign(doc.nodeCount);
      final trailing = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: <String, dynamic>{
          if (inheritedAlign != null) 'textAlign': inheritedAlign,
        },
      );

      doc.insertNodeAt(doc.nodeCount, trailing);
      // selection/포커스는 사용자 탭으로 유도 (로드 직후 강제 포커스 방지)
    });
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

      // ✅ "첫 번째 노드=제목" 가정 제거:
      // 현재 커서가 있는 문단에 텍스트가 있으면 다음 줄에 삽입한다.
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

      if (insertIndex > doc.nodeCount) insertIndex = doc.nodeCount;

      // 이전 문단 정렬을 승계
      final String? inheritedAlign = _getPreviousParagraphAlign(insertIndex);

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
            if (inheritedAlign != null) 'textAlign': inheritedAlign,
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
        metadata: <String, dynamic>{
          if (inheritedAlign != null) 'textAlign': inheritedAlign,
        },
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

  /// ✅ 멘션 문단을 일반 문단으로 '강등'한다.
  /// - 범위 삭제(선택 핸들 백스페이스)처럼 TextDeletedEvent가 크게 들어오는 케이스에서
  ///   멘션 전용 삭제 로직(노드 삭제/selection 이동)이 re-entrancy를 일으켜 편집기가 먹통이 될 수 있어,
  ///   post-frame으로 안전하게 metadata만 제거한다.
  void _scheduleDemoteMentionNode(String nodeId) {
    if (_pendingMentionDemotions.contains(nodeId)) return;
    _pendingMentionDemotions.add(nodeId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingMentionDemotions.remove(nodeId);
      try {
        final node = document.getNodeById(nodeId);
        if (node is! ParagraphNode) return;
        if (node.metadata['mention'] != true) return;

        final dynamic rawAlign = node.metadata['textAlign'];
        final newMetadata = <String, dynamic>{
          if (rawAlign is String) 'textAlign': rawAlign,
        };

        // 멘션 노드는 보통 bold만 강제되어 있으므로, 강등 시에는 plain text로 정리한다.
        // (기존 attributions까지 유지하면 다시 멘션처럼 보일 수 있어 UX도 혼란)
        final newText = AttributedText(node.text.text);

        editor.execute([
          ReplaceNodeRequest(
            existingNodeId: nodeId,
            newNode: ParagraphNode(
              id: nodeId,
              text: newText,
              metadata: newMetadata,
            ),
          ),
        ]);
      } catch (e) {
        debugPrint('[EditorService] 멘션 강등 실패(무시): $e');
      }
    });
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

  /// 🎯 비디오 클립의 localPath 업데이트 (압축 완료 시점 등)
  /// - 업로드 URL은 그대로 두고, 로컬 재생 소스만 교체할 때 사용
  void updateVideoLocalPath(String nodeId, String localPath) {
    _isExecutingHistory = true;
    try {
      final node = document.getNodeById(nodeId);
      if (node is! ClipNode) return;

      final existingMetadata = Map<String, dynamic>.from(node.metadata);
      // padding 보장
      if (!existingMetadata.containsKey('padding')) {
        existingMetadata['padding'] = 'center';
      }
      // 원본 로컬 경로 보관 (디버그/추적용)
      if (node.localPath.isNotEmpty && node.localPath != localPath) {
        existingMetadata['originalLocalPath'] =
            existingMetadata['originalLocalPath'] ?? node.localPath;
      }

      final updated = ClipNode(
        id: node.id,
        label: node.label,
        colorHex: node.colorHex,
        url: node.url,
        localPath: localPath,
        thumbnailPath: node.thumbnailPath,
        metadata: existingMetadata,
      );

      editor.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: updated),
      ]);
    } catch (e) {
      debugPrint('[EditorService] updateVideoLocalPath error: $e');
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
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

  /// 🎯 이미지 메타데이터 병합 헬퍼 함수 (공통 로직)
  /// 여러 이미지의 imageDimensions와 uploadedUrls를 병합
  /// 반환: {imageDimensions: {...}, uploadedUrls: {...}}
  Map<String, dynamic> _mergeImageMetadata(
    List<Map<String, dynamic>?> metadataList,
  ) {
    final mergedDimensions = <String, dynamic>{};
    final mergedUploadedUrls = <String, dynamic>{};

    try {
      // 모든 메타데이터에서 imageDimensions와 uploadedUrls 병합
      for (final meta in metadataList) {
        if (meta == null) continue;

        final dimensions = meta['imageDimensions'] as Map<String, dynamic>?;
        if (dimensions != null) {
          mergedDimensions.addAll(dimensions);
        }

        final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
        if (uploadedUrls != null) {
          mergedUploadedUrls.addAll(uploadedUrls);
        }
      }

      // uploadedUrls의 값(네트워크 URL)에 대한 크기 정보도 매핑
      for (final meta in metadataList) {
        if (meta == null) continue;

        final dimensions = meta['imageDimensions'] as Map<String, dynamic>?;
        final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;

        if (dimensions != null && uploadedUrls != null) {
          for (final entry in uploadedUrls.entries) {
            final localPath = entry.key;
            final networkUrl = entry.value.toString();
            if (dimensions.containsKey(localPath) &&
                !mergedDimensions.containsKey(networkUrl)) {
              mergedDimensions[networkUrl] = dimensions[localPath];
            }
          }
        }
      }

      debugPrint(
        '[EditorService] ✅ 병합된 imageDimensions: ${mergedDimensions.keys.toList()}',
      );
      debugPrint(
        '[EditorService] ✅ 병합된 uploadedUrls: ${mergedUploadedUrls.keys.toList()}',
      );
    } catch (e) {
      debugPrint('[EditorService] ❌ imageMetadata 병합 실패: $e');
    }

    final result = <String, dynamic>{};
    if (mergedDimensions.isNotEmpty) {
      result['imageDimensions'] = mergedDimensions;
    }
    if (mergedUploadedUrls.isNotEmpty) {
      result['uploadedUrls'] = mergedUploadedUrls;
    }
    return result;
  }

  /// 🎯 특정 URL 목록에 해당하는 메타데이터만 필터링
  Map<String, dynamic> _filterMetadataForUrls(
    Map<String, dynamic>? sourceMetadata,
    List<String> targetUrls,
  ) {
    if (sourceMetadata == null) return {};

    final filtered = <String, dynamic>{};

    // imageDimensions 필터링
    final dimensions =
        sourceMetadata['imageDimensions'] as Map<String, dynamic>?;
    if (dimensions != null) {
      final filteredDimensions = <String, dynamic>{};
      for (final url in targetUrls) {
        if (dimensions.containsKey(url)) {
          filteredDimensions[url] = dimensions[url];
        }
      }
      if (filteredDimensions.isNotEmpty) {
        filtered['imageDimensions'] = filteredDimensions;
      }
    }

    // imageCommentInfo 필터링
    final commentInfo =
        sourceMetadata['imageCommentInfo'] as Map<String, dynamic>?;
    if (commentInfo != null) {
      final filteredCommentInfo = <String, dynamic>{};
      for (final url in targetUrls) {
        if (commentInfo.containsKey(url)) {
          filteredCommentInfo[url] = commentInfo[url];
        }
      }
      if (filteredCommentInfo.isNotEmpty) {
        filtered['imageCommentInfo'] = filteredCommentInfo;
      }
    }

    // uploadedUrls 필터링 (해당 URL과 관련된 것만)
    final uploadedUrls =
        sourceMetadata['uploadedUrls'] as Map<String, dynamic>?;
    if (uploadedUrls != null) {
      final filteredUploadedUrls = <String, dynamic>{};
      for (final entry in uploadedUrls.entries) {
        final networkUrl = entry.value.toString();
        if (targetUrls.contains(networkUrl) ||
            targetUrls.any(
              (url) =>
                  url.contains(entry.key) ||
                  entry.key.contains(url.split('/').last),
            )) {
          filteredUploadedUrls[entry.key] = entry.value;
        }
      }
      if (filteredUploadedUrls.isNotEmpty) {
        filtered['uploadedUrls'] = filteredUploadedUrls;
      }
    }

    return filtered;
  }

  /// 이미지 행에서 특정 이미지를 분리하고 분리된 이미지 ID 반환
  /// insertIndex가 주어지면 해당 위치에 바로 삽입한다. 주어지지 않으면 행의 위치(rowIndex)에 삽입.
  String? splitImageFromRow(String rowId, int imageIndex, {int? insertIndex}) {
    debugPrint(
      '[EditorService] ✂️ 이미지 분리 시작: rowId=$rowId, imageIndex=$imageIndex, insertIndex=$insertIndex',
    );

    final rowNode = document.getNodeById(rowId);
    if (rowNode == null || rowNode is! ImageRowNode) {
      debugPrint('[EditorService] ❌ 분리 실패: Row 노드를 찾을 수 없음');
      return null;
    }
    if (imageIndex < 0 || imageIndex >= rowNode.imageUrls.length) {
      debugPrint(
        '[EditorService] ❌ 분리 실패: 이미지 인덱스 범위 초과 (imageIndex=$imageIndex, rowLength=${rowNode.imageUrls.length})',
      );
      return null;
    }

    // 분리할 이미지 URL
    final imageUrl = rowNode.imageUrls[imageIndex];
    debugPrint('[EditorService] 📋 분리할 이미지 URL: $imageUrl');
    debugPrint('[EditorService] 📋 기존 Row 이미지: ${rowNode.imageUrls}');

    // 🎯 분리할 이미지의 메타데이터 추출 (공통 함수 사용)
    final rowMeta = rowNode.metadata;
    final splitImageMetadata = _filterMetadataForUrls(rowMeta, [imageUrl]);
    debugPrint(
      '[EditorService] 📦 분리할 이미지 메타데이터: keys=${splitImageMetadata.keys.toList()}',
    );

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
    final newImageNode = AppImageNode(
      id: newImageId,
      imageUrl: imageUrl,
      metadata: splitImageMetadata,
    );
    debugPrint(
      '[EditorService] 🆕 분리된 이미지 노드 생성: id=$newImageId, metadata=${splitImageMetadata.keys.toList()}',
    );

    // 이미지 행에서 해당 이미지 제거
    final remainingUrls = List<String>.from(rowNode.imageUrls);
    remainingUrls.removeAt(imageIndex);
    debugPrint(
      '[EditorService] 📋 분리 후 남은 이미지: $remainingUrls (${remainingUrls.length}개)',
    );

    // 🎯 이미지 분리 작업 중에는 히스토리 추적 일시 중단
    _isExecutingHistory = true;

    try {
      // 🎯 남은 이미지들의 메타데이터 필터링
      final remainingMetadata = _filterMetadataForUrls(rowMeta, remainingUrls);
      debugPrint(
        '[EditorService] 📦 남은 이미지 메타데이터: keys=${remainingMetadata.keys.toList()}',
      );

      if (remainingUrls.length == 1) {
        // 이미지가 1개만 남으면 단일 이미지로 변경
        final singleImageMetadata = _filterMetadataForUrls(rowMeta, [
          remainingUrls.first,
        ]);
        final singleImageNode = AppImageNode(
          id: rowId,
          imageUrl: remainingUrls.first,
          metadata: singleImageMetadata.isNotEmpty ? singleImageMetadata : null,
        );
        debugPrint(
          '[EditorService] 🔄 Row를 단일 이미지로 변환: rowId=$rowId, metadata keys=${singleImageMetadata.keys.toList()}',
        );

        // ✅ 중요: Replace + Insert를 개별 document mutation으로 하면 DocumentLayout이 중간 상태를 그리며
        // Row → Single 변환 순간에 "깜빡임"이 발생할 수 있다.
        // SuperEditor의 트랜잭션(editor.execute)으로 한 번에 배치 처리해서 중간 프레임을 줄인다.
        final int targetInsertIndex = insertIndex ?? rowIndex;
        editor.execute([
          ReplaceNodeRequest(existingNodeId: rowId, newNode: singleImageNode),
          InsertNodeAtIndexRequest(
            nodeIndex: targetInsertIndex,
            newNode: newImageNode,
          ),
        ]);
      } else if (remainingUrls.isEmpty) {
        // 이미지가 없으면 행 삭제
        document.deleteNode(rowId);
        debugPrint('[EditorService] 🗑️ 빈 Row 삭제: rowId=$rowId');
      } else {
        // 이미지 행 업데이트 (메타데이터도 함께 업데이트)
        final updatedRowNode = rowNode.copyWith(
          imageUrls: remainingUrls,
          metadata: remainingMetadata.isNotEmpty ? remainingMetadata : null,
        );
        debugPrint(
          '[EditorService] ✅ Row 업데이트: rowId=$rowId, imageUrls=${remainingUrls.length}개, metadata keys=${remainingMetadata.keys.toList()}',
        );

        final int targetInsertIndex = insertIndex ?? rowIndex;
        editor.execute([
          ReplaceNodeRequest(existingNodeId: rowId, newNode: updatedRowNode),
          InsertNodeAtIndexRequest(
            nodeIndex: targetInsertIndex,
            newNode: newImageNode,
          ),
        ]);
      }

      // ✅ remainingUrls.isEmpty인 케이스(삭제)만 기존 경로 유지: 여기서는 insert만 수행
      // (Delete를 editor.execute로 바꾸려면 Delete 요청 타입에 대한 안정성 확인이 필요)
      if (remainingUrls.isEmpty) {
        final int targetInsertIndex = insertIndex ?? rowIndex;
        document.insertNodeAt(targetInsertIndex, newImageNode);
      }

      debugPrint(
        '[EditorService] ✅ 이미지 분리 완료: newImageId=$newImageId, insertIndex=${insertIndex ?? rowIndex}',
      );
      return newImageId;
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
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
    Map<String, dynamic>? metadata,
  }) {
    final id = 'group_${DateTime.now().millisecondsSinceEpoch}';
    DocumentNode node;
    if (layout == GroupImageLayout.pageview) {
      node = PageViewImageNode(
        id: id,
        imageUrls: localPaths,
        metadata: metadata,
      );
    } else {
      node = ImageRowNode(id: id, imageUrls: localPaths, metadata: metadata);
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

    // ✅ "첫 번째 노드=제목" 가정 제거:
    // 현재 커서가 있는 문단에 텍스트가 있으면 다음 줄에 삽입한다.
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

    if (insertIndex > doc.nodeCount) insertIndex = doc.nodeCount;

    final bool insertingAtEnd = insertIndex == doc.nodeCount;

    final edits = <EditRequest>[
      InsertNodeAtIndexRequest(nodeIndex: insertIndex, newNode: componentNode),
    ];

    if (insertingAtEnd) {
      final String paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
      // 직전 문단의 정렬을 승계
      final String? inheritedAlign = _getPreviousParagraphAlign(insertIndex);
      final ParagraphNode trailingParagraph = ParagraphNode(
        id: paragraphId,
        text: AttributedText(''),
        metadata: <String, dynamic>{
          if (inheritedAlign != null) 'textAlign': inheritedAlign,
        },
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

    // ✅ 여러 노드 삽입(컴포넌트 + trailing 빈 문단)은 문서 변경 이벤트가 여러 번 발생할 수 있어
    // "빈 문단 추가" 같은 의미없는 undo step이 생길 수 있다.
    // 따라서 이 삽입은 원자적으로 처리하여 히스토리에 1번만 기록되도록 한다.
    _isExecutingHistory = true;
    try {
      editor.execute(edits);
    } finally {
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
    }
  }

  String? _getPreviousParagraphAlign(int beforeIndex) {
    for (int i = beforeIndex - 1; i >= 0; i--) {
      final node = editor.document.getNodeAt(i);
      if (node is ParagraphNode) {
        final String? align = node.metadata['textAlign'] as String?;
        if (align != null) return align;
      }
    }
    // ✅ 이전 문단이 없으면(textAlign 승계 불가) 메타데이터를 강제로 주입하지 않는다.
    // 기본 정렬은 stylesheet/렌더러 기본값에 맡긴다.
    return null;
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

    String? previousAlign;
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

    // ✅ 이전 문단이 없으면 첫 문단까지 강제로 center를 넣지 않는다.
    if (previousAlign == null) return;

    meta['textAlign'] = previousAlign;
    final replaced = ParagraphNode(
      id: node.id,
      text: node.text,
      metadata: meta,
    );
    _runRecoveryOperation(() {
      document.replaceNodeById(node.id, replaced);
    });
  }

  // 제목은 썸네일 편집 화면에서 입력하므로 제목 위치 유지 로직 제거됨

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
  final List<Sticker> stickers; // ✅ 스티커 스냅샷(드로잉 포함)
  final int version; // ✅ 변경 버전
  final DocumentSelection? selection; // 커서 위치
  final DocumentPosition? anchor; // ✅ 히스토리 UX용 스크롤 앵커(복원 시 이동)
  final int _cachedHashCode; // 🚀 캐시된 해시 (O(1) 비교용)

  _DocumentSnapshot({
    required this.nodes,
    required this.order,
    required this.stickers,
    required this.version,
    this.selection,
    this.anchor,
  }) : _cachedHashCode = _computeHash(nodes, order, stickers);

  // 🚀 해시 계산 (생성 시 한 번만)
  static int _computeHash(
    Map<String, DocumentNode> nodes,
    List<String> order,
    List<Sticker> stickers,
  ) {
    // ✅ 히스토리 동일성은 "문서 내용"으로만 판정해야 한다.
    // version(증분 카운터)에 의존하면 "내용은 같은데 버전만 다른" 스냅샷이 쌓여
    // 첫 Undo가 no-op처럼 보이는 문제가 생길 수 있다.

    int _stableValueHash(Object? v) {
      if (v == null) return 0;
      if (v is num || v is bool || v is String) return v.hashCode;
      if (v is DateTime) return v.millisecondsSinceEpoch.hashCode;
      if (v is Color) return v.value.hashCode;
      if (v is Uint8List) {
        // 너무 큰 바이트는 전부 해시하지 않고, 길이 + 앞부분 샘플로 안정성 확보
        final int sample = math.min(64, v.length);
        int h = Object.hash('u8', v.length);
        for (int i = 0; i < sample; i++) {
          h = Object.hash(h, v[i]);
        }
        return h;
      }
      if (v is List) {
        return Object.hashAll(v.map((e) => _stableValueHash(e)));
      }
      if (v is Map) {
        final keys =
            v.keys.toList()
              ..sort((a, b) => a.toString().compareTo(b.toString()));
        final parts = <int>[];
        for (final k in keys) {
          final ks = k.toString();
          parts.add(ks.hashCode);
          parts.add(_stableValueHash(v[k]));
        }
        return Object.hashAll(parts);
      }
      // Flutter/SuperEditor 객체 등은 런타임 타입 기반으로만 보수적으로 처리
      return v.runtimeType.toString().hashCode;
    }

    Map<String, dynamic>? _tryGetMetadata(DocumentNode node) {
      try {
        final dynamic meta = (node as dynamic).metadata;
        if (meta is Map<String, dynamic>) return meta;
        if (meta is Map) return meta.cast<String, dynamic>();
      } catch (_) {}
      return null;
    }

    int _attributedTextStableHash(AttributedText text) {
      // ⚠️ AttributedText.hashCode는 내부 구현/인스턴스에 의존할 수 있어
      // 스냅샷 간 "내용은 같은데 해시만 달라" 중복 히스토리가 쌓이는 원인이 될 수 있다.
      // 따라서 "문자열 + attribution span" 기반으로 안정 해시를 만든다.
      final s = text.text;
      if (s.isEmpty) return Object.hash('t', '');

      // 1) 전체 문자열
      int h = Object.hash('t', s);

      // 2) 존재하는 attribution들을 1회 스캔으로 수집
      final unique = <Attribution>{};
      for (int i = 0; i < s.length; i++) {
        unique.addAll(text.getAllAttributionsAt(i));
      }

      String _attrKey(Attribution a) {
        // NamedAttribution('spoiler') 같은 케이스
        try {
          final dynamic d = a;
          final dynamic name = d.name;
          if (name != null) return 'named:${name.toString()}';
        } catch (_) {}

        // ColorAttribution 계열(HighlightAttribution 등): 색상을 포함해야 한다.
        try {
          final dynamic d = a;
          final dynamic color = d.color;
          if (color is Color) {
            return '${a.id}:${color.value}';
          }
        } catch (_) {}

        // fallback: id + runtimeType
        return '${a.id}:${a.runtimeType}';
      }

      final attrs =
          unique.toList()..sort((a, b) => _attrKey(a).compareTo(_attrKey(b)));

      final fullRange = SpanRange(0, s.length - 1);
      for (final a in attrs) {
        h = Object.hash(h, _attrKey(a));
        final spans = text.getAttributionSpansInRange(
          attributionFilter: (attr) => attr == a,
          range: fullRange,
        );
        for (final span in spans) {
          h = Object.hash(h, span.start, span.end);
        }
      }

      return h;
    }

    int _nodeSignature(DocumentNode? node) {
      if (node == null) return 0;
      if (node is ParagraphNode) {
        // 텍스트 + attribution(형광펜/스포일러/볼드 등) + 주요 메타
        final meta = node.metadata;
        return Object.hash(
          'p',
          _attributedTextStableHash(node.text),
          meta['textAlign'],
          meta['isTitle'],
          meta['mention'],
          _stableValueHash(meta['usernames']),
          meta['fontFamily'],
        );
      }
      if (node is ImageNode) {
        // 이미지 URL(로컬/네트워크) + 메타(스포일러/패딩/업로드 맵 등)
        final meta = _tryGetMetadata(node);
        return Object.hash(
          'img',
          node.imageUrl,
          node.altText,
          _stableValueHash(meta),
        );
      }
      if (node is ImageRowNode) {
        final meta = _tryGetMetadata(node);
        return Object.hash(
          'row',
          Object.hashAll(node.imageUrls),
          node.spacing,
          _stableValueHash(meta),
        );
      }
      if (node is PageViewImageNode) {
        final meta = _tryGetMetadata(node);
        return Object.hash(
          'page',
          Object.hashAll(node.imageUrls),
          _stableValueHash(meta),
        );
      }
      if (node is LinkNode) {
        return Object.hash(
          'link',
          node.url,
          node.title,
          node.description,
          node.thumbnailUrl,
        );
      }
      if (node is ClipNode) {
        final meta = _tryGetMetadata(node);
        return Object.hash(
          'clip',
          node.url,
          node.localPath,
          node.thumbnailPath,
          node.label,
          node.colorHex,
          _stableValueHash(meta),
        );
      }
      // 기타 노드: 타입 + id 정도
      return Object.hash(node.runtimeType.toString(), node.id);
    }

    // ✅ 스냅샷은 생성 시점에 이미 전체 노드를 deep copy 한다.
    // 따라서 "전체 order + 전체 nodeSignature"로 해시를 만들어도 추가 비용이 크지 않으며,
    // 샘플링 기반 누락(특정 노드만 바뀐 케이스)을 줄여 히스토리 안정성이 올라간다.
    int h = Object.hash(order.length, order.isEmpty ? null : order.first);
    for (final id in order) {
      h = Object.hash(h, id, _nodeSignature(nodes[id]));
    }

    // ✅ 스티커도 히스토리 동일성 판정에 포함 (드로잉 추가/삭제 undo/redo 지원)
    h = Object.hash(h, 'stickers', stickers.length);
    for (final s in stickers) {
      h = Object.hash(
        h,
        s.id,
        s.type.index,
        s.position.dx,
        s.position.dy,
        s.scale,
        s.rotation,
        s.opacity,
        s.zIndex,
        s.locked,
        _stableValueHash(s.content),
      );
    }
    return h;
  }

  @override
  int get hashCode => _cachedHashCode;
}

/// DeleteContentRequest(범위 삭제)에서 특수노드가 누락되는 케이스를 보완하기 위한 커맨드.
///
/// - 기본 DeleteContentCommand를 먼저 실행하여 텍스트/일반 노드를 삭제한다.
/// - 그 다음, "보라색 범위 선택에 포함된" 특수노드 중 남아있는 것들을 DeleteNodeCommand로 삭제한다.
/// - 특수노드는 레지스트리 복원과 충돌하지 않도록 삭제 전에 `explicitlyDeleted`로 표시한다.
class _DeleteContentAndSpecialNodesCommand extends EditCommand {
  _DeleteContentAndSpecialNodesCommand({
    required this.documentRange,
    required this.selectionForCaretCalculation,
    required this.coveredSpecialNodeIds,
    required this.saveHistoryBeforeDelete,
    required this.beginSuppressRestoration,
    required this.endSuppressRestoration,
    required this.beginSuppressHistoryTracking,
    required this.endSuppressHistoryTracking,
    required this.finalizeBatchDeleteHistory,
    required this.ensureParagraphAlignmentForNodeId,
    required this.markSpecialNodeExplicitlyDeleted,
  });

  final DocumentRange documentRange;
  final DocumentSelection selectionForCaretCalculation;
  final Set<String> coveredSpecialNodeIds;
  final VoidCallback saveHistoryBeforeDelete;
  final VoidCallback beginSuppressRestoration;
  final VoidCallback endSuppressRestoration;
  final VoidCallback beginSuppressHistoryTracking;
  final VoidCallback endSuppressHistoryTracking;
  final VoidCallback finalizeBatchDeleteHistory;
  final void Function(String nodeId) ensureParagraphAlignmentForNodeId;
  final void Function(String nodeId) markSpecialNodeExplicitlyDeleted;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final doc = context.document;
    assert(() {
      debugPrint(
        '[EditorService] 🧹 DeleteContent+SpecialNodes: range=$documentRange, coveredSpecialNodeIds=$coveredSpecialNodeIds',
      );
      return true;
    }());

    beginSuppressRestoration();
    beginSuppressHistoryTracking();
    try {
      // 🎯 삭제 전 상태 저장 (EditorService 커스텀 undo 안정화)
      saveHistoryBeforeDelete();

      // 🎯 삭제 후 caret 위치 계산 (SuperEditor 기본 UX와 정렬)
      final caretAfterDeletion =
          CommonEditorOperations.getDocumentPositionAfterExpandedDeletion(
            document: doc,
            selection: selectionForCaretCalculation,
          );

      // 🎯 DeleteContentCommand로 삭제될 수 있는(=deletable) 특수노드는 미리 명시적 삭제 표시
      // (NodeRemovedEvent에서 복원 로직이 먼저 실행되는 걸 방지)
      for (final id in coveredSpecialNodeIds) {
        final node = doc.getNodeById(id);
        if (node != null && node.isDeletable) {
          markSpecialNodeExplicitlyDeleted(id);
        }
      }

      // 1) 기본 범위 삭제 (가능한 deletable 노드/텍스트 먼저)
      final nodesInRange = doc.getNodesInside(
        documentRange.start,
        documentRange.end,
      );
      final hasAnyDeletable = nodesInRange.any((n) => n.isDeletable);
      if (hasAnyDeletable) {
        executor.executeCommand(
          DeleteContentCommand(documentRange: documentRange),
        );
      }

      // 2) 기본 삭제에서 누락된 특수노드 보완 삭제
      for (final id in coveredSpecialNodeIds) {
        final stillExists = doc.getNodeById(id) != null;
        if (!stillExists) continue;
        markSpecialNodeExplicitlyDeleted(id);
        executor.executeCommand(DeleteNodeCommand(nodeId: id));
      }

      // 3) selection 정리
      if (caretAfterDeletion != null) {
        executor.executeCommand(
          ChangeSelectionCommand(
            DocumentSelection.collapsed(position: caretAfterDeletion),
            SelectionChangeType.deleteContent,
            SelectionReason.userInteraction,
          ),
        );

        // ✅ 삭제 직후 커서가 앉는 문단의 정렬 메타데이터가 비어있으면 즉시 보정
        // (입력 1글자 후에야 정렬이 "원래대로" 돌아오는 현상 방지)
        ensureParagraphAlignmentForNodeId(caretAfterDeletion.nodeId);
      } else {
        executor.executeCommand(
          const ChangeSelectionCommand(
            null,
            SelectionChangeType.clearSelection,
            SelectionReason.contentChange,
          ),
        );
      }
    } finally {
      finalizeBatchDeleteHistory();
      endSuppressHistoryTracking();
      endSuppressRestoration();
    }
  }
}

/// DeleteSelectionRequest(IME/선택 핸들 백스페이스)에서 특수노드가 누락되는 케이스를 보완.
///
/// - 기본 DeleteSelectionCommand를 먼저 실행해서 SuperEditor의 일반 삭제/affinity 정책을 유지한다.
/// - 그 다음, "보라색 범위 선택에 포함된" 특수노드 중 남아있는 것들을 DeleteNodeCommand로 삭제한다.
/// - 특수노드는 레지스트리 복원과 충돌하지 않도록 삭제 전에 `explicitlyDeleted`로 표시한다.
class _DeleteSelectionAndSpecialNodesCommand extends EditCommand {
  _DeleteSelectionAndSpecialNodesCommand({
    required this.affinity,
    required this.selectionForDeletion,
    required this.coveredSpecialNodeIds,
    required this.saveHistoryBeforeDelete,
    required this.beginSuppressRestoration,
    required this.endSuppressRestoration,
    required this.beginSuppressHistoryTracking,
    required this.endSuppressHistoryTracking,
    required this.finalizeBatchDeleteHistory,
    required this.ensureParagraphAlignmentForNodeId,
    required this.markSpecialNodeExplicitlyDeleted,
  });

  final TextAffinity affinity;
  final DocumentSelection selectionForDeletion;
  final Set<String> coveredSpecialNodeIds;
  final VoidCallback saveHistoryBeforeDelete;
  final VoidCallback beginSuppressRestoration;
  final VoidCallback endSuppressRestoration;
  final VoidCallback beginSuppressHistoryTracking;
  final VoidCallback endSuppressHistoryTracking;
  final VoidCallback finalizeBatchDeleteHistory;
  final void Function(String nodeId) ensureParagraphAlignmentForNodeId;
  final void Function(String nodeId) markSpecialNodeExplicitlyDeleted;

  DocumentPosition? _pickSafeCaretBeforeDeletion(
    Document doc, {
    required DocumentSelection selection,
    required Set<String> coveredSpecialNodeIds,
    required DocumentPosition? caretAfterDeletion,
  }) {
    // 1) caretAfterDeletion이 이미 계산되어 있고, 그 node가 삭제 대상이 아니면 최우선
    if (caretAfterDeletion != null) {
      final n = doc.getNodeById(caretAfterDeletion.nodeId);
      if (n != null &&
          !coveredSpecialNodeIds.contains(caretAfterDeletion.nodeId)) {
        return caretAfterDeletion;
      }
    }

    // 2) extent가 텍스트 노드 쪽이라면(대부분의 케이스), extent로 collapse (삭제 range는 별도로 유지)
    final extentNode = doc.getNodeById(selection.extent.nodeId);
    if (extentNode != null &&
        !coveredSpecialNodeIds.contains(selection.extent.nodeId)) {
      return selection.extent;
    }

    // 3) base가 삭제 대상이 아니면 base
    final baseNode = doc.getNodeById(selection.base.nodeId);
    if (baseNode != null &&
        !coveredSpecialNodeIds.contains(selection.base.nodeId)) {
      return selection.base;
    }

    return null;
  }

  // DeleteSelectionRequest는 affinity 방향(아래→위 vs 위→아래)에 따라 내부 로직이 달라지고,
  // 특수 노드(start 경계 포함) 케이스에서 DeleteSelectionCommand가 null-assertion 크래시를 내는 경우가 있어
  // selection을 DocumentRange로 정규화하여 DeleteContentCommand 경로로 통일한다.
  DocumentRange _documentRangeFromSelection(
    Document doc,
    DocumentSelection selection,
  ) {
    final baseIndex = doc.getNodeIndexById(selection.base.nodeId);
    final extentIndex = doc.getNodeIndexById(selection.extent.nodeId);

    // 인덱스를 못 찾으면 보수적으로 base..extent로 둔다.
    if (baseIndex == -1 || extentIndex == -1) {
      return DocumentRange(start: selection.base, end: selection.extent);
    }

    if (baseIndex < extentIndex) {
      return DocumentRange(start: selection.base, end: selection.extent);
    }
    if (baseIndex > extentIndex) {
      return DocumentRange(start: selection.extent, end: selection.base);
    }

    // 같은 노드 내에서는 nodePosition의 선후를 비교
    final bp = selection.base.nodePosition;
    final ep = selection.extent.nodePosition;

    int comparePositions(Object a, Object b) {
      // 특수 노드(Upstream/Downstream)
      if (a is UpstreamDownstreamNodePosition &&
          b is UpstreamDownstreamNodePosition) {
        final aUp = a == const UpstreamDownstreamNodePosition.upstream();
        final bUp = b == const UpstreamDownstreamNodePosition.upstream();
        if (aUp == bUp) return 0;
        return aUp ? -1 : 1;
      }

      // 텍스트 노드(TextPosition)
      if (a is TextPosition && b is TextPosition) {
        if (a.offset != b.offset) return a.offset < b.offset ? -1 : 1;
        if (a.affinity == b.affinity) return 0;
        return a.affinity == TextAffinity.upstream ? -1 : 1;
      }

      // 혼합 타입: upstream/downstream은 "노드 경계"로 보고,
      // upstream < (텍스트) < downstream 순으로 정렬한다.
      int rank(Object p) {
        if (p is UpstreamDownstreamNodePosition) {
          return p == const UpstreamDownstreamNodePosition.upstream() ? 0 : 2;
        }
        if (p is TextPosition) return 1;
        return 1;
      }

      final ra = rank(a);
      final rb = rank(b);
      if (ra == rb) return 0;
      return ra < rb ? -1 : 1;
    }

    final cmp = comparePositions(bp, ep);
    if (cmp <= 0) {
      return DocumentRange(start: selection.base, end: selection.extent);
    }
    return DocumentRange(start: selection.extent, end: selection.base);
  }

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final doc = context.document;
    assert(() {
      debugPrint(
        '[EditorService] 🧹 DeleteSelection+SpecialNodes: affinity=$affinity, selection=$selectionForDeletion, coveredSpecialNodeIds=$coveredSpecialNodeIds',
      );
      return true;
    }());

    beginSuppressRestoration();
    beginSuppressHistoryTracking();
    try {
      // 🎯 삭제 전 상태 저장 (EditorService 커스텀 undo 안정화)
      saveHistoryBeforeDelete();

      // 🎯 삭제 후 caret 위치 계산 (SuperEditor 기본 UX와 정렬)
      final caretAfterDeletion =
          CommonEditorOperations.getDocumentPositionAfterExpandedDeletion(
            document: doc,
            selection: selectionForDeletion,
          );

      // ✅ iOS IME/컨트롤 레이어가 "삭제된 노드를 가리키는 selection"을 직렬화/레이아웃하는 순간
      // super_editor 내부에서 null-assertion 크래시가 발생할 수 있다.
      // 따라서 실제 삭제 전에 selection을 안전한 위치로 먼저 collapse/clear 한다.
      final safeCaretBeforeDeletion = _pickSafeCaretBeforeDeletion(
        doc,
        selection: selectionForDeletion,
        coveredSpecialNodeIds: coveredSpecialNodeIds,
        caretAfterDeletion: caretAfterDeletion,
      );
      if (safeCaretBeforeDeletion != null) {
        executor.executeCommand(
          ChangeSelectionCommand(
            DocumentSelection.collapsed(position: safeCaretBeforeDeletion),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        );
      } else {
        executor.executeCommand(
          const ChangeSelectionCommand(
            null,
            SelectionChangeType.clearSelection,
            SelectionReason.userInteraction,
          ),
        );
      }

      // 🎯 DeleteContentCommand로 삭제될 수 있는(=deletable) 특수노드는 미리 명시적 삭제 표시
      // (NodeRemovedEvent에서 복원 로직이 먼저 실행되는 걸 방지)
      for (final id in coveredSpecialNodeIds) {
        final node = doc.getNodeById(id);
        if (node != null && node.isDeletable) {
          markSpecialNodeExplicitlyDeleted(id);
        }
      }

      // 1) selection을 DocumentRange로 정규화한 뒤 기본 범위 삭제
      // (DeleteSelectionCommand 경로에서 발생하는 null-assertion 크래시 회피)
      final range = _documentRangeFromSelection(doc, selectionForDeletion);
      final nodesInRange = doc.getNodesInside(range.start, range.end);
      final hasAnyDeletable = nodesInRange.any((n) => n.isDeletable);
      if (hasAnyDeletable) {
        executor.executeCommand(DeleteContentCommand(documentRange: range));
      }

      // 2) 기본 삭제에서 누락된 특수노드 보완 삭제
      for (final id in coveredSpecialNodeIds) {
        final stillExists = doc.getNodeById(id) != null;
        if (!stillExists) continue;
        markSpecialNodeExplicitlyDeleted(id);
        executor.executeCommand(DeleteNodeCommand(nodeId: id));
      }

      // 3) selection 정리
      if (caretAfterDeletion != null) {
        executor.executeCommand(
          ChangeSelectionCommand(
            DocumentSelection.collapsed(position: caretAfterDeletion),
            SelectionChangeType.deleteContent,
            SelectionReason.userInteraction,
          ),
        );
        ensureParagraphAlignmentForNodeId(caretAfterDeletion.nodeId);
      } else {
        executor.executeCommand(
          const ChangeSelectionCommand(
            null,
            SelectionChangeType.clearSelection,
            SelectionReason.contentChange,
          ),
        );
      }
    } finally {
      finalizeBatchDeleteHistory();
      endSuppressHistoryTracking();
      endSuppressRestoration();
    }
  }
}

/// caret이 문단 시작일 때 Backspace로 바로 이전 DividerNode를 삭제한다.
class _DeletePreviousDividerOnBackspaceCommand extends EditCommand {
  _DeletePreviousDividerOnBackspaceCommand({
    required this.dividerNodeId,
    required this.caretNodeId,
    required this.saveHistoryBeforeDelete,
  });

  final String dividerNodeId;
  final String caretNodeId;
  final VoidCallback saveHistoryBeforeDelete;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final doc = context.document;
    if (doc.getNodeById(dividerNodeId) == null) return;
    if (doc.getNodeById(caretNodeId) == null) return;

    // 삭제 전 스냅샷 저장 (커스텀 undo 안정화)
    saveHistoryBeforeDelete();

    // caret은 현재 문단 시작에 그대로 유지
    executor.executeCommand(
      ChangeSelectionCommand(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: caretNodeId,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    );

    executor.executeCommand(DeleteNodeCommand(nodeId: dividerNodeId));
  }
}
