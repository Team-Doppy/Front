import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/editor_service.dart';

/// 패키지 기본 ParagraphComponent를 사용하고,
/// 드래그 드롭 라인만 오버레이로 추가하는 경량 커스텀 빌더
class CustomParagraphComponentBuilder implements ComponentBuilder {
  const CustomParagraphComponentBuilder({
    required this.dragService,
    required this.editorService,
  });

  final DragService dragService;
  final EditorService editorService;
  static const ParagraphComponentBuilder _defaultBuilder =
      ParagraphComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    // 기본 빌더에 위임 (패키지 ParagraphNode만 대상)
    final result = _defaultBuilder.createViewModel(document, node);
    return result;
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    // 기본 컴포넌트 생성
    final child = _defaultBuilder.createComponent(
      componentContext,
      componentViewModel,
    );
    if (child == null) return null;

    // 문단이 아닌 경우 래핑 불필요
    if (componentViewModel is! ParagraphComponentViewModel) return child;

    // 드래그 라인만 덧씌우는 얇은 래퍼
    return _ParagraphWithDropLines(
      nodeId: componentViewModel.nodeId,
      dragService: dragService,
      editorService: editorService,
      child: child,
    );
  }
}

class _ParagraphWithDropLines extends StatelessWidget {
  const _ParagraphWithDropLines({
    required this.nodeId,
    required this.dragService,
    required this.editorService,
    required this.child,
  });

  final String nodeId;
  final DragService dragService;
  final EditorService editorService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([dragService, editorService]),
      builder: (context, _) {
        final currentIndex = dragService.getNodeIndex(nodeId);
        final dropIndex = dragService.dropIndex;
        final isSelf = dragService.draggingNodeId == nodeId;
        final showTop =
            dropIndex != null &&
            !isSelf &&
            currentIndex != -1 &&
            dropIndex == currentIndex;

        // 중앙집중 규칙에 따른 텍스트 마진 적용
        final EdgeInsets margin = editorService.getParagraphMargin(nodeId);

        return Stack(
          children: [
            Padding(
              padding: margin,
              child: Builder(
                builder: (context) {
                  // ParagraphNode의 metadata에서 정렬 정보를 읽어 적용
                  TextAlign resolvedAlign = TextAlign.left;
                  try {
                    final node = editorService.editor.document.getNodeById(
                      nodeId,
                    );
                    if (node is ParagraphNode) {
                      final alignName = node.metadata['textAlign'] as String?;
                      if (alignName == 'center') {
                        resolvedAlign = TextAlign.center;
                      } else if (alignName == 'right') {
                        resolvedAlign = TextAlign.right;
                      } else if (alignName == 'left') {
                        resolvedAlign = TextAlign.left;
                      }
                    }
                  } catch (_) {}

                  return DefaultTextStyle.merge(
                    textAlign: resolvedAlign,
                    child: child,
                  );
                },
              ),
            ),
            if (showTop)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 3, color: const Color(0xFF007AFF)),
              ),
            // 하단 라인 비활성화(이중 라인 방지)
          ],
        );
      },
    );
  }
}
