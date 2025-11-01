import 'dart:async';
import 'dart:convert';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/sticker_service.dart';
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
  // 멘션 삭제 처리 중 무한 루프 방지 플래그
  bool _isClearingMention = false;

  // 최근 저장 스냅샷 지문
  String? _lastSavedFingerprint;

  // 제목 스타일 전파 방지용 스냅샷(간소화 이후 미사용)
  // ignore: unused_field
  int _lastTitleTextLength = 0;

  EditorService({required this.editor, required this.document}) {
    document.addListener(_onDocumentChanged);
    editor.composer.selectionNotifier.addListener(_onSelectionChanged);
  }

  void setDocumentLayoutKey(GlobalKey key) {
    _documentLayoutKey = key;
  }

  GlobalKey? get documentLayoutKey => _documentLayoutKey;

  // 문서 변경 리스너: 구조가 변했을 때만 마진 재계산
  void _onDocumentChanged(DocumentChangeLog changeLog) {
    final change = changeLog.changes[0];
    print('changeLog.changes[0]: $change');

    // 멘션 문단(ParagraphNode with metadata.mention == true)에서 일부 삭제가 발생하면
    // 텍스트를 한 번에 비우도록 처리 (가장 먼저 체크)
    if (change is TextDeletedEvent && !_isClearingMention) {
      try {
        // TextDeletedEvent에서 직접 nodeId 가져오기
        String? targetNodeId;
        try {
          targetNodeId = (change as dynamic).nodeId as String?;
          print(
            '[EditorService] TextDeletedEvent에서 nodeId 직접 가져오기: $targetNodeId',
          );
        } catch (_) {}

        // 방법 1: _lastSelection에서 가져오기 (삭제 전 상태)
        if (targetNodeId == null && _lastSelection != null) {
          targetNodeId = _lastSelection!.extent.nodeId;
          print(
            '[EditorService] 멘션 삭제 감지: _lastSelection에서 nodeId=$targetNodeId',
          );
        }

        // 방법 2: 현재 selection에서 가져오기
        if (targetNodeId == null) {
          final selection = editor.composer.selectionNotifier.value;
          if (selection != null) {
            targetNodeId = selection.extent.nodeId;
            print(
              '[EditorService] 멘션 삭제 감지: 현재 selection에서 nodeId=$targetNodeId',
            );
          }
        }

        if (targetNodeId != null) {
          final node = document.getNodeById(targetNodeId);

          if (node is ParagraphNode) {
            final isMention = node.metadata['mention'] == true;
            print(
              '[EditorService] 노드 확인: nodeId=$targetNodeId, isParagraph=true, isMention=$isMention, text="${node.text.text}"',
            );

            if (isMention && node.text.text.isNotEmpty) {
              _isClearingMention = true;

              // 삭제 전 텍스트 저장 (로깅용)
              final originalText = node.text.text;

              // usernames 메타데이터에서 첫 번째 멘션 찾기
              final List<dynamic> currentUsernames =
                  (node.metadata['usernames'] as List?) ?? const [];

              if (currentUsernames.isEmpty) {
                // usernames가 없으면 멘션 노드가 아니므로 처리 안 함
                _isClearingMention = false;
                return;
              }

              final firstUsername = currentUsernames[0].toString();
              final mentionPattern = '@$firstUsername';
              final text = node.text.text;

              // 텍스트에서 멘션 패턴 찾기
              final mentionStartIndex = text.indexOf(mentionPattern);

              String newText;
              bool shouldDeleteNode = false;

              if (mentionStartIndex == -1) {
                // 패턴을 찾을 수 없으면 노드 전체 삭제
                shouldDeleteNode = true;
                newText = '';
              } else {
                // 멘션 부분 제거
                final mentionEndIndex =
                    mentionStartIndex + mentionPattern.length;

                // 멘션 앞뒤 텍스트를 합침
                final beforeMention = text.substring(0, mentionStartIndex);
                final afterMention = text.substring(mentionEndIndex);
                newText = (beforeMention + afterMention).trim();

                // 남은 텍스트가 없으면 노드 삭제, 있으면 텍스트만 수정
                if (newText.isEmpty) {
                  shouldDeleteNode = true;
                }
              }

              // IME 위치 매핑 오류 방지: 문서 변경 전에 selection을 먼저 클리어
              try {
                editor.composer.clearSelection();
              } catch (e) {
                print('[EditorService] 멘션 삭제 전 selection 클리어 실패: $e');
              }

              // 문서 변경을 다음 마이크로태스크로 지연하여 IME가 selection 클리어를 처리할 시간을 줌
              final nodeIdForAsync = targetNodeId;
              final nodeIndex = document.getNodeIndexById(nodeIdForAsync);

              Future.microtask(() {
                try {
                  // 문서 변경 전에 플래그 유지
                  final wasClearing = _isClearingMention;
                  _isClearingMention = true;

                  if (shouldDeleteNode) {
                    // 노드 전체 삭제
                    document.deleteNode(nodeIdForAsync);
                  } else {
                    // 멘션 부분만 제거하고 남은 텍스트 유지
                    final currentNode = document.getNodeById(nodeIdForAsync);
                    if (currentNode is ParagraphNode) {
                      // 멘션 메타데이터 제거 (일반 문단으로 변환)
                      final newMetadata = Map<String, dynamic>.from(
                        currentNode.metadata,
                      );
                      newMetadata.remove('mention');
                      newMetadata.remove('usernames');

                      // 원본 텍스트의 attribution 유지하면서 새 텍스트 생성
                      final newAttributedText = AttributedText(newText);

                      // 기존 attribution 중 bold를 제외하고 복사 (필요시)
                      // 여기서는 새 텍스트에만 적용

                      final updatedNode = ParagraphNode(
                        id: currentNode.id,
                        text: newAttributedText,
                        metadata: newMetadata,
                      );

                      document.replaceNodeById(nodeIdForAsync, updatedNode);
                    }
                  }

                  // 플래그 복원
                  _isClearingMention = wasClearing;

                  _isClearingMention = false;

                  // 다음 프레임에서 selection을 설정
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    try {
                      final doc = document;
                      DocumentPosition? position;

                      if (shouldDeleteNode) {
                        // 노드가 삭제되었으면 다음 노드 또는 이전 노드로
                        // 단, 제목 노드(index 0)로는 커서가 가지 않도록 보호
                        if (nodeIndex < doc.nodeCount) {
                          final nextNode = doc.getNodeAt(nodeIndex);
                          // 제목 노드가 아니고 ParagraphNode인 경우만
                          if (nextNode != null &&
                              nextNode is ParagraphNode &&
                              nextNode.metadata['isTitle'] != true) {
                            position = DocumentPosition(
                              nodeId: nextNode.id,
                              nodePosition: const TextNodePosition(offset: 0),
                            );
                          }
                        }

                        // 제목 다음 노드가 없거나 제목이면 빈 문단 생성
                        if (position == null && nodeIndex == 1) {
                          // 제목 바로 밑 노드가 삭제된 경우
                          // 제목 다음에 빈 문단이 없으면 생성
                          if (doc.nodeCount <= 1 ||
                              (doc.nodeCount > 1 &&
                                  doc.getNodeAt(1)?.metadata['isTitle'] ==
                                      true)) {
                            final paragraphId =
                                'p_${DateTime.now().millisecondsSinceEpoch}';
                            final ParagraphNode newParagraph = ParagraphNode(
                              id: paragraphId,
                              text: AttributedText(''),
                              metadata: {'textAlign': 'center'},
                            );
                            doc.insertNodeAt(1, newParagraph);
                            position = DocumentPosition(
                              nodeId: paragraphId,
                              nodePosition: const TextNodePosition(offset: 0),
                            );
                          }
                        }

                        // 이전 노드로 이동 (제목 제외)
                        if (position == null && nodeIndex > 1) {
                          final prevNode = doc.getNodeAt(nodeIndex - 1);
                          if (prevNode != null &&
                              prevNode is ParagraphNode &&
                              prevNode.metadata['isTitle'] != true) {
                            final prevText = prevNode.text.text;
                            position = DocumentPosition(
                              nodeId: prevNode.id,
                              nodePosition: TextNodePosition(
                                offset: prevText.length,
                              ),
                            );
                          }
                        }

                        // 여전히 위치가 없으면 제목 다음에 빈 문단 생성
                        if (position == null && doc.nodeCount >= 1) {
                          final firstNode = doc.getNodeAt(0);
                          if (firstNode != null &&
                              firstNode is ParagraphNode &&
                              firstNode.metadata['isTitle'] == true) {
                            final paragraphId =
                                'p_${DateTime.now().millisecondsSinceEpoch}';
                            final ParagraphNode newParagraph = ParagraphNode(
                              id: paragraphId,
                              text: AttributedText(''),
                              metadata: {'textAlign': 'center'},
                            );
                            doc.insertNodeAt(1, newParagraph);
                            position = DocumentPosition(
                              nodeId: paragraphId,
                              nodePosition: const TextNodePosition(offset: 0),
                            );
                          }
                        }
                      } else {
                        // 노드가 수정되었으면 현재 노드의 멘션 제거된 위치로
                        // 단, 제목 노드가 아닌 경우만
                        final updatedNode = doc.getNodeById(nodeIdForAsync);
                        if (updatedNode is ParagraphNode &&
                            updatedNode.metadata['isTitle'] != true) {
                          // 멘션 패턴 위치 확인 (삭제 후에는 없을 것이므로 텍스트 길이만큼)
                          position = DocumentPosition(
                            nodeId: nodeIdForAsync,
                            nodePosition: TextNodePosition(
                              offset: updatedNode.text.text.length,
                            ),
                          );
                        }
                      }

                      if (position != null) {
                        editor.execute([
                          ChangeSelectionRequest(
                            DocumentSelection.collapsed(position: position),
                            SelectionChangeType.placeCaret,
                            SelectionReason.userInteraction,
                          ),
                        ]);
                      }
                    } catch (e) {
                      print('[EditorService] 멘션 삭제 후 selection 업데이트 실패: $e');
                    }
                  });

                  notifyListeners();
                } catch (e) {
                  print('[EditorService] 멘션 삭제/수정 실패: $e');
                  _isClearingMention = false;
                }
              });

              print(
                '[EditorService] 멘션 처리 완료 - 원본: "$originalText", 삭제 후: "$newText", 노드 삭제: $shouldDeleteNode',
              );
              return; // 이벤트 처리 중단
            }
          }
        } else {
          print('[EditorService] 멘션 삭제 감지: nodeId를 찾을 수 없음');
        }
      } catch (e) {
        _isClearingMention = false;
        print('[EditorService] 멘션 삭제 처리 중 오류: $e');
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
  bool hasNonEmptyBody() {
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
    final bool anyContent = hasNonEmptyTitle() || hasNonEmptyBody();
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

    // 방향에 따라 이미지 순서 결정
    if (isFromLeft) {
      // 왼쪽에서 오는 경우: 드래그 이미지가 왼쪽에
      imageUrls.add(draggingNode.imageUrl);
      imageUrls.add(targetNode.imageUrl);
    } else {
      // 오른쪽에서 오는 경우: 타겟 이미지가 왼쪽에
      imageUrls.add(targetNode.imageUrl);
      imageUrls.add(draggingNode.imageUrl);
    }

    // ImageRowNode 생성 (이미 3개 제한이 적용됨)
    final imageRowNode = ImageRowNode(
      id: 'imageRow_${DateTime.now().millisecondsSinceEpoch}',
      imageUrls: imageUrls,
      spacing: 8.0,
    );

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

    // 새로운 이미지 URL 리스트 생성
    final newImageUrls = List<String>.from(rowNode.imageUrls);

    if (isFromLeft) {
      newImageUrls.insert(0, imageNode.imageUrl);
    } else {
      newImageUrls.add(imageNode.imageUrl);
    }

    // ImageRowNode 업데이트 (이미 3개 제한이 적용됨)
    final updatedRowNode = rowNode.copyWith(imageUrls: newImageUrls);
    document.replaceNodeById(rowId, updatedRowNode);

    // 기존 이미지 삭제
    document.deleteNode(imageId);
    // 문서 구조 변경 → 행 주변만 마진 재계산(O(1))
    final int rowIndex = document.getNodeIndexById(rowId);
    if (rowIndex != -1) {
      //_recomputeParagraphMarginsAround(rowIndex);
    }
    notifyListeners();
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
    try {
      if (usernames.isEmpty) return;

      // 이전 문단 정렬을 승계
      final int caretIndex = _getCaretNodeIndexSafe();
      final String inheritedAlign = _getPreviousParagraphAlign(caretIndex);

      // 각 멘션을 개별 노드로 생성
      int insertIndex = _getCaretNodeIndexSafe();

      // 현재 커서 위치의 다음 줄에 삽입
      if (insertIndex == 0) {
        insertIndex = 1;
      } else {
        // 현재 커서가 있는 문단에 텍스트가 있으면 다음 줄에 삽입
        final currentNode = document.getNodeAt(insertIndex);
        if (currentNode is ParagraphNode &&
            currentNode.text.text.trim().isNotEmpty) {
          insertIndex = insertIndex + 1;
        }
      }

      // 각 username을 개별 노드로 삽입
      for (int i = 0; i < usernames.length; i++) {
        final username = usernames[i];
        final String text = '@$username';
        final String id =
            'p_mention_${DateTime.now().millisecondsSinceEpoch}_$i';

        final AttributedText attributed = AttributedText(text);
        attributed.addAttribution(
          boldAttribution,
          SpanRange(0, text.length - 1),
        );

        final ParagraphNode mentionParagraph = ParagraphNode(
          id: id,
          text: attributed,
          metadata: {
            'textAlign': inheritedAlign,
            'mention': true,
            'usernames': [username], // 각 노드는 하나의 username만 가짐
          },
        );

        // 각 노드를 순서대로 삽입
        final doc = document;
        if (insertIndex > doc.nodeCount) {
          insertIndex = doc.nodeCount;
        }

        final edits = <EditRequest>[
          InsertNodeAtIndexRequest(
            nodeIndex: insertIndex,
            newNode: mentionParagraph,
          ),
        ];

        // 마지막 노드가 문서 끝에 삽입되면 빈 문단 추가
        if (insertIndex == doc.nodeCount) {
          final String paragraphId =
              'p_${DateTime.now().millisecondsSinceEpoch}';
          final ParagraphNode newParagraph = ParagraphNode(
            id: paragraphId,
            text: AttributedText(''),
            metadata: {'textAlign': inheritedAlign},
          );
          edits.add(
            InsertNodeAtIndexRequest(
              nodeIndex: insertIndex + 1,
              newNode: newParagraph,
            ),
          );
        }

        editor.execute(edits);
        insertIndex++; // 다음 노드는 그 다음 위치에 삽입
      }

      notifyListeners();
    } catch (_) {}
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
    );
    final int safeIndex = _getCaretNodeIndexSafe();
    editor.execute([
      InsertNodeAtIndexRequest(nodeIndex: safeIndex, newNode: node),
    ]);
    return id;
  }

  /// Video placeholder를 실제 URL로 교체
  Future<void> replaceVideoPlaceholderWithUrl(String id, String url) async {
    try {
      final existing = editor.document.getNodeById(id);
      if (existing is! ClipNode) return;

      final newNode = ClipNode(
        id: existing.id,
        label: existing.label,
        colorHex: existing.colorHex,
        url: url,
        localPath: '', // placeholder 해제
        thumbnailPath: existing.thumbnailPath, // 썸네일 경로 유지
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
    final int safeIndex = _getCaretNodeIndexSafe();
    final node = ClipNode(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      colorHex: colorHex,
      url: url,
    );
    editor.execute([
      InsertNodeAtIndexRequest(nodeIndex: safeIndex, newNode: node),
    ]);
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
      print("Error finding node at position: $e");
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
  }

  /// 이미지 추가: 현재 커서 다음 줄에 로컬 경로 기반 이미지 노드 삽입
  void addImageNode(String thumbnailImageUrl) {
    try {
      print('이미지 추가: $thumbnailImageUrl');

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
      metadata: {
        'isPlaceholder': true,
        'localPath': localPath,
        'uploadProgress': 0.0,
      },
    );
    _insertComponentNodeAtNextLine(imageNode);
    return id;
  }

  Future<void> replacePlaceholderWithUrl(
    String id,
    String url, {
    String? mediaId,
  }) async {
    try {
      // 기존 노드(localPath)를 기억하여 행 내부 로컬 URL 교체에 활용
      String? localPath;
      try {
        final existing = editor.document.getNodeById(id);
        if (existing is ImageNode) {
          final meta = (existing as dynamic).metadata as Map<String, dynamic>?;
          localPath = meta != null ? (meta['localPath']?.toString()) : null;
        }
      } catch (_) {}
      // 0) 네트워크 이미지 미리 로드하여 교체 시 깜빡임 제거
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
      try {
        stream.removeListener(listener);
      } catch (_) {}

      // 1) iOS 핸들 NPE 방지: 교체 중 selection 비우기
      final prevSelection = editor.composer.selectionNotifier.value;
      try {
        editor.composer.clearSelection();
      } catch (_) {}

      // 2) 동일 id로 교체
      final newNode = AppImageNode(
        id: id,
        imageUrl: url,
        altText: '',
        metadata: {
          'isPlaceholder': false,
          if (mediaId != null && mediaId.isNotEmpty) 'mediaId': mediaId,
        },
      );
      editor.execute([
        ReplaceNodeRequest(existingNodeId: id, newNode: newNode),
      ]);

      // 업로드 성공 URL ↔ imageId 매핑을 등록할 수 있게끔 업로드 흐름에서 호출할 API 제공
      // (이 메서드에서는 URL만 교체하고, ID는 업로드 서비스 쪽에서 NodeComponentService에 등록)

      // ImageRowNode들 중 로컬 경로(file:// 또는 localPath) 포함된 URL을 신규 네트워크 URL로 교체
      try {
        for (int i = 0; i < editor.document.length; i++) {
          final n = editor.document.getNodeAt(i);
          if (n is ImageRowNode) {
            final urls = List<String>.from(n.imageUrls);
            bool changed = false;
            for (int k = 0; k < urls.length; k++) {
              final u = urls[k];
              if ((localPath != null && u == localPath) ||
                  u.startsWith('file://')) {
                urls[k] = url;
                changed = true;
              }
            }
            if (changed) {
              final updated = n.copyWith(imageUrls: urls);
              editor.document.replaceNodeById(n.id, updated);
            }
          }
        }
      } catch (_) {}

      // 3) 다음 프레임에서 selection 복원
      if (prevSelection != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            editor.execute([
              ChangeSelectionRequest(
                prevSelection,
                SelectionChangeType.placeCaret,
                SelectionReason.userInteraction,
              ),
            ]);
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('replacePlaceholderWithUrl failed: $e');
    }
  }

  void deleteImagePlaceholderNode(String id) {
    try {
      document.deleteNode(id);
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
    print('DEBUG: _insertComponentNodeAtNextLine: $componentNode');
    final doc = editor.document;
    final safeIndex = _getCaretNodeIndexSafe();
    int insertIndex = safeIndex;

    // 제목 노드(index 0)에 커서가 있으면 강제로 다음 라인에 삽입
    if (insertIndex == 0) {
      insertIndex = 1;
      print('🎯 제목 노드에 커서가 있음, 다음 라인(index 1)에 삽입');

      // 제목 다음에 빈 문단이 없으면 먼저 생성
      if (doc.nodeCount < 2) {
        final paragraphId = 'p_${DateTime.now().millisecondsSinceEpoch}';
        final ParagraphNode newParagraph = ParagraphNode(
          id: paragraphId,
          text: AttributedText(''),
          metadata: {'textAlign': 'center'},
        );
        doc.insertNodeAt(1, newParagraph);
        print('📝 제목 다음에 빈 문단 생성');
      }
    } else {
      // 현재 커서가 있는 문단에 텍스트가 있으면 다음 줄에 삽입
      if (insertIndex < doc.nodeCount) {
        final currentNode = doc.getNodeAt(insertIndex);
        if (currentNode is ParagraphNode) {
          final hasText = currentNode.text.text.trim().isNotEmpty;
          if (hasText) {
            insertIndex = insertIndex + 1;
            print('🎯 현재 문단에 텍스트가 있음, 다음 줄(index $insertIndex)에 삽입');
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
  }

  /// insertIndex 이전의 가장 가까운 문단 정렬을 찾아 반환. 기본값은 'center'
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
