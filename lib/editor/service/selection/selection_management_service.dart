import 'dart:async';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

/// 🎯 Selection 관리 전담 서비스
/// - selection 변경 감지
/// - 특수 노드 선택/하이라이트
/// - 범위 선택 추적
class SelectionManagementService {
  final Editor editor;
  final MutableDocument document;
  final BuildContext? context;
  final Function(DocumentNode) isSpecialNode;
  final Function(DocumentNode, DocumentNode) hasNodeChanged;
  final Function(DocumentNode) copyNode;

  // 🎯 마지막 유효 selection 캐시
  DocumentSelection? _lastSelection;
  DocumentSelection? get lastSelection => _lastSelection;

  // 🎯 범위 선택으로 하이라이트된 노드들을 추적
  Set<String> _pendingHighlightedNodeIds = <String>{};
  Set<String> get pendingHighlightedNodeIds => _pendingHighlightedNodeIds;

  // 🎯 이전 selection이 범위 선택이었는지 추적
  bool _wasRangeSelection = false;

  // 🎯 단순 셀렉션 해제 감지용 타이머
  Timer? _selectionClearTimer;

  SelectionManagementService({
    required this.editor,
    required this.document,
    required this.context,
    required this.isSpecialNode,
    required this.hasNodeChanged,
    required this.copyNode,
  });

  void dispose() {
    _selectionClearTimer?.cancel();
  }

  /// 🎯 Selection 변경 핸들러
  void handleSelectionChanged() {
    final sel = editor.composer.selectionNotifier.value;

    // 🎯 케이스 0: selection이 삭제된 노드를 가리키는지 먼저 확인
    if (sel != null) {
      if (!_validateSelection(sel)) {
        return; // 삭제된 노드를 가리키면 나머지 로직 스킵
      }
    }

    // 🎯 케이스 1: 선택 완전 해제
    if (sel == null) {
      _handleSelectionCleared();
      return;
    }

    // 🎯 케이스 2: 범위 선택 (드래그)
    if (!sel.isCollapsed) {
      _handleRangeSelection(sel);
      return;
    }

    // 🎯 케이스 3: collapsed 선택으로 변경 (범위 선택 해제)
    if (_wasRangeSelection) {
      _handleRangeSelectionCollapsed();
    }

    // 🎯 여기부터는 collapsed 선택만 도달 (백스페이스 보정 로직)
    _lastSelection = sel;
    _handleCollapsedSelection(sel);
  }

  /// Selection이 삭제된 노드를 가리키는지 확인하고 안전한 위치로 이동
  bool _validateSelection(DocumentSelection sel) {
    try {
      final nodeId = sel.extent.nodeId;
      final node = document.getNodeById(nodeId);
      if (node == null) {
        _moveToSafePosition();
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[SelectionService] ⚠️ selection 노드 확인 실패: $e');
      return true; // 에러 발생 시에도 계속 진행
    }
  }

  /// 안전한 위치로 커서 이동
  void _moveToSafePosition() {
    DocumentPosition? safePosition;
    for (int i = 0; i < document.nodeCount; i++) {
      final candidateNode = document.getNodeAt(i);
      if (candidateNode is ParagraphNode &&
          candidateNode.metadata['isTitle'] != true) {
        final text = candidateNode.text.text;
        safePosition = DocumentPosition(
          nodeId: candidateNode.id,
          nodePosition: TextNodePosition(
            offset: text.length.clamp(0, text.length),
          ),
        );
        break;
      }
    }

    if (safePosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          editor.composer.setSelectionWithReason(
            DocumentSelection.collapsed(position: safePosition!),
            SelectionReason.userInteraction,
          );
          debugPrint('[SelectionService] ✅ 안전한 위치로 이동');
        } catch (e) {
          debugPrint('[SelectionService] ⚠️ selection 이동 실패: $e');
          try {
            editor.composer.clearSelection();
          } catch (_) {}
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          editor.composer.clearSelection();
        } catch (_) {}
      });
    }
  }

  /// Selection 해제 처리
  void _handleSelectionCleared() {
    _pendingHighlightedNodeIds.clear();
    if (context != null) {
      try {
        final nodeService = context!.read<NodeComponentService>();
        if (nodeService.selectedNodeId != null) {
          nodeService.clearSelectionSilently();
          nodeService.clearHighlightedSelectionSilently();
          debugPrint('[SelectionService] Selection null → 특수 노드 선택 해제');
        }
      } catch (e) {
        // NodeComponentService가 없을 수 있음 (무시)
      }
    }
  }

  /// 범위 선택 처리
  void _handleRangeSelection(DocumentSelection sel) {
    _wasRangeSelection = true;

    if (context == null) return;

    try {
      final nodeService = context!.read<NodeComponentService>();

      // 선택 해제
      if (nodeService.selectedNodeId != null) {
        nodeService.clearSelectionSilently();
      }

      // 하이라이트 설정
      _highlightNodesInRange(sel, nodeService);
    } catch (e) {
      debugPrint('[SelectionService] ⚠️ 범위 선택 하이라이트 실패: $e');
    }
  }

  /// 범위 내 특수 노드들을 하이라이트
  void _highlightNodesInRange(
    DocumentSelection sel,
    NodeComponentService nodeService,
  ) {
    final baseIndex = document.getNodeIndexById(sel.base.nodeId);
    final extentIndex = document.getNodeIndexById(sel.extent.nodeId);

    if (baseIndex == -1 || extentIndex == -1) {
      _pendingHighlightedNodeIds.clear();
      nodeService.clearHighlightedSelection();
      return;
    }

    final startIndex = baseIndex < extentIndex ? baseIndex : extentIndex;
    final endIndex = baseIndex < extentIndex ? extentIndex : baseIndex;

    final highlightedIds = <String>{};

    debugPrint(
      '[SelectionService] 🔍 범위 선택: base=$baseIndex, extent=$extentIndex, start=$startIndex, end=$endIndex',
    );

    // 최적화: 범위가 작을 때만 순회
    // 범위 내 특수 노드 검색
    for (int i = startIndex; i <= endIndex; i++) {
      final node = document.getNodeAt(i);
      if (node != null && isSpecialNode(node)) {
        highlightedIds.add(node.id);
        debugPrint('[SelectionService] ✅ 특수 노드 발견: ${node.id} (인덱스: $i)');
      }
    }

    _pendingHighlightedNodeIds = highlightedIds;
    nodeService.setHighlightedSelection(highlightedIds);

    if (highlightedIds.isNotEmpty) {
      debugPrint('[SelectionService] ✅ 하이라이트: ${highlightedIds.length}개');
    }
  }

  /// 범위 선택이 collapsed로 변경됨
  void _handleRangeSelectionCollapsed() {
    _wasRangeSelection = false;
    _selectionClearTimer?.cancel();

    if (context == null) {
      _pendingHighlightedNodeIds.clear();
      return;
    }

    try {
      final nodeService = context!.read<NodeComponentService>();
      final currentHighlightedIds = nodeService.selectionHighlightedIds;

      if (currentHighlightedIds.isNotEmpty) {
        final validHighlightedIds = <String>{};
        for (final nodeId in currentHighlightedIds) {
          if (document.getNodeById(nodeId) != null) {
            validHighlightedIds.add(nodeId);
          }
        }

        if (validHighlightedIds.isNotEmpty) {
          _pendingHighlightedNodeIds = validHighlightedIds;
          debugPrint(
            '[SelectionService] ✅ 범위 선택 해제: ${_pendingHighlightedNodeIds.length}개 저장',
          );
        } else {
          _pendingHighlightedNodeIds.clear();
          nodeService.clearHighlightedSelection();
        }
      }
    } catch (e) {
      debugPrint('[SelectionService] ⚠️ 범위 선택 해제 처리 실패: $e');
    }
  }

  /// Collapsed selection 처리 (특수 노드 레지스트리 등록)
  void _handleCollapsedSelection(DocumentSelection sel) {
    try {
      final nodeId = sel.extent.nodeId;
      final node = document.getNodeById(nodeId);

      if (node == null) {
        debugPrint('[SelectionService] ⚠️ 노드 없음: $nodeId');
        _moveToSafePosition();
        return;
      }

      if (isSpecialNode(node)) {
        _handleSpecialNodeSelection(node, sel);
      } else {
        _clearSpecialNodeSelection();
      }
    } catch (e) {
      // 에러 무시
    }
  }

  /// 특수 노드 선택 처리
  void _handleSpecialNodeSelection(DocumentNode node, DocumentSelection sel) {
    final nodeIndex = document.getNodeIndexById(node.id);
    final position = sel.extent.nodePosition;
    final isAtDownstream =
        position is UpstreamDownstreamNodePosition &&
        position == const UpstreamDownstreamNodePosition.downstream();
    final isAtUpstream =
        position is UpstreamDownstreamNodePosition &&
        position == const UpstreamDownstreamNodePosition.upstream();

    // 레지스트리 제거됨

    debugPrint(
      '[SelectionService] 특수 노드 등록: ${node.id}, downstream=$isAtDownstream',
    );

    // NodeComponentService 선택 설정
    if (context != null && (isAtDownstream || isAtUpstream)) {
      _setNodeComponentSelection(
        node.id,
        nodeIndex,
        isAtDownstream,
        isAtUpstream,
        sel,
      );
    }
  }

  /// NodeComponentService에 선택 설정
  void _setNodeComponentSelection(
    String nodeId,
    int nodeIndex,
    bool isAtDownstream,
    bool isAtUpstream,
    DocumentSelection sel,
  ) {
    try {
      final nodeService = context!.read<NodeComponentService>();

      if (nodeService.selectedImageId != nodeId) {
        nodeService.selectNode(nodeId);
        debugPrint('[SelectionService] 노드 선택: $nodeId');
      }
    } catch (e) {
      debugPrint('[SelectionService] NodeComponentService 접근 실패: $e');
    }
  }

  /// 이전 특수 노드 등록

  /// 특수 노드 선택 해제
  void _clearSpecialNodeSelection() {
    if (context != null) {
      try {
        final nodeService = context!.read<NodeComponentService>();
        if (nodeService.selectedImageId != null) {
          nodeService.selectNode(null);
          debugPrint('[SelectionService] 일반 노드로 이동, 선택 해제');
        }
      } catch (e) {
        // NodeComponentService가 없을 수 있음
      }
    }
  }

  /// 🎯 하이라이트된 노드 ID 클리어
  void clearPendingHighlightedNodeIds() {
    _pendingHighlightedNodeIds.clear();
  }
}
