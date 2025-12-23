import 'package:doppy/editor/service/node/node_management_service.dart';
import 'package:doppy/editor/service/selection/selection_management_service.dart';
import 'package:doppy/editor/service/document/document_structure_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

/// 🎯 문서 변경 이벤트 처리 서비스
/// - TextInsertionEvent 처리 (멘션 볼드 처리)
/// - TextDeletedEvent 처리 (하이라이트 노드 삭제, 멘션 노드 삭제)
/// - NodeRemovedEvent 처리 (노드 복원 로직)
/// - NodeInsertedEvent 처리 (멘션 다음 문단 볼드 제거)
/// - NodeMovedEvent, NodeChangeEvent 처리
class DocumentChangeService {
  final Editor editor;
  final MutableDocument document;
  final BuildContext? context;
  final NodeManagementService nodeService;
  final SelectionManagementService selectionService;
  final DocumentStructureService documentService;
  final VoidCallback notifyListeners;
  final Function(DocumentChange) trackChangeFromLog;
  final Function(DocumentNode, DocumentNode) hasNodeChanged;
  final Function(DocumentNode) copyNode;
  final Function(DocumentNode) isSpecialNode;
  final Function() getEditingIndex;
  final Function(bool) setHistoryExecuting;

  // 🎯 Provider 캐싱 (성능 최적화)
  NodeComponentService? _nodeComponentService;

  // 🎯 특수 노드 복원을 위한 캐시 (nodeId → {node, index})
  final Map<String, ({DocumentNode node, int index})> _cachedSpecialNodes = {};

  /// 🎯 특수 노드 캐시 클리어 (임시저장 불러오기 시 호출)
  void clearSpecialNodeCache() {
    _cachedSpecialNodes.clear();
    debugPrint('[DocumentChangeService] 🧹 특수 노드 캐시 클리어');
  }

  DocumentChangeService({
    required this.editor,
    required this.document,
    required this.context,
    required this.nodeService,
    required this.selectionService,
    required this.documentService,
    required this.notifyListeners,
    required this.trackChangeFromLog,
    required this.hasNodeChanged,
    required this.copyNode,
    required this.isSpecialNode,
    required this.getEditingIndex,
    required this.setHistoryExecuting,
  }) {
    // 🎯 초기화 시 Provider 캐싱
    if (context != null) {
      try {
        _nodeComponentService = context!.read<NodeComponentService>();
      } catch (e) {
        // NodeComponentService가 없을 수 있음
      }
    }
  }

  /// 🎯 문서 변경 리스너: 구조가 변했을 때만 마진 재계산
  void handleDocumentChanged(DocumentChangeLog changeLog) {
    final change = changeLog.changes[0];
    debugPrint('changeLog.changes[0]: $change');

    // 🎯 변경된 노드 추적
    trackChangeFromLog(change);

    // 🎯 텍스트 입력/삭제 시 노드 선택 자동 해제 (가볍게 처리)
    if ((change is TextInsertionEvent || change is TextDeletedEvent) &&
        _nodeComponentService != null) {
      if (_nodeComponentService!.selectedNodeId != null) {
        _nodeComponentService!.clearSelectionSilently();
      }
    }

    // 🎯 각 이벤트 타입별 처리
    if (change is TextInsertionEvent) {
      _handleTextInsertion(change);
    } else if (change is TextDeletedEvent) {
      _handleTextDeleted(change);
    } else if (change is NodeRemovedEvent) {
      _handleNodeRemoved(change);
    } else if (change is NodeInsertedEvent) {
      _handleNodeInserted(change);
    } else if (change is NodeMovedEvent) {
      _handleNodeMoved(change);
    } else if (change is NodeChangeEvent) {
      _handleNodeChanged(change);
    }
  }

  /// 🎯 TextInsertionEvent 처리: 멘션 노드에서 텍스트 입력 시 볼드 유지
  void _handleTextInsertion(TextInsertionEvent change) {
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
                  debugPrint('[DocumentChangeService] 멘션 텍스트 스타일 조정 실패: $e');
                }
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DocumentChangeService] 멘션 텍스트 입력 처리 중 오류: $e');
    }

    // 문서 구조 확인
    documentService.ensureOnlyFirstIsTitle();
    // 본문 텍스트 변경으로 UI 갱신 통지
    notifyListeners();
  }

  /// 🎯 TextDeletedEvent 처리: 하이라이트 노드 삭제 및 멘션 노드 처리
  void _handleTextDeleted(TextDeletedEvent change) {
    try {
      debugPrint('[DocumentChangeService] 📝 TextDeletedEvent 시작');

      // 🎯 이번 TextDeletedEvent에서 삭제된 노드 ID 추적 (같은 이벤트 처리 중 복원 방지)
      final deletedInThisEvent = <String>{};

      // 🎯 범위 선택으로 하이라이트된 특수 노드들을 삭제
      _deleteHighlightedNodes(deletedInThisEvent);

      // TextDeletedEvent에서 nodeId 가져오기
      String? targetNodeId = _getTargetNodeId(change);

      if (targetNodeId != null && targetNodeId.isNotEmpty) {
        final node = document.getNodeById(targetNodeId);
        debugPrint(
          '[DocumentChangeService] TextDeletedEvent: targetNodeId=$targetNodeId, node=${node?.runtimeType}',
        );

        // 🎯 노드가 존재하지 않으면 처리 중단
        if (node == null) {
          debugPrint(
            '[DocumentChangeService] ⚠️ TextDeletedEvent: 노드가 존재하지 않음: $targetNodeId',
          );
          return;
        }

        // 특수 노드 위의 ParagraphNode에서 텍스트 삭제 시 특수 노드 정보 저장
        if (node is ParagraphNode) {
          debugPrint('[DocumentChangeService] 📝 ParagraphNode에서 텍스트 삭제');
          _registerSpecialNodeAbove(targetNodeId, node, deletedInThisEvent);

          // 🎯 멘션 노드 처리
          _handleMentionNodeDeletion(change, targetNodeId, node);
        }
      }

      debugPrint(
        '[DocumentChangeService] 📝 현재 캐시: ${_cachedSpecialNodes.keys.toList()}',
      );
    } catch (e, stackTrace) {
      debugPrint('[DocumentChangeService] 멘션 삭제 처리 중 오류: $e');
      debugPrint('[DocumentChangeService] 스택 트레이스: $stackTrace');
    }

    // 문서 구조 확인
    documentService.ensureOnlyFirstIsTitle();
    // 본문 텍스트 변경으로 UI 갱신 통지
    notifyListeners();
  }

  /// 🎯 하이라이트된 노드들을 삭제
  void _deleteHighlightedNodes(Set<String> deletedInThisEvent) {
    // 🎯 selectionService.pendingHighlightedNodeIds 우선 확인, 비어있으면 nodeService.selectionHighlightedIds 확인 (fallback)
    Set<String>? highlightedIds;
    bool isFromPending = false;
    if (selectionService.pendingHighlightedNodeIds.isNotEmpty) {
      highlightedIds = selectionService.pendingHighlightedNodeIds;
      isFromPending = true;
      debugPrint(
        '[DocumentChangeService] 🎯 TextDeletedEvent: selectionService.pendingHighlightedNodeIds에서 ${highlightedIds.length}개 노드 발견',
      );
    } else if (context != null) {
      try {
        final nodeComponentService = context!.read<NodeComponentService>();
        final currentHighlightedIds =
            nodeComponentService.selectionHighlightedIds;
        // 🎯 하이라이트된 노드가 있으면 삭제 대상으로 간주
        if (currentHighlightedIds.isNotEmpty) {
          highlightedIds = currentHighlightedIds;
          isFromPending = false; // nodeService에서 온 것이므로
        }
      } catch (e) {
        debugPrint(
          '[DocumentChangeService] ⚠️ TextDeletedEvent: nodeService 확인 실패: $e',
        );
      }
    }

    if (highlightedIds != null && highlightedIds.isNotEmpty) {
      // 🎯 최적화: 실제로 존재하는 노드만 빠르게 필터링
      final validHighlightedIds = <String>{};
      for (final id in highlightedIds) {
        if (document.getNodeById(id) != null) {
          validHighlightedIds.add(id);
        }
      }

      if (validHighlightedIds.isEmpty) {
        // 이미 모두 삭제된 경우
        selectionService.pendingHighlightedNodeIds.clear();
        // 🎯 하이라이트 클리어 (UI 반응성 향상)
        if (context != null) {
          try {
            context!.read<NodeComponentService>().clearHighlightedSelection();
          } catch (e) {
            // 무시
          }
        }
      } else {
        debugPrint(
          '[DocumentChangeService] 🎯 TextDeletedEvent: 하이라이트된 노드 삭제 시작: ${validHighlightedIds.length}개',
        );
        // 🎯 최적화: 하이라이트 클리어를 삭제 전에 실행 (UI 반응성 향상)
        if (context != null) {
          try {
            context!.read<NodeComponentService>().clearHighlightedSelection();
          } catch (e) {
            // 무시
          }
        }

        // 🎯 selectionService.pendingHighlightedNodeIds에서 온 경우에만 클리어 (재사용 방지)
        if (isFromPending) {
          selectionService.pendingHighlightedNodeIds.clear();
        }

        // 🎯 삭제된 노드 추적
        for (final nodeId in validHighlightedIds) {
          deletedInThisEvent.add(nodeId);
        }

        // 🎯 최적화: 역순으로 삭제 (인덱스가 큰 것부터, 인덱스 계산 최소화)
        final nodeIdsToDelete = <MapEntry<String, int>>[];
        for (final id in validHighlightedIds) {
          final index = document.getNodeIndexById(id);
          if (index != -1) {
            nodeIdsToDelete.add(MapEntry(id, index));
          }
        }
        nodeIdsToDelete.sort((a, b) => b.value.compareTo(a.value));

        // 🎯 삭제 전에 selection을 안전한 위치로 이동 (SuperEditor 크래시 방지)
        _moveSelectionBeforeDelete(validHighlightedIds);

        // 🎯 노드 삭제 실행
        for (final entry in nodeIdsToDelete) {
          document.deleteNode(entry.key);
          debugPrint(
            '[DocumentChangeService] 🗑️ 노드 삭제 실행: ${entry.key} (인덱스: ${entry.value})',
          );
        }

        debugPrint(
          '[DocumentChangeService] ✅ 하이라이트된 특수 노드 삭제 완료 (TextDeletedEvent): ${nodeIdsToDelete.length}개, nodeService.explicitlyDeletedNodes에 ${validHighlightedIds.length}개 추가됨',
        );

        // 🎯 UI 업데이트 (document.deleteNode()가 NodeRemovedEvent를 발생시키지만, 명시적으로 호출)
        notifyListeners();
      }
    }
  }

  /// 🎯 삭제 전 selection을 안전한 위치로 이동
  void _moveSelectionBeforeDelete(Set<String> validHighlightedIds) {
    try {
      final currentSelection = editor.composer.selectionNotifier.value;
      if (currentSelection != null) {
        final nodeId = currentSelection.extent.nodeId;
        // 🎯 삭제될 노드를 가리키고 있으면 안전한 위치로 이동
        if (validHighlightedIds.contains(nodeId)) {
          // 가장 가까운 ParagraphNode로 이동
          DocumentPosition? safePosition;
          for (int i = 0; i < document.nodeCount; i++) {
            final candidateNode = document.getNodeAt(i);
            if (candidateNode is ParagraphNode &&
                candidateNode.metadata['isTitle'] != true &&
                !validHighlightedIds.contains(candidateNode.id)) {
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
            editor.composer.setSelectionWithReason(
              DocumentSelection.collapsed(position: safePosition),
              SelectionReason.userInteraction,
            );
            debugPrint(
              '[DocumentChangeService] ✅ 삭제 전 안전한 위치로 이동 (TextDeletedEvent)',
            );
          } else {
            // 안전한 위치가 없으면 selection 클리어
            editor.composer.clearSelection();
          }
        }
      }
    } catch (e) {
      debugPrint('[DocumentChangeService] ⚠️ 삭제 전 selection 이동 실패: $e');
      try {
        editor.composer.clearSelection();
      } catch (_) {}
    }
  }

  /// 🎯 targetNodeId 가져오기
  String? _getTargetNodeId(TextDeletedEvent change) {
    final selection = editor.composer.selectionNotifier.value;
    String? targetNodeId;
    try {
      targetNodeId = (change as dynamic).nodeId as String?;
    } catch (_) {}

    // 현재 selection에서 가져오기
    if (targetNodeId == null) {
      if (selection != null && selection.extent.nodeId.isNotEmpty) {
        targetNodeId = selection.extent.nodeId;
      }
    }

    return targetNodeId;
  }

  /// 🎯 특수 노드 위의 ParagraphNode에서 특수 노드 정보 저장
  void _registerSpecialNodeAbove(
    String targetNodeId,
    ParagraphNode node,
    Set<String> deletedInThisEvent,
  ) {
    final nodeIndex = document.getNodeIndexById(targetNodeId);

    // 🎯 인덱스 유효성 확인
    if (nodeIndex < 0 || nodeIndex >= document.nodeCount) {
      debugPrint(
        '[DocumentChangeService] ⚠️ TextDeletedEvent: 잘못된 인덱스: $nodeIndex',
      );
      return;
    }

    if (nodeIndex > 0) {
      final prevNode = document.getNodeAt(nodeIndex - 1);
      debugPrint(
        '[DocumentChangeService] TextDeletedEvent: prevNode=${prevNode?.runtimeType}, id=${prevNode?.id}',
      );

      if (prevNode != null && isSpecialNode(prevNode)) {
        // 🎯 빈 텍스트 노드인 경우: 노드 삭제 + 키보드 내리기 (히스토리 기록 방지)
        if (node.text.text.isEmpty && node.metadata['isTitle'] != true) {
          debugPrint(
            '[DocumentChangeService] 🎯 빈 텍스트 노드 + 위에 특수 노드 → 노드 삭제 & 키보드 내리기',
          );

          // 🎯 이전에 캐싱된 특수 노드 캐시 클리어 (잘못된 복원 방지)
          if (_cachedSpecialNodes.containsKey(prevNode.id)) {
            _cachedSpecialNodes.remove(prevNode.id);
            debugPrint(
              '[DocumentChangeService] 🧹 특수 노드 캐시 클리어: ${prevNode.id}',
            );
          }

          // 🎯 히스토리 기록 방지 (언두 시 빈 노드 복원 방지)
          setHistoryExecuting(true);

          try {
            // 노드 삭제
            document.deleteNode(targetNodeId);
            debugPrint('[DocumentChangeService] ✅ 빈 텍스트 노드 삭제: $targetNodeId');

            // 🎯 키보드 내리기 (언두 시에는 자동으로 이전 상태 복원됨)
            if (context != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  FocusScope.of(context!).unfocus();
                  debugPrint('[DocumentChangeService] ⌨️ 키보드 내림');
                } catch (e) {
                  debugPrint('[DocumentChangeService] ⚠️ 키보드 내리기 실패: $e');
                }
              });
            }
          } catch (e) {
            debugPrint('[DocumentChangeService] ❌ 노드 삭제 실패: $e');
          } finally {
            // 🎯 히스토리 플래그 복원
            setHistoryExecuting(false);
          }

          return; // 더 이상 처리하지 않음 (캐싱 불필요)
        }

        // 🎯 텍스트가 있는 경우: 특수 노드 캐싱 (삭제 시 복원을 위해)
        _cachedSpecialNodes[prevNode.id] = (
          node: copyNode(prevNode),
          index: nodeIndex - 1,
        );
        debugPrint(
          '[DocumentChangeService] 🔖 특수 노드 캐싱: ${prevNode.id} (인덱스: ${nodeIndex - 1})',
        );
      } else {
        debugPrint(
          '[DocumentChangeService] 이전 노드가 특수 노드가 아님: ${prevNode?.runtimeType}',
        );
      }
    } else {
      debugPrint('[DocumentChangeService] nodeIndex가 0 이하: $nodeIndex');
    }
  }

  /// 🎯 멘션 노드 삭제 처리
  void _handleMentionNodeDeletion(
    TextDeletedEvent change,
    String targetNodeId,
    ParagraphNode node,
  ) {
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
      if (selection != null && selection.extent.nodeId == targetNodeId) {
        try {
          cursorOffset =
              (selection.extent.nodePosition as TextNodePosition).offset;
        } catch (_) {}
      }

      // 현재 텍스트 길이 확인 (삭제 후)
      final currentText = node.text.text;

      // 삭제 전 텍스트 길이 추정
      final previousTextLength = currentText.length + (deletedLength ?? 1);

      // 삭제 위치 확인
      final isDeletingAfterMention =
          (deletedOffset != null && deletedOffset >= mentionLength) ||
          (previousTextLength > mentionLength &&
              cursorOffset != null &&
              cursorOffset >= mentionLength);

      if (isDeletingAfterMention) {
        // 멘션 텍스트 이후에서 삭제하는 경우 일반 삭제 동작 허용
        debugPrint(
          '[DocumentChangeService] 멘션 텍스트 이후에서 삭제: deletedOffset=$deletedOffset, cursorOffset=$cursorOffset, mentionLength=$mentionLength',
        );
        return;
      }

      // 멘션 텍스트 내부에서 삭제가 발생한 경우
      if (currentText.length > mentionLength) {
        // 멘션 이후에 텍스트가 남아있음 → 멘션 부분만 제거하고 나머지 유지
        _removeMentionKeepRest(targetNodeId, node, mentionLength);
        return;
      }

      // 멘션 텍스트만 있으면 노드 전체 삭제
      _deleteMentionNode(targetNodeId);
    }
  }

  /// 🎯 멘션 부분만 제거하고 나머지 텍스트 유지
  void _removeMentionKeepRest(
    String targetNodeId,
    ParagraphNode node,
    int mentionLength,
  ) {
    final remainingText = node.text.text.substring(mentionLength);

    final nodeIndex = document.getNodeIndexById(targetNodeId);
    if (nodeIndex == -1) {
      debugPrint('[DocumentChangeService] 멘션 부분 삭제: 유효하지 않은 노드 인덱스');
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
            newText.addAttribution(attr, SpanRange(newIndex, newIndex));
          }
        }
      }
    }

    // 일반 문단으로 변환 (mention 메타데이터 제거)
    final newParagraph = ParagraphNode(
      id: targetNodeId,
      text: newText,
      metadata: {'textAlign': node.metadata['textAlign'] ?? 'center'},
    );

    // 노드 교체
    editor.execute([
      ReplaceNodeRequest(existingNodeId: targetNodeId, newNode: newParagraph),
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
        debugPrint('[DocumentChangeService] 커서 이동 실패: $e');
      }
    });
  }

  /// 🎯 멘션 노드 전체 삭제
  void _deleteMentionNode(String targetNodeId) {
    final nodeIndex = document.getNodeIndexById(targetNodeId);

    // 유효한 인덱스인지 확인
    if (nodeIndex == -1) {
      debugPrint('[DocumentChangeService] 멘션 삭제: 유효하지 않은 노드 인덱스');
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
        debugPrint('[DocumentChangeService] 다음 노드 확인 실패: $e');
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
        debugPrint('[DocumentChangeService] 이전 노드 확인 실패: $e');
      }
    }

    // 노드 삭제 전에 커서 위치 저장
    final savedTargetPosition = targetPosition;
    final savedNodeIndex = nodeIndex;

    // 🎯 노드가 여전히 존재하는지 확인 (이중 삭제 방지)
    if (document.getNodeById(targetNodeId) == null) {
      debugPrint('[DocumentChangeService] ⚠️ 멘션 노드가 이미 삭제됨: $targetNodeId');
      return;
    }

    // 노드 삭제
    try {
      document.deleteNode(targetNodeId);
      debugPrint('[DocumentChangeService] 멘션 노드 삭제 완료: $targetNodeId');
    } catch (e) {
      debugPrint('[DocumentChangeService] 멘션 노드 삭제 실패: $e');
      return;
    }

    // 🎯 커서 이동 (삭제 후 여러 프레임을 기다려 안전하게 처리)
    if (savedTargetPosition != null) {
      _moveCursorAfterMentionDeletion(savedTargetPosition, savedNodeIndex);
    } else {
      // 커서 위치가 없으면 그냥 클리어만 유지
      debugPrint('[DocumentChangeService] 멘션 삭제: 커서 이동 위치 없음, 클리어 상태 유지');
    }
  }

  /// 🎯 멘션 삭제 후 커서 이동
  void _moveCursorAfterMentionDeletion(
    DocumentPosition savedTargetPosition,
    int savedNodeIndex,
  ) {
    // 첫 번째 프레임: 문서 구조 안정화 대기
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 두 번째 프레임: IME 초기화 대기
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 세 번째 프레임: 안전하게 커서 이동
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            // 삭제 후에도 노드가 존재하는지 확인
            final targetNode = document.getNodeById(savedTargetPosition.nodeId);
            if (targetNode != null && targetNode is ParagraphNode) {
              // 노드가 여전히 존재하고 유효한지 확인
              final currentIndex = document.getNodeIndexById(
                savedTargetPosition.nodeId,
              );
              if (currentIndex != -1) {
                editor.execute([
                  ChangeSelectionRequest(
                    DocumentSelection.collapsed(position: savedTargetPosition),
                    SelectionChangeType.placeCaret,
                    SelectionReason.userInteraction,
                  ),
                ]);
                return;
              }
            }

            // 타겟 노드가 없으면 안전한 위치로 이동
            final fallbackPosition = _findFallbackPosition(savedNodeIndex);
            if (fallbackPosition != null) {
              editor.execute([
                ChangeSelectionRequest(
                  DocumentSelection.collapsed(position: fallbackPosition),
                  SelectionChangeType.placeCaret,
                  SelectionReason.userInteraction,
                ),
              ]);
            }
          } catch (e, stackTrace) {
            debugPrint('[DocumentChangeService] 커서 이동 실패: $e');
            debugPrint('[DocumentChangeService] 스택 트레이스: $stackTrace');
          }
        });
      });
    });
  }

  /// 🎯 fallback 커서 위치 찾기
  DocumentPosition? _findFallbackPosition(int savedNodeIndex) {
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
        final prevNode = document.getNodeAt(savedNodeIndex - 1);
        if (prevNode != null &&
            prevNode is ParagraphNode &&
            prevNode.metadata['isTitle'] != true) {
          final prevText = prevNode.text.text;
          fallbackPosition = DocumentPosition(
            nodeId: prevNode.id,
            nodePosition: TextNodePosition(
              offset: prevText.length.clamp(0, prevText.length),
            ),
          );
        }
      } catch (_) {}
    }

    // 최후의 수단: 문서 끝으로 이동
    if (fallbackPosition == null && document.nodeCount > 0) {
      try {
        final lastNode = document.getNodeAt(document.nodeCount - 1);
        if (lastNode is ParagraphNode && lastNode.metadata['isTitle'] != true) {
          final lastText = lastNode.text.text;
          fallbackPosition = DocumentPosition(
            nodeId: lastNode.id,
            nodePosition: TextNodePosition(
              offset: lastText.length.clamp(0, lastText.length),
            ),
          );
        }
      } catch (_) {}
    }

    return fallbackPosition;
  }

  /// 🎯 NodeRemovedEvent 처리 (특수 노드 복원)
  void _handleNodeRemoved(NodeRemovedEvent change) {
    if (getEditingIndex() == 0) {
      // 타이틀 문단 삭제 방지
      documentService.ensureTitleAtTop();
      return;
    }

    final removedNodeId = change.nodeId;
    debugPrint(
      '[DocumentChangeService] 🗑️ NodeRemovedEvent: nodeId=$removedNodeId',
    );
    debugPrint(
      '[DocumentChangeService] 🗑️ 현재 캐시: ${_cachedSpecialNodes.keys.toList()}',
    );
    debugPrint(
      '[DocumentChangeService] 🗑️ 캐시에 있나? ${_cachedSpecialNodes.containsKey(removedNodeId)}',
    );

    // 🎯 특수 노드 복원 체크
    if (_cachedSpecialNodes.containsKey(removedNodeId)) {
      final cached = _cachedSpecialNodes[removedNodeId]!;

      // 🎯 의도적 삭제인지 확인 (하이라이트 체크)
      final isIntentionalDelete = _isIntentionalDelete(removedNodeId);
      debugPrint('[DocumentChangeService] 🗑️ 의도적 삭제? $isIntentionalDelete');

      if (isIntentionalDelete) {
        // 의도적 삭제: 캐시 클리어 및 업로드 취소
        debugPrint('[DocumentChangeService] ✅ 의도적 삭제 감지: $removedNodeId');
        _cachedSpecialNodes.remove(removedNodeId);
        _cancelUpload(removedNodeId);
      } else {
        // 실수 삭제: 즉시 복원
        debugPrint('[DocumentChangeService] 🔄 특수 노드 복원 시작: $removedNodeId');
        _restoreSpecialNode(removedNodeId, cached.node, cached.index);
      }
    } else {
      debugPrint('[DocumentChangeService] ⚠️ 캐시에 없음 - 복원 불가');
      // 일반 노드 삭제: 업로드 취소만
      if (removedNodeId.startsWith('clip_') ||
          removedNodeId.startsWith('img_') ||
          removedNodeId.startsWith('group_')) {
        _cancelUpload(removedNodeId);
      }
    }
  }

  /// 🎯 의도적 삭제 감지 (하이라이트된 상태에서 삭제)
  bool _isIntentionalDelete(String nodeId) {
    // 하이라이트된 노드 목록에 있으면 의도적 삭제
    if (_nodeComponentService != null) {
      if (_nodeComponentService!.selectionHighlightedIds.contains(nodeId)) {
        return true;
      }
    }

    if (selectionService.pendingHighlightedNodeIds.contains(nodeId)) {
      return true;
    }

    return false;
  }

  /// 🎯 특수 노드 복원
  void _restoreSpecialNode(
    String nodeId,
    DocumentNode node,
    int originalIndex,
  ) {
    try {
      // 🎯 히스토리 기록 방지
      setHistoryExecuting(true);

      try {
        // 현재 인덱스 계산 (삭제 후 인덱스가 변경될 수 있음)
        final targetIndex = originalIndex.clamp(0, document.nodeCount);

        // 노드 복원
        document.insertNodeAt(targetIndex, node);

        debugPrint(
          '[DocumentChangeService] ✅ 특수 노드 복원 완료: $nodeId (인덱스: $targetIndex)',
        );

        // 캐시 클리어
        _cachedSpecialNodes.remove(nodeId);

        // UI 갱신
        notifyListeners();
      } finally {
        // 히스토리 플래그 복원
        setHistoryExecuting(false);
      }
    } catch (e, stack) {
      debugPrint('[DocumentChangeService] ❌ 특수 노드 복원 실패: $e');
      debugPrint('[DocumentChangeService] Stack: $stack');
      // 복원 실패 시 캐시 클리어
      _cachedSpecialNodes.remove(nodeId);
    }
  }

  /// 🎯 업로드 취소
  void _cancelUpload(String removedNodeId) {
    try {
      if (context != null) {
        final uploadService = context!.read<UploadService>();
        uploadService.cancelByRef(removedNodeId);
        final editorId = 'editor_${editor.hashCode}';
        uploadService.cancelEditorCompressions(editorId);
      }
    } catch (e) {
      debugPrint('[DocumentChangeService] 업로드 취소 오류: $e');
    }
  }

  /// 🎯 NodeInsertedEvent 처리: 멘션 노드 다음 문단 볼드 제거
  void _handleNodeInserted(NodeInsertedEvent change) {
    try {
      final insertedNode = document.getNodeAt(change.insertionIndex);
      if (insertedNode is ParagraphNode &&
          insertedNode.metadata['mention'] != true &&
          change.insertionIndex > 0) {
        // 이전 노드가 멘션 노드인지 확인
        final prevNode = document.getNodeAt(change.insertionIndex - 1);
        if (prevNode is ParagraphNode && prevNode.metadata['mention'] == true) {
          // 멘션 노드 다음에 생성된 문단이면 composer의 bold preference 제거
          if (editor.composer.preferences.currentAttributions.contains(
            boldAttribution,
          )) {
            editor.composer.preferences.removeStyle(boldAttribution);
            debugPrint(
              '[DocumentChangeService] 멘션 노드 다음 문단 생성: 볼드 preference 제거',
            );
          }

          // 새로 생성된 문단의 텍스트에서도 볼드 attribution 제거
          _removeBoldFromInsertedNode(insertedNode);
        }
      }
    } catch (e) {
      debugPrint('[DocumentChangeService] 멘션 노드 다음 문단 볼드 제거 실패: $e');
    }

    // 새 문단의 정렬 승계
    documentService.ensureParagraphAlignmentForIndex(change.insertionIndex);
    documentService.ensureOnlyFirstIsTitle();
    // 문서 구조가 변했으므로 UI 갱신 필요
    notifyListeners();
  }

  /// 🎯 삽입된 노드에서 볼드 제거
  void _removeBoldFromInsertedNode(ParagraphNode insertedNode) {
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
            debugPrint('[DocumentChangeService] 멘션 노드 다음 문단 볼드 제거 실패: $e');
          }
        });
      }
    }
  }

  /// 🎯 NodeMovedEvent 처리
  void _handleNodeMoved(NodeMovedEvent change) {
    documentService.ensureOnlyFirstIsTitle();
    // 문서 구조가 변했으므로 UI 갱신 필요
    notifyListeners();
  }

  /// 🎯 NodeChangeEvent 처리
  void _handleNodeChanged(NodeChangeEvent change) {
    // 타입 변경 등 구조 영향 가능 → 해당 인덱스만 우선 보정
    final idx = document.getNodeIndexById(change.nodeId);
    if (idx != -1) {
      documentService.ensureParagraphAlignmentForIndex(getEditingIndex());
      documentService.ensureOnlyFirstIsTitle();
    } else {
      documentService.ensureOnlyFirstIsTitle();
    }
    // 문서 구조/내용이 변했으므로 UI 갱신 필요
    notifyListeners();
  }
}
