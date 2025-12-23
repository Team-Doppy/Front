import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 🎯 멘션 관련 작업 전담 서비스
class MentionService {
  final Editor editor;
  final MutableDocument document;
  final Function(bool) setHistoryExecuting;
  final Function(bool, VoidCallback?) saveHistory;
  final VoidCallback notifyListeners;
  final int Function() getCaretNodeIndexSafe;
  final String Function(int) getPreviousParagraphAlign;

  MentionService({
    required this.editor,
    required this.document,
    required this.setHistoryExecuting,
    required this.saveHistory,
    required this.notifyListeners,
    required this.getCaretNodeIndexSafe,
    required this.getPreviousParagraphAlign,
  });

  /// 🎯 멘션 노드에서 텍스트 입력 시 처리
  /// 멘션 부분만 볼드로 유지하고 나머지는 일반 텍스트로 처리
  void handleMentionTextInsertion(String targetNodeId) {
    try {
      final node = document.getNodeById(targetNodeId);
      if (node == null || node is! ParagraphNode) return;

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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              final updatedNode = document.getNodeById(targetNodeId);
              if (updatedNode != null && updatedNode is ParagraphNode) {
                final text = updatedNode.text;
                final textLength = text.text.length;

                // 멘션 부분 이후의 텍스트에서만 볼드 제거
                if (textLength > mentionLength) {
                  final newText = AttributedText(text.text);

                  // 기존 attribution 복사 (멘션 부분만)
                  for (int i = 0; i < mentionLength && i < textLength; i++) {
                    final attributions = text.getAllAttributionsAt(i);
                    for (final attr in attributions) {
                      newText.addAttribution(attr, SpanRange(i, i));
                    }
                  }

                  // 멘션 부분 이후는 볼드 제외
                  for (int i = mentionLength; i < textLength; i++) {
                    final attributions = text.getAllAttributionsAt(i);
                    for (final attr in attributions) {
                      if (attr != boldAttribution) {
                        newText.addAttribution(attr, SpanRange(i, i));
                      }
                    }
                  }

                  final newNode = ParagraphNode(
                    id: updatedNode.id,
                    text: newText,
                    metadata: Map<String, dynamic>.from(updatedNode.metadata),
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
              debugPrint('[MentionService] 멘션 텍스트 스타일 조정 실패: $e');
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[MentionService] 멘션 텍스트 입력 처리 중 오류: $e');
    }
  }

  /// 🎯 멘션 노드에서 텍스트 삭제 시 처리
  /// 멘션 텍스트 내부에서 삭제가 발생하면 노드 전체 또는 멘션 부분만 제거
  void handleMentionTextDeletion(
    String targetNodeId,
    int? deletedOffset,
    int? deletedLength,
  ) {
    try {
      final node = document.getNodeById(targetNodeId);
      if (node == null || node is! ParagraphNode) return;

      final isMention = node.metadata['mention'] == true;
      final List<dynamic> usernames =
          (node.metadata['usernames'] as List?) ?? const [];

      if (!isMention || usernames.isEmpty) return;

      final mentionText = '@${usernames.first}';
      final mentionLength = mentionText.length;
      final currentText = node.text.text;

      // 현재 커서 위치 확인
      final selection = editor.composer.selectionNotifier.value;
      int? cursorOffset;
      if (selection != null && selection.extent.nodeId == targetNodeId) {
        try {
          cursorOffset =
              (selection.extent.nodePosition as TextNodePosition).offset;
        } catch (_) {}
      }

      // 삭제 전 텍스트 길이 추정
      final previousTextLength = currentText.length + (deletedLength ?? 1);

      // 삭제 위치 확인
      final isDeletingAfterMention =
          (deletedOffset != null && deletedOffset >= mentionLength) ||
          (previousTextLength > mentionLength &&
              cursorOffset != null &&
              cursorOffset >= mentionLength);

      if (isDeletingAfterMention) {
        // 멘션 텍스트 이후에서 삭제하는 경우 일반 삭제 허용
        debugPrint('[MentionService] 멘션 텍스트 이후에서 삭제');
        return;
      }

      // 멘션 텍스트 내부에서 삭제 발생
      if (currentText.length > mentionLength) {
        // 멘션 이후에 텍스트가 남아있음 → 멘션 부분만 제거
        _removeMentionPartOnly(targetNodeId, node, mentionLength);
      } else {
        // 멘션 텍스트만 있음 → 노드 전체 삭제
        _deleteMentionNode(targetNodeId);
      }
    } catch (e, stackTrace) {
      debugPrint('[MentionService] 멘션 삭제 처리 중 오류: $e');
      debugPrint('[MentionService] 스택 트레이스: $stackTrace');
    }
  }

  /// 멘션 부분만 제거하고 나머지 텍스트 유지
  void _removeMentionPartOnly(
    String targetNodeId,
    ParagraphNode node,
    int mentionLength,
  ) {
    final nodeIndex = document.getNodeIndexById(targetNodeId);
    if (nodeIndex == -1) return;

    final remainingText = node.text.text.substring(mentionLength);
    final newText = AttributedText(remainingText);
    final originalText = node.text;

    // 나머지 텍스트의 attribution 복사 (볼드 제외)
    for (int i = mentionLength; i < originalText.text.length; i++) {
      final attributions = originalText.getAllAttributionsAt(i);
      for (final attr in attributions) {
        if (attr != boldAttribution) {
          final newIndex = i - mentionLength;
          if (newIndex >= 0 && newIndex < remainingText.length) {
            newText.addAttribution(attr, SpanRange(newIndex, newIndex));
          }
        }
      }
    }

    // 일반 문단으로 변환
    final newParagraph = ParagraphNode(
      id: targetNodeId,
      text: newText,
      metadata: {'textAlign': node.metadata['textAlign'] ?? 'center'},
    );

    editor.execute([
      ReplaceNodeRequest(existingNodeId: targetNodeId, newNode: newParagraph),
    ]);

    // 커서를 나머지 텍스트의 시작으로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        editor.execute([
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
        ]);
      } catch (e) {
        debugPrint('[MentionService] 커서 이동 실패: $e');
      }
    });
  }

  /// 멘션 노드 전체 삭제
  void _deleteMentionNode(String targetNodeId) {
    final nodeIndex = document.getNodeIndexById(targetNodeId);
    if (nodeIndex == -1) return;

    // 다음 노드로 커서 이동할 위치 찾기
    DocumentPosition? targetPosition =
        _findNextPosition(nodeIndex) ?? _findPreviousPosition(nodeIndex);

    // 노드가 여전히 존재하는지 확인
    if (document.getNodeById(targetNodeId) == null) {
      debugPrint('[MentionService] ⚠️ 멘션 노드가 이미 삭제됨: $targetNodeId');
      return;
    }

    // 노드 삭제
    try {
      document.deleteNode(targetNodeId);
      debugPrint('[MentionService] 멘션 노드 삭제 완료: $targetNodeId');
    } catch (e) {
      debugPrint('[MentionService] 멘션 노드 삭제 실패: $e');
      return;
    }

    // 커서 이동 (3프레임 대기)
    if (targetPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _moveCursorSafely(targetPosition, nodeIndex);
          });
        });
      });
    } else {
      debugPrint('[MentionService] 멘션 삭제: 커서 이동 위치 없음');
    }
  }

  /// 다음 문단 위치 찾기
  DocumentPosition? _findNextPosition(int nodeIndex) {
    if (nodeIndex + 1 < document.nodeCount) {
      try {
        final nextNode = document.getNodeAt(nodeIndex + 1);
        if (nextNode != null &&
            nextNode is ParagraphNode &&
            nextNode.metadata['isTitle'] != true) {
          return DocumentPosition(
            nodeId: nextNode.id,
            nodePosition: const TextNodePosition(offset: 0),
          );
        }
      } catch (e) {
        debugPrint('[MentionService] 다음 노드 확인 실패: $e');
      }
    }
    return null;
  }

  /// 이전 문단 위치 찾기
  DocumentPosition? _findPreviousPosition(int nodeIndex) {
    if (nodeIndex > 1) {
      try {
        final prevNode = document.getNodeAt(nodeIndex - 1);
        if (prevNode != null &&
            prevNode is ParagraphNode &&
            prevNode.metadata['isTitle'] != true) {
          final prevText = prevNode.text.text;
          return DocumentPosition(
            nodeId: prevNode.id,
            nodePosition: TextNodePosition(
              offset: prevText.length.clamp(0, prevText.length),
            ),
          );
        }
      } catch (e) {
        debugPrint('[MentionService] 이전 노드 확인 실패: $e');
      }
    }
    return null;
  }

  /// 안전하게 커서 이동
  void _moveCursorSafely(DocumentPosition? targetPosition, int savedNodeIndex) {
    try {
      final targetNode = document.getNodeById(targetPosition!.nodeId);
      if (targetNode != null && targetNode is ParagraphNode) {
        final currentIndex = document.getNodeIndexById(targetPosition.nodeId);
        if (currentIndex != -1) {
          editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(position: targetPosition),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
          return;
        }
      }

      // fallback 위치 찾기
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
      debugPrint('[MentionService] 커서 이동 실패: $e');
      debugPrint('[MentionService] 스택 트레이스: $stackTrace');
    }
  }

  /// Fallback 위치 찾기
  DocumentPosition? _findFallbackPosition(int savedNodeIndex) {
    // 삭제된 노드의 다음 위치 확인
    if (savedNodeIndex < document.nodeCount) {
      try {
        final nextNode = document.getNodeAt(savedNodeIndex);
        if (nextNode != null &&
            nextNode is ParagraphNode &&
            nextNode.metadata['isTitle'] != true) {
          return DocumentPosition(
            nodeId: nextNode.id,
            nodePosition: const TextNodePosition(offset: 0),
          );
        }
      } catch (_) {}
    }

    // 이전 노드 확인
    if (savedNodeIndex > 1) {
      try {
        final prevNode = document.getNodeAt(savedNodeIndex - 1);
        if (prevNode != null &&
            prevNode is ParagraphNode &&
            prevNode.metadata['isTitle'] != true) {
          final prevText = prevNode.text.text;
          return DocumentPosition(
            nodeId: prevNode.id,
            nodePosition: TextNodePosition(
              offset: prevText.length.clamp(0, prevText.length),
            ),
          );
        }
      } catch (_) {}
    }

    // 문서 끝으로 이동
    if (document.nodeCount > 0) {
      try {
        final lastNode = document.getNodeAt(document.nodeCount - 1);
        if (lastNode is ParagraphNode && lastNode.metadata['isTitle'] != true) {
          final lastText = lastNode.text.text;
          return DocumentPosition(
            nodeId: lastNode.id,
            nodePosition: TextNodePosition(
              offset: lastText.length.clamp(0, lastText.length),
            ),
          );
        }
      } catch (_) {}
    }

    return null;
  }

  /// 🎯 멘션 노드 다음에 생성된 문단의 볼드 attribution 제거
  void handleParagraphInsertedAfterMention(int insertionIndex) {
    try {
      final insertedNode = document.getNodeAt(insertionIndex);
      if (insertedNode is! ParagraphNode ||
          insertedNode.metadata['mention'] == true ||
          insertionIndex <= 0) {
        return;
      }

      // 이전 노드가 멘션 노드인지 확인
      final prevNode = document.getNodeAt(insertionIndex - 1);
      if (prevNode is! ParagraphNode || prevNode.metadata['mention'] != true) {
        return;
      }

      // composer의 bold preference 제거
      if (editor.composer.preferences.currentAttributions.contains(
        boldAttribution,
      )) {
        editor.composer.preferences.removeStyle(boldAttribution);
        debugPrint('[MentionService] 멘션 노드 다음 문단: 볼드 preference 제거');
      }

      // 새로 생성된 문단의 텍스트에서도 볼드 제거
      final text = insertedNode.text;
      if (text.text.isEmpty) return;

      bool hasBold = false;
      for (int i = 0; i < text.text.length; i++) {
        if (text.getAllAttributionsAt(i).contains(boldAttribution)) {
          hasBold = true;
          break;
        }
      }

      if (hasBold) {
        final newText = AttributedText(text.text);
        for (int i = 0; i < text.text.length; i++) {
          final attributions = text.getAllAttributionsAt(i);
          for (final attr in attributions) {
            if (attr != boldAttribution) {
              newText.addAttribution(attr, SpanRange(i, i));
            }
          }
        }

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
            debugPrint('[MentionService] 멘션 노드 다음 문단 볼드 제거 실패: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('[MentionService] 멘션 노드 다음 문단 볼드 제거 실패: $e');
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
    setHistoryExecuting(true);

    try {
      final doc = editor.document;
      final safeIndex = getCaretNodeIndexSafe();
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
      final String inheritedAlign = getPreviousParagraphAlign(insertIndex);

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
      debugPrint('[MentionService] 멘션 추가 실패: $e');
    } finally {
      // 🎯 작업 완료 후 히스토리 추적 재개 + 한 번만 저장
      setHistoryExecuting(false);
      saveHistory(true, notifyListeners);
      debugPrint('[MentionService] 📝 멘션 추가 완료');
    }
  }
}
