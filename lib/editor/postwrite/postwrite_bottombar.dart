import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import '../../editor/service/editor_service.dart';
import '../../editor/service/node_component_service.dart';
import '../../editor/style/text_styling_service.dart';
import '../../editor/toolbar/selected_toolbar.dart';
import '../../editor/toolbar/defualt_toolbar.dart';

class PostwriteBottomBar extends StatelessWidget {
  final ValueNotifier<bool> keyboardVisibleNotifier;
  final TextStylingService textStylingService;
  final EditorService editorService;
  final ScrollController scrollController;
  final VoidCallback onDismissKeyboard;
  final VoidCallback onShowDraftList;
  final NodeComponentService nodeComponentService;
  final Document document;
  final void Function(String selectedId, DocumentNode node) onEditImage;
  final void Function(DocumentNode node, String selectedId) onDeleteNode;
  final Future<void> Function(DocumentNode node, String selectedId)
  onChangeMediaAlignment;
  final ValueNotifier<bool>? videoUploadIndicatorNotifier;

  const PostwriteBottomBar({
    super.key,
    required this.keyboardVisibleNotifier,
    required this.textStylingService,
    required this.editorService,
    required this.scrollController,
    required this.onDismissKeyboard,
    required this.onShowDraftList,
    required this.nodeComponentService,
    required this.document,
    required this.onEditImage,
    required this.onDeleteNode,
    required this.onChangeMediaAlignment,
    this.videoUploadIndicatorNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = keyboardHeight > safeBottom
        ? keyboardHeight
        : safeBottom;
    final theme = Theme.of(context);

    final Widget bar = Container(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: ListenableBuilder(
          listenable: nodeComponentService,
          builder: (context, _) {
            final selectedId = nodeComponentService.selectedNodeId;
            final Widget toolbar;
            if (selectedId != null) {
              final node = document.getNodeById(selectedId);
              if (node == null) return const SizedBox.shrink();
              toolbar = SelectedToolbar(
                key: const ValueKey('selected_toolbar'),
                node: node,
                selectedId: selectedId,
                onEdit: () => onEditImage(selectedId, node),
                onDelete: onDeleteNode,
                onChangeAlignment: onChangeMediaAlignment,
                editorService: editorService,
              );
            } else {
              toolbar = DefaultToolbar(
                key: const ValueKey('default_toolbar'),
                editorService: editorService,
                onShowDraftList: onShowDraftList,
                scrollController: scrollController,
                stylingService: textStylingService,
                onDismissKeyboard: onDismissKeyboard,
                keyboardVisibleNotifier: keyboardVisibleNotifier,
                videoUploadIndicatorNotifier: videoUploadIndicatorNotifier,
              );
            }

            return AnimatedSwitcher(
              duration: Duration.zero,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: toolbar,
            );
          },
        ),
      ),
    );

    return bar;
  }
}
