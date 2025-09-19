import 'dart:async';
import 'package:doppy/editor/component/app_image_node.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:doppy/editor/component/mention_component.dart';
import 'package:doppy/editor/component/location_component.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

class EditorService extends ChangeNotifier {
  late final Editor editor;
  late final MutableDocument document;
  GlobalKey? _documentLayoutKey;
  // 마지막 유효 selection 캐시 (포커스가 잠시 사라져도 사용)
  DocumentSelection? _lastSelection;

  bool publishable = false;

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

      return;
    }

    if (change is NodeMovedEvent) {
      // 이동 전/후 주변만 마진 재계산
      //_recomputeParagraphMarginsAround(change.from);
      //_recomputeParagraphMarginsAround(change.to);
      _ensureOnlyFirstIsTitle();

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

      return;
    }

    if (changeLog.changes[0] is TextInsertionEvent ||
        changeLog.changes[0] is TextDeletedEvent) {
      if (getEditingIndex() == 0) {
        publishable = hasNonEmptyTitle();
        notifyListeners();
        return;
      }
      _ensureOnlyFirstIsTitle();

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
      case LocationNode():
        return NodeType.location;
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

  /// 언급 노드를 현재 커서 다음 슬롯에 삽입
  void addMentionNode(List<String> usernames) {
    final node = MentionNode(
      id: 'mention_${DateTime.now().millisecondsSinceEpoch}',
      usernames: usernames,
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

  /// 변경 지점 주변(상/하/본인)만 부분적으로 마진 재계산 (public)
  void recomputeParagraphMarginsAround(int centerIndex) {
    //_recomputeParagraphMarginsAround(centerIndex);
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
    // 로컬 파일 경로를 바로 imageUrl에 넣어 미리보기로 사용
    final imageNode = AppImageNode(
      id: id,
      imageUrl: localPath.startsWith('file://') ? localPath : localPath,
      altText: '',
      metadata: {'isPlaceholder': true, 'localPath': localPath},
    );
    _insertComponentNodeAtNextLine(imageNode);
    return id;
  }

  Future<void> replacePlaceholderWithUrl(String id, String url) async {
    try {
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
        metadata: {'isPlaceholder': false},
      );
      editor.execute([
        ReplaceNodeRequest(existingNodeId: id, newNode: newNode),
      ]);

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

  // selection이 null이거나 nodeId를 찾지 못해도 문서 끝을 반환하여 안전
  int _getCaretNodeIndexSafe() {
    final doc = editor.document;
    final sel = editor.composer.selectionNotifier.value ?? _lastSelection;
    if (sel == null) return doc.nodeCount;
    final idx = doc.getNodeIndexById(sel.extent.nodeId);
    return idx == -1 ? doc.nodeCount : idx;
  }

  /// 공통 삽입 유틸: 현재 커서의 다음 줄에 컴포넌트 노드를 삽입한다.
  /// 만약 삽입 지점이 문서의 마지막(끝)이면, 그 아래에 빈 문단을 추가하고
  /// 커서를 그 빈 문단 앞으로 이동한다.
  void _insertComponentNodeAtNextLine(DocumentNode componentNode) {
    final doc = editor.document;
    final safeIndex = _getCaretNodeIndexSafe();
    int insertIndex = safeIndex + 1;
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

  /*
  // 변경 지점 주변(상/하/본인)만 부분적으로 마진 재계산
  void _recomputeParagraphMarginsAround(int centerIndex) {
    for (final i in <int>[centerIndex - 1, centerIndex, centerIndex + 1]) {
      if (i < 0 || i >= document.length) continue;
      final node = document.getNodeAt(i);
      if (node is! ParagraphNode) continue;

      NodeType? prevType;
      NodeType? nextType;
      if (i > 0) {
        final prev = document.getNodeAt(i - 1);
        if (prev != null) prevType = getNodeType(prev.id);
      }
      if (i < document.length - 1) {
        final next = document.getNodeAt(i + 1);
        if (next != null) nextType = getNodeType(next.id);
      }

      final bool addTop = _isImageType(prevType);
      final bool addBottom = _isImageType(nextType);
      _paragraphMargins[node.id] = EdgeInsets.only(
        top: addTop ? _imageTextMarginPx : _baseTopMarginPx,
        bottom: addBottom ? _imageTextMarginPx : 0,
      );
    }
  }
  */

  // ===== 게시 가능 여부 판정 =====
  bool hasNonEmptyTitle() {
    final node = document.getNodeAt(0);
    if (node is ParagraphNode && (node.metadata['isTitle'] == true)) {
      final text = node.text.text.trim();
      return text.isNotEmpty;
    }
    return false;
  }

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

  /// 위치 노드를 현재 커서 위치에 삽입합니다
  void addLocationNode({
    required double lat,
    required double lng,
    String title = '',
    String address = '',
    String description = '',
  }) {
    final node = LocationNode(
      id: 'location_${DateTime.now().millisecondsSinceEpoch}',
      lat: lat,
      lng: lng,
      title: title,
      address: address,
      description: description,
    );
    _insertComponentNodeAtNextLine(node);
  }
}
