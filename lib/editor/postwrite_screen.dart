import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 글 공개 범위 옵션
enum VisibilityOption { public, partial, private }

enum NodeType { paragraph, image, unknown }

class PostwriteScreen extends StatefulWidget {
  final double screenWidth;
  const PostwriteScreen({super.key, required this.screenWidth});

  @override
  State<PostwriteScreen> createState() => _PostwriteScreenState();
}

class _PostwriteScreenState extends State<PostwriteScreen> {
  late final Editor editor;
  late final MutableDocument document;
  late final MutableDocumentComposer composer;

  //service
  late final EditorService editorService;
  late final DragService dragService;

  OverlayEntry? overlayEntry;
  GlobalKey overlayKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    document = MutableDocument(
      nodes: [
        ParagraphNode(id: '1', text: AttributedText('Hello, World1!   ')),
        ParagraphNode(id: '2', text: AttributedText('Hello, World2!')),
      ],
    );
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    editorService = EditorService(editor: editor);
    dragService = DragService(editorService: editorService);
    dragService.addListener(_onDragChange);
  }

  @override
  void dispose() {
    super.dispose();
    editorService.dispose();
    dragService.removeListener(_onDragChange);
  }

  // 드래그 프리뷰 렌더링을 위한 리스너
  void _onDragChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: [
          SuperEditor(
            gestureMode: DocumentGestureMode.iOS,
            editor: editor,
            componentBuilders: [
              NodeComponentBuilder(
                editorService: editorService,
                editor: editor,
                dragService: dragService,
              ),
            ],
          ),

          // 드래그 미리보기
          Builder(
            builder: (context) {
              final pos = dragService.dragPosition;
              if (dragService.draggingNodeId == null || pos == null) {
                return const SizedBox.shrink();
              }

              return Positioned(
                left: pos.dx - 50,
                top: pos.dy - 120,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(200),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(50),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    "Dragging ${dragService.draggingNodeId}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class NodeComponentBuilder extends ComponentBuilder {
  final EditorService editorService;
  final Editor editor;
  final DragService dragService;

  NodeComponentBuilder({
    required this.editorService,
    required this.editor,
    required this.dragService,
  });

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    final key = componentContext.componentKey;
    final node = editor.document.getNodeById(componentViewModel.nodeId);
    if (node == null) return const SizedBox.shrink();

    editorService.nodeKeys[node.id] = key;

    // 기본 컴포넌트 빌드
    final component = _buildNodeComponent(node, key, componentContext);
    if (component == null) return const SizedBox.shrink();

    // 드래그 상태 확인 (직접 접근)
    final dropIndex = dragService.dropIndex;
    final draggingId = dragService.draggingNodeId;

    // 드래그 중이 아니면 일반 컴포넌트 반환
    if (draggingId == null || dropIndex == null) {
      return component;
    }

    // 현재 노드의 인덱스 계산
    final nodeIndex = _getNodeIndex(node.id);

    // 플레이스홀더 표시 조건 확인
    final totalNodes = editor.document.length;
    final shouldShowPlaceholderBefore = dropIndex == nodeIndex;
    final shouldShowPlaceholderAfter =
        dropIndex == totalNodes && nodeIndex == totalNodes - 1;

    if (shouldShowPlaceholderBefore || shouldShowPlaceholderAfter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬 유지
        children:
            shouldShowPlaceholderBefore
                ? [_buildPlaceholder(), component]
                : [component, _buildPlaceholder()],
      );
    }

    return component;
  }

  int _getNodeIndex(String nodeId) {
    int index = 0;
    for (final node in editor.document) {
      if (node.id == nodeId) return index;
      index++;
    }
    return -1;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: 2, // 얇은 플레이스홀더
      margin: const EdgeInsets.symmetric(vertical: 1),
      color: const Color.fromARGB(255, 0, 191, 255),
    );
  }

  Widget? _buildNodeComponent(
    DocumentNode node,
    GlobalKey key,
    SingleColumnDocumentComponentContext componentContext,
  ) {
    if (node is ParagraphNode) {
      return Container(
        key: key,
        child: GestureDetector(
          onLongPressStart:
              (details) => dragService.startDrag(
                node.id,
                componentContext.context,
                details.globalPosition,
              ),
          onLongPressMoveUpdate:
              (details) => dragService.updateDrag(
                details.globalPosition,
                componentContext.context,
              ),
          onLongPressEnd: (_) => dragService.endDrag(),
          child: Text(node.text.text, style: const TextStyle(fontSize: 16)),
        ),
      );
    } else if (node is ImageNode) {
      return Container(
        key: key,
        child: GestureDetector(
          onLongPressStart:
              (details) => dragService.startDrag(
                node.id,
                componentContext.context,
                details.globalPosition,
              ),
          onLongPressMoveUpdate:
              (details) => dragService.updateDrag(
                details.globalPosition,
                componentContext.context,
              ),
          onLongPressEnd: (_) => dragService.endDrag(),
          child: Image.network(
            node.imageUrl,
            fit: BoxFit.cover,
            errorBuilder:
                (context, error, stackTrace) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.image),
                ),
          ),
        ),
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is ParagraphNode || node is ImageNode) {
      return _SimpleComponentViewModel(
        nodeId: node.id,
        createdAt: DateTime.now(),
        padding: EdgeInsets.zero,
      );
    }
    return null;
  }
}

// 간단한 ViewModel 구현
class _SimpleComponentViewModel extends SingleColumnLayoutComponentViewModel {
  _SimpleComponentViewModel({
    required super.nodeId,
    required super.createdAt,
    required super.padding,
  });

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return _SimpleComponentViewModel(
      nodeId: nodeId,
      createdAt: createdAt,
      padding: padding,
    );
  }
}
