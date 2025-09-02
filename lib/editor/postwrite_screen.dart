import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/style/placeholder_styler.dart';
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
            customStylePhases: [PlaceholderStyler(dragService: dragService)],
            componentBuilders: [
              NodeComponentBuilder(
                editorService: editorService,
                editor: editor,
                dragService: dragService,
              ),
            ],
          ),

          // 드래그 미리보기 (Overlay 대체)
          Builder(
            builder: (_) {
              final pos = dragService.dragPosition;
              if (dragService.draggingNodeId == null || pos == null) {
                return const SizedBox.shrink();
              }
              return Positioned(
                left: pos.dx,
                top: pos.dy,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.blue.withAlpha(80),
                  child: Text("Dragging ${dragService.draggingNodeId}"),
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
    // placeholder
    if (componentViewModel is PlaceholderViewModel) {
      return SizedBox(
        key: componentContext.componentKey,
        width: double.infinity,
        height: 10,
        child: const ColoredBox(color: Color.fromARGB(255, 0, 191, 255)),
      );
    }

    // node/image
    final key = componentContext.componentKey;
    final node = editor.document.getNodeById(componentViewModel.nodeId);
    if (node == null) return const SizedBox.shrink();

    editorService.nodeKeys[node.id] = key;

    if (node is ParagraphNode) {
      return GestureDetector(
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
        child: Container(
          key: key,
          child: Text(node.text.text, style: const TextStyle(fontSize: 16)),
        ),
      );
    } else if (node is ImageNode) {
      return GestureDetector(
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
        child: Container(
          key: key,
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

    return const SizedBox.shrink();
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
