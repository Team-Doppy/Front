import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/custom_nodes/image_row_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_editor/super_editor.dart';

class EditorService extends ChangeNotifier {
  late final Editor editor;
  late final MutableDocument document;
  GlobalKey? _documentLayoutKey;

  // 문단별 마진 캐시 (중앙집중 판정 결과)
  final Map<String, EdgeInsets> _paragraphMargins = <String, EdgeInsets>{};
  String? _lastStructureSignature;
  bool _lastPublishable = false;

  EditorService({required this.editor, required this.document}) {
    // 초기 문서 상태 기준으로 문단 마진을 계산
    recomputeParagraphMargins();
    // 초기 구조 시그니처 저장 및 변경 리스너 등록
    _lastStructureSignature = _computeStructureSignature();
    _lastPublishable = canPublish;
    document.addListener(_onDocumentChanged);
  }

  void setDocumentLayoutKey(GlobalKey key) {
    _documentLayoutKey = key;
  }

  GlobalKey? get documentLayoutKey => _documentLayoutKey;

  // 문서 구조(노드 타입/순서) 시그니처 계산: 텍스트 입력만으로는 변하지 않게 설계
  String _computeStructureSignature() {
    final buffer = StringBuffer();
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node == null) continue;
      final type = getNodeType(node.id);
      switch (type) {
        case NodeType.paragraph:
          buffer.write('P|');
          break;
        case NodeType.image:
          buffer.write('I|');
          break;
        case NodeType.imageRow:
          buffer.write('R|');
          break;
        case NodeType.unknown:
          buffer.write('U|');
          break;
      }
    }
    return buffer.toString();
  }

  // 문서 변경 리스너: 구조가 변했을 때만 마진 재계산
  void _onDocumentChanged(DocumentChangeLog changeLog) {
    // 제목 노드가 항상 존재하고 맨 위에 있도록 보정
    final bool titleFixed = _ensureTitleAtTop();

    final signature = _computeStructureSignature();
    bool structureChanged = false;
    if (signature != _lastStructureSignature) {
      _lastStructureSignature = signature;
      structureChanged = true;
      // 구조 변경 시에만 마진 재계산
      recomputeParagraphMargins();
    }

    // 새로 생성된 문단이 있으면 이전 문단의 정렬을 승계하도록 정렬 메타데이터 보정
    final bool alignmentFixed = _ensureParagraphAlignmentDefaults();

    // 게시 가능 여부가 바뀌었는지 확인 (텍스트 입력 같은 구조 비변경도 감지)
    final currentPublishable = canPublish;
    final publishableChanged = currentPublishable != _lastPublishable;
    _lastPublishable = currentPublishable;

    if (structureChanged ||
        publishableChanged ||
        alignmentFixed ||
        titleFixed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    try {
      document.removeListener(_onDocumentChanged);
    } catch (_) {}
    super.dispose();
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
    // 문서 구조 변경 → 문단 마진 재계산
    recomputeParagraphMargins();
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
    // 문서 구조 변경 → 문단 마진 재계산
    recomputeParagraphMargins();
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
    // 문서 구조 변경 → 문단 마진 재계산
    recomputeParagraphMargins();
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
    final newImageNode = ImageNode(id: newImageId, imageUrl: imageUrl);

    // 이미지 행에서 해당 이미지 제거
    final remainingUrls = List<String>.from(rowNode.imageUrls);
    remainingUrls.removeAt(imageIndex);

    if (remainingUrls.length == 1) {
      // 이미지가 1개만 남으면 단일 이미지로 변경
      final singleImageNode = ImageNode(
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
    // 문서 구조 변경 → 문단 마진 재계산
    recomputeParagraphMargins();
    notifyListeners();

    return newImageId;
  }

  // ===== 중앙집중 텍스트 마진 판정 =====
  static const double _baseTopMarginPx = 2.0;
  static const double _imageTextMarginPx = 16.0;

  bool _isImageType(NodeType? t) =>
      t == NodeType.image || t == NodeType.imageRow;

  /// 현재 문서 스냅샷을 순회하며 모든 Paragraph에 대해
  /// 이미지와 이웃한 쪽에만 마진을 주는 규칙을 계산한다.
  void recomputeParagraphMargins() {
    _paragraphMargins.clear();

    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is! ParagraphNode) continue;

      // 이전/다음 노드의 타입 확인
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

      final EdgeInsets margin = EdgeInsets.only(
        top: addTop ? _imageTextMarginPx : _baseTopMarginPx,
        bottom: addBottom ? _imageTextMarginPx : 0,
      );

      _paragraphMargins[node.id] = margin;
    }
  }

  /// 외부에서 문단의 마진을 조회
  EdgeInsets getParagraphMargin(String nodeId) {
    return _paragraphMargins[nodeId] ??
        const EdgeInsets.only(top: _baseTopMarginPx);
  }

  // ===== 게시 가능 여부 판정 =====
  bool hasNonEmptyTitle() {
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode && (node.metadata['isTitle'] == true)) {
        // ignore: deprecated_member_use
        final text = node.text.text.trim();
        return text.isNotEmpty;
      }
    }
    return false;
  }

  bool hasNonEmptyContent() {
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode && (node.metadata['isTitle'] == true)) {
        // 타이틀은 제외
        continue;
      }
      if (node is ParagraphNode) {
        // ignore: deprecated_member_use
        if (node.text.text.trim().isNotEmpty) {
          return true;
        }
      } else if (node is ImageNode || node is ImageRowNode) {
        return true;
      }
    }
    return false;
  }

  bool get canPublish => hasNonEmptyTitle() && hasNonEmptyContent();

  // ===== 정렬 승계 보정 =====
  // 새 ParagraphNode가 생성될 때 metadata['textAlign']이 비어 있으면
  // 바로 이전 Paragraph의 정렬을 승계한다. (없으면 'left')
  bool _ensureParagraphAlignmentDefaults() {
    bool updated = false;
    String previousAlign = 'left';

    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode) {
        final Map<String, dynamic> meta = Map<String, dynamic>.from(
          node.metadata,
        );
        final String? align = meta['textAlign'] as String?;
        if (align == null) {
          // 이전 문단 정렬 승계
          meta['textAlign'] = previousAlign;
          final replaced = ParagraphNode(
            id: node.id,
            text: node.text,
            metadata: meta,
          );
          document.replaceNodeById(node.id, replaced);
          updated = true;
        } else {
          previousAlign = align;
        }
      }
    }

    return updated;
  }

  // 제목 문단이 항상 존재하고 맨 위(index 0)에 있도록 보정한다.
  // 변경이 있었으면 true를 반환한다.
  bool _ensureTitleAtTop() {
    int titleIndex = -1;
    ParagraphNode? titleNode;
    for (int i = 0; i < document.length; i++) {
      final node = document.getNodeAt(i);
      if (node is ParagraphNode && (node.metadata['isTitle'] == true)) {
        titleIndex = i;
        titleNode = node;
        break;
      }
    }

    // 없으면 생성
    if (titleIndex == -1) {
      final ParagraphNode newTitle = ParagraphNode(
        id: 'title_${DateTime.now().millisecondsSinceEpoch}',
        text: AttributedText(''),
        metadata: {'isTitle': true},
      );
      document.insertNodeAt(0, newTitle);
      return true;
    }

    // 맨 위가 아니면 이동
    if (titleIndex != 0 && titleNode != null) {
      document.deleteNode(titleNode.id);
      document.insertNodeAt(0, titleNode);
      return true;
    }
    return false;
  }
}
