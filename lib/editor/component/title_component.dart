import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/editor_service.dart';

/// 제목 전용 문단 빌더: metadata['isTitle'] == true 인 문단만 처리하고,
/// 기본 Paragraph 컴포넌트를 그대로 렌더링(스타일은 Stylesheet에서 적용), 드롭 라인은 표시하지 않음.
class TitleParagraphComponentBuilder implements ComponentBuilder {
  const TitleParagraphComponentBuilder({required this.editorService});

  final EditorService editorService;
  static const ParagraphComponentBuilder _defaultBuilder =
      ParagraphComponentBuilder();

  bool _isTitleNode(String nodeId) {
    final node = editorService.editor.document.getNodeById(nodeId);
    return node is ParagraphNode && (node.metadata['isTitle'] == true);
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is ParagraphNode && (node.metadata['isTitle'] == true)) {
      return _defaultBuilder.createViewModel(document, node);
    }
    return null; // 타이틀이 아닌 문단은 내가 처리하지 않음
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! ParagraphComponentViewModel) return null;

    // 타이틀 문단만 처리
    if (!_isTitleNode(componentViewModel.nodeId)) return null;

    // 기본 Paragraph 컴포넌트 생성(스타일은 stylesheet에서 isTitle로 적용됨)
    final child = _defaultBuilder.createComponent(
      componentContext,
      componentViewModel,
    );
    if (child == null) return null;

    // 타이틀은 드롭 라인 등 오버레이 없이 그대로 렌더 + 비어있을 때 힌트 위젯 표시
    final node = editorService.editor.document.getNodeById(
      componentViewModel.nodeId,
    );
    // ignore: deprecated_member_use
    final String text = node is ParagraphNode ? node.text.text : '';
    final bool isEmpty = text.trim().isEmpty;

    // 정렬 메타데이터 반영
    TextAlign resolvedAlign = TextAlign.left;
    Alignment overlayAlign = Alignment.centerLeft;
    if (node is ParagraphNode) {
      final alignName = node.metadata['textAlign'] as String?;
      if (alignName == 'center') {
        resolvedAlign = TextAlign.center;
        overlayAlign = Alignment.center;
      } else if (alignName == 'right') {
        resolvedAlign = TextAlign.right;
        overlayAlign = Alignment.centerRight;
      } else if (alignName == 'left') {
        resolvedAlign = TextAlign.left;
        overlayAlign = Alignment.centerLeft;
      }
    }

    return Stack(
      children: [
        DefaultTextStyle.merge(textAlign: resolvedAlign, child: child),
        if (isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Align(
                alignment: overlayAlign,
                child: Padding(
                  padding: const EdgeInsets.only(top: 0),
                  child: Builder(
                    builder:
                        (context) => Text(
                          context.tr('enter_title'),
                          textAlign: resolvedAlign,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w500,
                            color: AppColors.darkTextSecondary,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
