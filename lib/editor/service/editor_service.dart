import 'dart:async';
import 'dart:convert';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/divider_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/post_reader_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

class EditorService extends ChangeNotifier {
  late final Editor editor;
  late final MutableDocument document;
  GlobalKey? _documentLayoutKey;
  // 마지막 유효 selection 캐시 (포커스가 잠시 사라져도 사용)
  DocumentSelection? _lastSelection;

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

  // 🎯 NodeComponentService 참조 (노드 선택 해제용)
  BuildContext? _context;

  EditorService({
    required this.editor,
    required this.document,
    BuildContext? context,
  }) : _context = context {
    document.addListener(_onDocumentChanged);
    editor.composer.selectionNotifier.addListener(_onSelectionChanged);

    // 초기 상태 저장 (여러 프레임 후 실행하여 UI 블로킹 방지)
    // 🎯 사용자가 실제로 편집을 시작할 때까지 충분히 지연
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 첫 프레임 후 추가 지연 (UI 렌더링 완료 보장)
      // 🎯 더 긴 지연으로 UI 완전히 안정화 후 실행
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (!_initialStateSaved) {
          _saveInitialState();
        }
      });
    });
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

  // 🎯 모든 노드를 비동기로 deep copy (초기 상태 저장용, UI 블로킹 방지)
  Future<_DocumentSnapshot> _copyAllNodesAsync() async {
    final nodes = <String, DocumentNode>{};
    final order = <String>[];

    for (int i = 0; i < document.nodeCount; i++) {
      final node = document.getNodeAt(i);
      if (node != null) {
        // 🎯 빈 문단은 저장하지 않음 (제목 제외)
        if (node is ParagraphNode) {
          final isTitle = node.metadata['isTitle'] == true;
          final isEmpty = node.text.text.trim().isEmpty;

          // 제목이 아니고 비어있으면 스킵
          if (!isTitle && isEmpty) {
            continue;
          }
        }

        // 🎯 플레이스홀더(업로드 중)는 저장하지 않음
        if (node is ImageNode) {
          final isPlaceholder = node.metadata['isPlaceholder'] == true;
          if (isPlaceholder) {
            continue;
          }
        }

        if (node is ClipNode) {
          final isPlaceholder = node.url.isEmpty && node.localPath.isNotEmpty;
          if (isPlaceholder) {
            continue;
          }
        }

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
      if (node != null) {
        // 🎯 빈 문단은 저장하지 않음 (제목 제외)
        if (node is ParagraphNode) {
          final isTitle = node.metadata['isTitle'] == true;
          final isEmpty = node.text.text.trim().isEmpty;

          // 제목이 아니고 비어있으면 스킵
          if (!isTitle && isEmpty) {
            continue;
          }
        }

        // 🎯 플레이스홀더(업로드 중)는 저장하지 않음
        if (node is ImageNode) {
          final isPlaceholder = node.metadata['isPlaceholder'] == true;
          if (isPlaceholder) {
            continue;
          }
        }

        if (node is ClipNode) {
          final isPlaceholder = node.url.isEmpty && node.localPath.isNotEmpty;
          if (isPlaceholder) {
            continue;
          }
        }

        // 🎯 노드 복사를 microtask로 분산하여 UI 블로킹 방지
        await Future.microtask(() {
          nodes[node.id] = _copyNode(node);
          order.add(node.id);
        });

        // 🎯 각 노드 복사 후 짧은 지연 (UI 업데이트 기회 제공, Hang 방지)
        // 즉시 저장은 빠르게 처리하되 UI 블로킹은 방지
        if (i < document.nodeCount - 1) {
          // 5개마다 한 번씩만 지연 (더 빠른 처리)
          if (i % 5 == 0) {
            await Future.delayed(const Duration(milliseconds: 8));
          }
        }
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

        _undoStack.add(snapshot);
        _redoStack.clear();

        // 최대 30개까지만 유지
        if (_undoStack.length > 30) {
          _undoStack.removeAt(0);
        }

        debugPrint(
          '[EditorService] 📸 즉시 저장 (total: ${_undoStack.length}, nodes: ${snapshot.nodes.length})',
        );

        // 🎯 Undo/Redo 버튼 상태 업데이트
        notifyListeners();
      });
    } else {
      // 디바운싱 (텍스트 입력)
      _historyTimer?.cancel();
      _historyTimer = Timer(Duration(seconds: 1), () {
        final snapshot = _copyAllNodes();

        // 중복 방지
        if (_undoStack.isNotEmpty &&
            _areSnapshotsEqual(_undoStack.last, snapshot)) {
          return;
        }

        _undoStack.add(snapshot);
        _redoStack.clear();

        // 최대 30개까지만 유지
        if (_undoStack.length > 30) {
          _undoStack.removeAt(0);
        }

        debugPrint('[EditorService] 📸 디바운싱 저장 (total: ${_undoStack.length})');

        // 🎯 Undo/Redo 버튼 상태 업데이트
        notifyListeners();
      });
    }
  }

  // 🎯 스냅샷 비교
  bool _areSnapshotsEqual(_DocumentSnapshot a, _DocumentSnapshot b) {
    if (a.order.length != b.order.length) return false;
    if (a.order.join(',') != b.order.join(',')) return false;

    for (final id in a.nodes.keys) {
      if (!b.nodes.containsKey(id)) return false;
      final nodeA = a.nodes[id];
      final nodeB = b.nodes[id];
      if (nodeA is ParagraphNode && nodeB is ParagraphNode) {
        if (nodeA.text.text != nodeB.text.text) return false;
      }
    }

    return true;
  }

  // 🎯 ChangeLog에서 변경 추적
  void _trackChangeFromLog(DocumentChange change) {
    if (_isExecutingHistory) return;

    try {
      // TextInsertionEvent, TextDeletedEvent - 디바운싱 적용
      if (change is TextInsertionEvent || change is TextDeletedEvent) {
        _saveCurrentState(immediate: false); // 500ms 디바운싱
        return;
      }

      // 🎯 NodeInsertedEvent (엔터), NodeRemoved, NodeChanged - 즉시 저장!
      if (change is NodeInsertedEvent ||
          change is NodeRemovedEvent ||
          change is NodeChangeEvent) {
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
      if (node != null) {
        // 🎯 빈 문단은 저장하지 않음 (제목 제외)
        if (node is ParagraphNode) {
          final isTitle = node.metadata['isTitle'] == true;
          final isEmpty = node.text.text.trim().isEmpty;

          // 제목이 아니고 비어있으면 스킵
          if (!isTitle && isEmpty) {
            continue;
          }
        }

        // 🎯 플레이스홀더(업로드 중)는 저장하지 않음
        if (node is ImageNode) {
          final isPlaceholder = node.metadata['isPlaceholder'] == true;
          if (isPlaceholder) {
            continue;
          }
        }

        if (node is ClipNode) {
          final isPlaceholder = node.url.isEmpty && node.localPath.isNotEmpty;
          if (isPlaceholder) {
            continue;
          }
        }

        nodes[node.id] = _copyNode(node);
        order.add(node.id);
      }
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
      return ClipNode(
        id: node.id,
        url: node.url,
        label: node.label,
        colorHex: node.colorHex,
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

  // 🎯 Undo 가능 여부
  bool get canUndo => _undoStack.length > 1;

  // 🎯 Redo 가능 여부
  bool get canRedo => _redoStack.isNotEmpty;

  // 🎯 즉시 히스토리 저장 (외부에서 호출 가능)
  void saveHistoryNow() {
    _historyTimer?.cancel();
    _saveCurrentState(immediate: true);
  }

  // 🎯 Undo 실행
  void undo() {
    if (!canUndo) {
      debugPrint('[EditorService] ❌ Undo 불가 (첫 상태)');
      return;
    }

    try {
      _isExecutingHistory = true;
      _historyTimer?.cancel(); // 대기 중인 저장 취소

      // 현재 상태를 redo 스택에 저장
      final currentSnapshot = _undoStack.removeLast();
      _redoStack.add(currentSnapshot);

      // 이전 상태로 복원
      final previousSnapshot = _undoStack.last;
      _restoreFromSnapshot(previousSnapshot);

      debugPrint('[EditorService] ⬅️ Undo 완료 (남은: ${_undoStack.length})');
    } catch (e) {
      debugPrint('[EditorService] Undo 실패: $e');
    } finally {
      _isExecutingHistory = false;
      // 🎯 Undo/Redo 버튼 상태 업데이트
      notifyListeners();
    }
  }

  // 🎯 Redo 실행
  void redo() {
    if (!canRedo) {
      debugPrint('[EditorService] ❌ Redo 불가 (없음)');
      return;
    }

    try {
      _isExecutingHistory = true;
      _historyTimer?.cancel();

      // Redo 스택에서 다음 상태 가져오기
      final nextSnapshot = _redoStack.removeLast();
      _undoStack.add(nextSnapshot);

      // 다음 상태로 복원
      _restoreFromSnapshot(nextSnapshot);

      debugPrint('[EditorService] ➡️ Redo 완료 (남은 redo: ${_redoStack.length})');
    } catch (e) {
      debugPrint('[EditorService] Redo 실패: $e');
    } finally {
      _isExecutingHistory = false;
      // 🎯 Undo/Redo 버튼 상태 업데이트
      notifyListeners();
    }
  }

  // 🎯 스냅샷으로 문서 복원
  void _restoreFromSnapshot(_DocumentSnapshot snapshot) {
    // 🎯 1. Selection 먼저 클리어 (iOS 핸들 에러 방지)
    try {
      editor.composer.clearSelection();
    } catch (e) {
      debugPrint('[EditorService] Selection 클리어 실패: $e');
    }

    // 🎯 2. 모든 노드 삭제
    while (document.nodeCount > 0) {
      final node = document.getNodeAt(0);
      if (node != null) {
        document.deleteNode(node.id);
      }
    }

    // 🎯 3. 저장된 순서대로 노드 복원
    for (final id in snapshot.order) {
      final node = snapshot.nodes[id];
      if (node != null) {
        document.insertNodeAt(document.nodeCount, _copyNode(node));
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

    // 🎯 UI 갱신 강제
    notifyListeners();

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
          if (node != null && node is ParagraphNode) {
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

                for (int i = mentionLength; i < originalText.text.length; i++) {
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

                notifyListeners();
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
                        if (targetNode != null && targetNode is ParagraphNode) {
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
                            final nextNode = document.getNodeAt(savedNodeIndex);
                            if (nextNode != null &&
                                nextNode is ParagraphNode &&
                                nextNode.metadata['isTitle'] != true) {
                              fallbackPosition = DocumentPosition(
                                nodeId: nextNode.id,
                                nodePosition: const TextNodePosition(offset: 0),
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

              notifyListeners();
              return;
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
        notifyListeners();
        return;
      }
      // 삭제는 이전 인덱스 정보를 잃어서 부분 보정보다 전체 재계산이 안전
      //_recomputeParagraphMargins();
      _ensureParagraphAlignmentForIndex(getEditingIndex());
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
      if (getEditingIndex() == 0) {
        notifyListeners();
        return;
      }
      _ensureOnlyFirstIsTitle();
      // 본문 텍스트 변경으로 UI 갱신 통지
      notifyListeners();
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

    try {
      document.removeListener(_onDocumentChanged);
      editor.composer.selectionNotifier.removeListener(_onSelectionChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onSelectionChanged() {
    final sel = editor.composer.selectionNotifier.value;
    if (sel != null) {
      _lastSelection = sel;

      // 🎯 텍스트 노드가 선택되면 특수 노드 선택 해제
      try {
        final nodeId = sel.extent.nodeId;
        final node = document.getNodeById(nodeId);
        if (node is ParagraphNode &&
            node.metadata['mention'] != true &&
            node.metadata['isTitle'] != true) {
          // 텍스트 노드가 선택되었으므로 특수 노드 선택 해제
          if (_context != null) {
            try {
              final nodeService = _context!.read<NodeComponentService>();
              if (nodeService.selectedNodeId != null) {
                nodeService.clearSelectionSilently();
                nodeService.clearHighlightedSelectionSilently();
                debugPrint('[EditorService] 텍스트 노드 선택 감지 -> 특수 노드 선택 해제');
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
      } else if (node is ImageNode || node is AppImageNode) {
        return true;
      } else if (node is ImageRowNode ||
          node is LinkNode ||
          (node is ParagraphNode && node.metadata['mention'] == true)) {
        return true;
      } else {
        // 기타 노드가 존재하면 본문이 있다고 간주
        return true;
      }
    }
    return false;
  }

  /// 문서 내 이미지/영상 플레이스홀더가 존재하는지 검사
  bool hasAnyPlaceholders() {
    return hasImagePlaceholders() || hasVideoPlaceholders();
  }

  /// 이미지 플레이스홀더(업로드 대기 중) 존재 여부
  bool hasImagePlaceholders() {
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is AppImageNode) {
        final meta = (node as dynamic).metadata as Map<String, dynamic>?;
        final isPlaceholder = meta != null && (meta['isPlaceholder'] == true);
        final hasLocalOnly = (node.imageUrl.isEmpty);
        if (isPlaceholder || hasLocalOnly) return true;
      }
      if (node is ImageRowNode) {
        // 행 내부에 로컬 경로(file://)가 끼어있으면 아직 교체 전이라고 간주
        final urls = node.imageUrls;
        final hasLocal = urls.any((u) => u.startsWith('file://'));
        if (hasLocal) return true;
      }
    }
    return false;
  }

  /// 영상 플레이스홀더(업로드 대기 중) 존재 여부
  bool hasVideoPlaceholders() {
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ClipNode) {
        final url = node.url;
        final localPath = node.localPath;
        if (url.isEmpty && localPath.isNotEmpty) return true;
      }
    }
    return false;
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
        // 노드 삭제 후 문서 끝에 삽입
        document.deleteNode(nodeId);
        document.insertNodeAt(document.length, node);
        notifyListeners();
        return;
      }

      // 노드 삭제 후 새 위치에 삽입
      document.deleteNode(nodeId);

      // targetIndex가 현재 인덱스보다 작으면 그대로 삽입
      final insertIndex =
          targetIndex > currentIndex ? targetIndex - 1 : targetIndex;
      document.insertNodeAt(insertIndex, node);
      // 문서 구조 변경 → 주변만 마진 재계산(O(1))
      //_recomputeParagraphMarginsAround(insertIndex);
      //_recomputeParagraphMarginsAround(currentIndex);
      notifyListeners();
    } finally {
      // 🎯 작업 완료 후 히스토리 추적 재개 + 한 번만 저장
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint(
        '[EditorService] 🔄 노드 순서 변경 완료 (${currentIndex} → ${targetIndex})',
      );
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

    // 타겟이 ImageRowNode인 경우
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
      // 문서 구조 변경 → 주변만 마진 재계산(O(1))
      // _recomputeParagraphMarginsAround(insertIndex);
      notifyListeners();
    } finally {
      // 🎯 작업 완료 후 히스토리 추적 재개 + 한 번만 저장
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 🖼️ 이미지 병합 완료');
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
      // 문서 구조 변경 → 행 주변만 마진 재계산(O(1))
      final int rowIndex = document.getNodeIndexById(rowId);
      if (rowIndex != -1) {
        //_recomputeParagraphMarginsAround(rowIndex);
      }
      notifyListeners();
    } finally {
      // 🎯 작업 완료 후 히스토리 추적 재개 + 한 번만 저장
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 🖼️ ImageRow에 이미지 추가 완료');
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
  void insertEmptyParagraphAtIndex(int index) {
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
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
        } catch (_) {}
      });
      notifyListeners();
    } catch (_) {}
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

      notifyListeners();
    } catch (e) {
      debugPrint('[EditorService] 멘션 추가 실패: $e');
    } finally {
      // 🎯 작업 완료 후 히스토리 추적 재개 + 한 번만 저장
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 📝 멘션 추가 완료');
    }
  }

  /// Video clip placeholder 노드 추가
  String addVideoClipPlaceholderNode(
    String localPath,
    String label, {
    String? thumbnailPath,
  }) {
    final id = 'clip_${DateTime.now().millisecondsSinceEpoch}';
    final node = ClipNode(
      id: id,
      label: label,
      colorHex: '#FF5252',
      url: '',
      localPath: localPath,
      thumbnailPath: thumbnailPath ?? '',
      metadata: {'padding': 'center'}, // 기본 패딩 모드 설정
    );
    _insertComponentNodeAtNextLine(node);
    return id;
  }

  /// Video placeholder의 썸네일 경로 업데이트
  void updateVideoPlaceholderThumbnail(String id, String thumbnailPath) {
    try {
      final node = editor.document.getNodeById(id);
      if (node is ClipNode && node.url.isEmpty) {
        // placeholder 상태일 때만 업데이트
        // 기존 metadata 보존 (패딩 정보 포함)
        final existingMetadata = Map<String, dynamic>.from(node.metadata);

        final updated = ClipNode(
          id: node.id,
          label: node.label,
          colorHex: node.colorHex,
          url: node.url,
          localPath: node.localPath,
          thumbnailPath: thumbnailPath,
          metadata: existingMetadata, // 패딩 정보 보존
        );
        editor.execute([
          ReplaceNodeRequest(existingNodeId: id, newNode: updated),
        ]);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[EditorService] 썸네일 업데이트 실패: $e');
    }
  }

  /// Video placeholder를 실제 URL로 교체
  /// - 기본은 id로 찾고, 실패 시 fallbackLocalPath가 주어지면 localPath로 검색해 교체
  Future<void> replaceVideoPlaceholderWithUrl(
    String id,
    String url, {
    String? fallbackLocalPath,
  }) async {
    try {
      DocumentNode? nodeFound = editor.document.getNodeById(id);
      if (nodeFound is! ClipNode) {
        // id로 못 찾았으면 localPath로 검색 (플레이스홀더가 이동/치환된 경우 대비)
        if (fallbackLocalPath != null && fallbackLocalPath.isNotEmpty) {
          for (int i = 0; i < editor.document.length; i++) {
            final n = editor.document.getNodeAt(i);
            if (n is ClipNode) {
              final lp = n.localPath;
              final isPlaceholder = (n.url.isEmpty && lp.isNotEmpty);
              if (isPlaceholder && lp == fallbackLocalPath) {
                nodeFound = n;
                id = n.id; // 이후 교체를 위해 id 갱신
                break;
              }
            }
          }
        }
      }
      if (nodeFound is! ClipNode) return;

      // 🎯 비디오 프리로드: 노드 교체 전에 비디오 컨트롤러를 미리 초기화하여 깜빡임 방지
      // 프리로드가 완료될 때까지 기다려서 플레이스홀더가 부드럽게 교체되도록 함
      try {
        await PostReaderService.preloadVideo(url);
        debugPrint('[EditorService] ✅ 비디오 프리로드 완료: $url');

        // 프리로드 완료 후 약간의 지연을 추가하여 UI가 안정화되도록 함
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        debugPrint('[EditorService] ⚠️ 비디오 프리로드 실패 (계속 진행): $e');
      }

      // 기존 metadata 보존 (패딩 정보 포함)
      final existingMetadata = Map<String, dynamic>.from(nodeFound.metadata);

      final newNode = ClipNode(
        id: nodeFound.id,
        label: nodeFound.label,
        colorHex: nodeFound.colorHex,
        url: url,
        localPath: '', // placeholder 해제
        thumbnailPath: nodeFound.thumbnailPath, // 썸네일 경로 유지
        metadata: existingMetadata, // 패딩 정보 보존
      );

      editor.execute([
        ReplaceNodeRequest(existingNodeId: id, newNode: newNode),
      ]);

      notifyListeners();
    } catch (e) {
      debugPrint('replaceVideoPlaceholderWithUrl error: $e');
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
            node is ImageNode ||
            node is ImageRowNode ||
            node is LinkNode ||
            node is ClipNode ||
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
      // 문서 구조 변경 → 분리 삽입 위치와 원래 행 주변만 마진 재계산(O(1))
      // _recomputeParagraphMarginsAround(targetInsertIndex);
      //_recomputeParagraphMarginsAround(rowIndex);
      notifyListeners();

      return newImageId;
    } finally {
      // 🎯 작업 완료 후 히스토리 추적 재개 + 한 번만 저장
      _isExecutingHistory = false;
      _saveCurrentState(immediate: true);
      debugPrint('[EditorService] 🖼️ 이미지 분리 완료');
    }
  }

  /// 이미지 추가: 현재 커서 다음 줄에 로컬 경로 기반 이미지 노드 삽입
  void addImageNode(String thumbnailImageUrl) {
    try {
      debugPrint('이미지 추가: $thumbnailImageUrl');

      final imageNode = AppImageNode(
        id: 'image_${DateTime.now().millisecondsSinceEpoch}',
        imageUrl: thumbnailImageUrl,
        altText: '',
      );
      _insertComponentNodeAtNextLine(imageNode);
    } catch (e) {
      debugPrint('이미지 추가 중 오류: $e');
    }
  }

  String addImagePlaceholderNode(String localPath) {
    final id = 'img_${DateTime.now().microsecondsSinceEpoch}';
    // 단일 이미지 노드에는 로컬 경로를 imageUrl에 절대 저장하지 않음
    // 로컬 경로는 metadata.localPath에만 저장하고, imageUrl은 비워둔다
    final imageNode = AppImageNode(
      id: id,
      imageUrl: '',
      altText: '',
      metadata: {'isPlaceholder': true, 'localPath': localPath},
    );
    _insertComponentNodeAtNextLine(imageNode);
    return id;
  }

  /// placeholder 노드 검색 (ID 또는 localPath로)
  ({ImageNode? node, String? localPath, String nodeId})? _findPlaceholderNode(
    String id,
    String? targetLocalPath,
  ) {
    // 1. ID로 직접 검색
    try {
      final node = editor.document.getNodeById(id);
      if (node is ImageNode) {
        final meta = (node as dynamic).metadata as Map<String, dynamic>?;
        final isPlaceholder = meta != null && (meta['isPlaceholder'] == true);
        final nodeLocalPath =
            meta != null ? (meta['localPath']?.toString()) : null;
        if (isPlaceholder) {
          return (node: node, localPath: nodeLocalPath, nodeId: node.id);
        }
      }
    } catch (_) {}

    // 2. 문서 전체에서 placeholder 노드 검색 (localPath 기준)
    final searchLocalPath = targetLocalPath;
    if (searchLocalPath != null) {
      for (int i = 0; i < editor.document.length; i++) {
        final node = editor.document.getNodeAt(i);
        if (node is ImageNode) {
          final meta = (node as dynamic).metadata as Map<String, dynamic>?;
          final isPlaceholder = meta != null && (meta['isPlaceholder'] == true);
          final nodeLocalPath =
              meta != null ? (meta['localPath']?.toString()) : null;
          if (isPlaceholder && nodeLocalPath == searchLocalPath) {
            return (node: node, localPath: nodeLocalPath, nodeId: node.id);
          }
        }
      }
    }

    // 3. ID가 일치하는 placeholder 노드 검색 (ID 변경 대응)
    for (int i = 0; i < editor.document.length; i++) {
      final node = editor.document.getNodeAt(i);
      if (node is ImageNode && node.id == id) {
        final meta = (node as dynamic).metadata as Map<String, dynamic>?;
        if (meta != null && (meta['isPlaceholder'] == true)) {
          final nodeLocalPath = meta['localPath']?.toString();
          return (node: node, localPath: nodeLocalPath, nodeId: node.id);
        }
      }
    }

    return null;
  }

  /// 노드 교체 실행
  bool _replaceNodeWithUrl(String nodeId, String url) {
    try {
      final newNode = AppImageNode(
        id: nodeId,
        imageUrl: url,
        altText: '',
        metadata: {'isPlaceholder': false},
      );
      editor.execute([
        ReplaceNodeRequest(existingNodeId: nodeId, newNode: newNode),
      ]);
      return true;
    } catch (e) {
      debugPrint('[EditorService] ❌ 노드 교체 실패: id=$nodeId, error=$e');
      return false;
    }
  }

  /// 이미지 행 내부 로컬 경로 교체
  void _replaceLocalPathInImageRows(String? localPath, String url) {
    if (localPath == null) return;

    for (int i = 0; i < editor.document.length; i++) {
      final node = editor.document.getNodeAt(i);
      if (node is ImageRowNode) {
        final urls = List<String>.from(node.imageUrls);
        bool changed = false;
        for (int k = 0; k < urls.length; k++) {
          final u = urls[k];
          if (u == localPath || u.startsWith('file://')) {
            urls[k] = url;
            changed = true;
          }
        }
        if (changed) {
          final updated = node.copyWith(imageUrls: urls);
          editor.document.replaceNodeById(node.id, updated);
        }
      }
    }
  }

  Future<void> replacePlaceholderWithUrl(String id, String url) async {
    try {
      // 1. placeholder 노드 검색
      final result = _findPlaceholderNode(id, null);
      if (result == null) {
        debugPrint('[EditorService] ⚠️ placeholder 노드를 찾지 못함: id=$id');
        return;
      }

      var targetNode = result.node;
      var localPath = result.localPath;
      var actualNodeId = result.nodeId;

      // localPath 추출 (없으면 노드에서 가져오기)
      if (localPath == null && targetNode != null) {
        final meta = (targetNode as dynamic).metadata as Map<String, dynamic>?;
        localPath = meta != null ? (meta['localPath']?.toString()) : null;
      }

      // 2. 네트워크 이미지 미리 로드 (깜빡임 방지)
      try {
        final provider = NetworkImage(url);
        final completer = Completer<void>();
        final stream = provider.resolve(const ImageConfiguration());
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (image, synchronousCall) {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (error, stackTrace) {
            if (!completer.isCompleted) completer.complete();
          },
        );
        stream.addListener(listener);
        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
        stream.removeListener(listener);
      } catch (_) {}

      // 3. selection 비우기 (iOS NPE 방지)
      try {
        editor.composer.clearSelection();
      } catch (_) {}

      // 4. 노드 교체
      if (targetNode != null) {
        // 교체 전 노드 재확인 (구조 변경 대응)
        final nodeBeforeReplace = editor.document.getNodeById(actualNodeId);
        if (nodeBeforeReplace == null && localPath != null) {
          // 재검색
          final retryResult = _findPlaceholderNode(id, localPath);
          if (retryResult != null) {
            actualNodeId = retryResult.nodeId;
          }
        }

        // 노드 교체 실행
        if (_replaceNodeWithUrl(actualNodeId, url)) {
          // 교체 확인
          await Future.delayed(const Duration(milliseconds: 100));
          final nodeAfterReplace = editor.document.getNodeById(actualNodeId);
          if (nodeAfterReplace is ImageNode) {
            if (nodeAfterReplace.imageUrl == url) {
              debugPrint(
                '[EditorService] ✅ 노드 교체 완료: id=$actualNodeId, url=$url',
              );
            } else if (localPath != null) {
              // 재시도: localPath로 다시 찾아서 교체
              final retryResult = _findPlaceholderNode(id, localPath);
              if (retryResult != null) {
                _replaceNodeWithUrl(retryResult.nodeId, url);
                debugPrint(
                  '[EditorService] ✅ 재시도로 노드 교체 완료: id=${retryResult.nodeId}',
                );
              }
            }
          } else if (localPath != null) {
            // 노드를 찾지 못한 경우 재시도
            final retryResult = _findPlaceholderNode(id, localPath);
            if (retryResult != null) {
              _replaceNodeWithUrl(retryResult.nodeId, url);
              debugPrint(
                '[EditorService] ✅ 재시도로 노드 교체 완료: id=${retryResult.nodeId}',
              );
            }
          }
        }
        notifyListeners();
      }

      // 5. 이미지 행 내부 로컬 경로 교체
      _replaceLocalPathInImageRows(localPath, url);
    } catch (e, stackTrace) {
      debugPrint(
        '[EditorService] ❌ replacePlaceholderWithUrl 실패: id=$id, url=$url, error=$e',
      );
      debugPrint('[EditorService] ❌ Stack trace: $stackTrace');
    }
  }

  void deleteImagePlaceholderNode(String id) {
    try {
      document.deleteNode(id);
      notifyListeners(); // 🎯 UI 즉시 업데이트
    } catch (_) {}
  }

  void deleteVideoPlaceholderNode(String id) {
    try {
      document.deleteNode(id);
      notifyListeners();
    } catch (_) {}
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
    notifyListeners(); // 🎯 UI 즉시 업데이트
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
}

// 🎯 문서 스냅샷 (전체 노드 + 순서 + 커서)
class _DocumentSnapshot {
  final Map<String, DocumentNode> nodes; // nodeId -> node
  final List<String> order; // 노드 순서
  final DocumentSelection? selection; // 커서 위치

  _DocumentSnapshot({required this.nodes, required this.order, this.selection});
}
