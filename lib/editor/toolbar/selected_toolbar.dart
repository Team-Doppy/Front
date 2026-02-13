import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:provider/provider.dart';
import '../component/clip_component.dart';
import '../component/link_component.dart';
import '../service/node_component_service.dart';
import '../component/row_image_component.dart';
import '../component/pageview_image_component.dart';
import '../service/editor_service.dart';
import '../component/app_image_node.dart';
import 'toolbar_components.dart';

class SelectedToolbar extends StatefulWidget {
  const SelectedToolbar({
    super.key,
    required this.selectedId,
    required this.node,
    required this.onEdit,
    required this.onDelete,
    this.onChangeAlignment,
    this.onEditMention,
    this.editorService,
  });

  final String? selectedId;
  final DocumentNode? node;
  final VoidCallback onEdit;
  final void Function(DocumentNode node, String selectedId) onDelete;
  final Future<void> Function(DocumentNode node, String selectedId)?
  onChangeAlignment;
  final void Function(String nodeId, List<String> usernames)? onEditMention;
  final EditorService? editorService;

  @override
  State<SelectedToolbar> createState() => _SelectedToolbarState();
}

class _SelectedToolbarState extends State<SelectedToolbar> {
  bool _mentionFontSizePanelOpen = false;

  @override
  Widget build(BuildContext context) {
    if (widget.node == null || widget.selectedId == null)
      return const SizedBox.shrink();

    // ✅ 중요: selectedId는 그대로인 채 node metadata만 바뀌는 경우가 많다.
    // (ReplaceNodeRequest로 같은 id의 노드가 교체됨)
    // 이때 부모는 selectedId 기준 Selector로만 리빌드되므로 widget.node가 stale일 수 있다.
    // 따라서 매 build마다 문서에서 최신 노드를 다시 가져와서 UI/아이콘 상태를 정확히 반영한다.
    final editorService = widget.editorService;
    final currentNode =
        editorService?.document.getNodeById(widget.selectedId!) ?? widget.node!;

    // 이미지 스포일러 적용 여부 (Provider 인스턴스 사용)
    bool isImageSpoiler = false;
    if (currentNode is ImageNode || currentNode is ImageRowNode) {
      try {
        final nodeService = context.read<NodeComponentService>();
        Map<String, dynamic>? meta;
        if (currentNode is ImageNode) {
          meta = (currentNode as dynamic).metadata as Map<String, dynamic>?;
        } else if (currentNode is ImageRowNode) {
          meta = currentNode.metadata;
        }
        isImageSpoiler = nodeService.shouldShowImageSpoiler(
          widget.selectedId ?? '',
          meta,
        );
      } catch (_) {}
    }

    // 현재 노드의 padding 상태 확인
    bool isExpanded = false;
    if (currentNode is ImageNode) {
      final meta = (currentNode as dynamic).metadata as Map<String, dynamic>?;
      isExpanded = meta?['padding'] == 'full';
    } else if (currentNode is ImageRowNode) {
      final meta = currentNode.metadata;
      isExpanded = meta['padding'] == 'full';
    } else if (currentNode is ClipNode) {
      final meta = currentNode.metadata;
      isExpanded = meta['padding'] == 'full';
    } else if (currentNode is LinkNode) {
      final meta = currentNode.metadata;
      isExpanded = meta['padding'] == 'full';
    }

    // 링크 표시 모드: full(default) / compact
    bool isCompactLink = false;
    if (currentNode is LinkNode) {
      final meta = currentNode.metadata;
      isCompactLink = meta['viewMode'] == 'compact';
    }
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),

      child: Row(
        children: [
          const SizedBox(width: 8),
          // 멘션 폰트 사이즈 패널이 펼쳐져 있을 때는 Spacer 제거 (리스트가 왼쪽 끝까지 확장)
          if (!(widget.onEditMention != null && _mentionFontSizePanelOpen))
            const Spacer(),
          if (currentNode is ImageNode || currentNode is ImageRowNode) ...[
            // 스포일러 토글
            if (widget.node is ImageNode || widget.node is ImageRowNode)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ToolbarToggleIcon(
                  svgPath: 'assets/icons/spoiler.svg',
                  isActive: isImageSpoiler,
                  onTap: () {
                    if (widget.selectedId != null) {
                      final newSpoilerValue = !isImageSpoiler;
                      final nodeId = widget.selectedId!;
                      final nodeSvc = context.read<NodeComponentService>();

                      // 문서의 metadata 업데이트 (undo/redo 포함 복원 시 스포일러 상태 유지)
                      try {
                        // 🎯 prop으로 전달받은 editorService 우선 사용, 없으면 Provider로 접근
                        final editorService =
                            widget.editorService ??
                            context.read<EditorService>();
                        final node = editorService.document.getNodeById(nodeId);

                        if (node is ImageNode) {
                          final meta = Map<String, dynamic>.from(
                            (node as dynamic).metadata
                                    as Map<String, dynamic>? ??
                                {},
                          );
                          if (newSpoilerValue) {
                            meta['spoiler'] = true;
                          } else {
                            meta.remove('spoiler');
                          }

                          final updatedNode = AppImageNode(
                            id: nodeId,
                            imageUrl: (node as dynamic).imageUrl as String,
                            altText: node.altText,
                            metadata: meta,
                          );

                          editorService.editor.execute([
                            ReplaceNodeRequest(
                              existingNodeId: nodeId,
                              newNode: updatedNode,
                            ),
                          ]);
                          // 🎯 Provider 인스턴스의 캐시 갱신 + notifyListeners → SingleImageComponent 리빌드
                          nodeSvc.setSpoiler(nodeId, newSpoilerValue);
                          editorService.saveHistoryNow();
                        } else if (node is ImageRowNode) {
                          final meta = Map<String, dynamic>.from(node.metadata);
                          if (newSpoilerValue) {
                            meta['spoiler'] = true;
                          } else {
                            meta.remove('spoiler');
                          }

                          final updatedNode = node.copyWith(metadata: meta);
                          editorService.editor.execute([
                            ReplaceNodeRequest(
                              existingNodeId: nodeId,
                              newNode: updatedNode,
                            ),
                          ]);
                          nodeSvc.setSpoiler(nodeId, newSpoilerValue);
                          editorService.saveHistoryNow();
                        }
                      } catch (e) {
                        debugPrint(
                          '[SelectedToolbar] 스포일러 metadata 업데이트 실패: $e',
                        );
                      }

                      // ✅ 스포일러 토글 후에도 SelectedToolbar 유지:
                      // padding 토글과 동일하게 다음 프레임에 selection을 복구한다.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        try {
                          final editorService =
                              widget.editorService ??
                              context.read<EditorService>();

                          // ✅ 토글 후: 문서 selection(하이라이트/캐럿) 제거
                          try {
                            editorService.editor.composer.clearSelection();
                          } catch (_) {}

                          // NodeComponentService 선택 강제 유지 (토글 X)
                          context.read<NodeComponentService>().setSelectedNode(
                            nodeId,
                          );
                        } catch (e) {
                          debugPrint(
                            '[SelectedToolbar] 스포일러 토글 후 selection 복구 실패: $e',
                          );
                        }
                      });

                      if (mounted) setState(() {});
                    }
                  },
                  size: 28,
                ),
              ),
            SizedBox(width: 8),
          ],

          // 패딩 조절 버튼 (이미지/영상/링크)
          if (currentNode is ImageNode ||
              currentNode is ClipNode ||
              currentNode is LinkNode) ...[
            ToolbarMainIcon(
              svgPath: isExpanded
                  ? 'assets/icons/arrow-double-shrink.svg' // 확장됨 → 축소 아이콘
                  : 'assets/icons/arrow-double-expand.svg', // 축소됨 → 확장 아이콘
              isActive: false,
              height: 40,
              onTap: () {
                final nodeId = widget.selectedId;
                if (nodeId == null) return;

                // ✅ 링크 viewMode 토글과 동일 철학:
                // - 툴바 내부에서 metadata만 ReplaceNodeRequest로 교체
                // - selection이 풀리지 않아 SelectedToolbar가 닫히지 않게 한다.
                try {
                  final editorService =
                      widget.editorService ?? context.read<EditorService>();
                  final node = editorService.document.getNodeById(nodeId);
                  if (node == null) return;

                  // 현재 padding: 기본값은 center
                  String currentPadding = 'center';
                  Map<String, dynamic> updatedMetadata = {};

                  if (node is ImageNode) {
                    final meta = Map<String, dynamic>.from(
                      (node as dynamic).metadata as Map<String, dynamic>? ?? {},
                    );
                    currentPadding = (meta['padding'] as String?) ?? 'center';
                    meta['padding'] = currentPadding == 'full'
                        ? 'center'
                        : 'full';
                    updatedMetadata = meta;

                    final updatedNode = AppImageNode(
                      id: nodeId,
                      imageUrl: (node as dynamic).imageUrl as String,
                      altText: node.altText,
                      metadata: updatedMetadata,
                    );
                    editorService.editor.execute([
                      ReplaceNodeRequest(
                        existingNodeId: nodeId,
                        newNode: updatedNode,
                      ),
                    ]);
                    editorService.saveHistoryNow();
                  } else if (node is ClipNode) {
                    final meta = Map<String, dynamic>.from(node.metadata);
                    currentPadding = (meta['padding'] as String?) ?? 'center';
                    meta['padding'] = currentPadding == 'full'
                        ? 'center'
                        : 'full';
                    updatedMetadata = meta;

                    final updatedNode = ClipNode(
                      id: node.id,
                      label: node.label,
                      colorHex: node.colorHex,
                      url: node.url,
                      localPath: node.localPath,
                      thumbnailPath: node.thumbnailPath,
                      metadata: updatedMetadata,
                    );
                    editorService.editor.execute([
                      ReplaceNodeRequest(
                        existingNodeId: nodeId,
                        newNode: updatedNode,
                      ),
                    ]);
                    editorService.saveHistoryNow();
                  } else if (node is LinkNode) {
                    final meta = Map<String, dynamic>.from(node.metadata);
                    currentPadding = (meta['padding'] as String?) ?? 'center';
                    meta['padding'] = currentPadding == 'full'
                        ? 'center'
                        : 'full';
                    updatedMetadata = meta;

                    final updatedNode = LinkNode(
                      id: node.id,
                      url: node.url,
                      title: node.title,
                      description: node.description,
                      thumbnailUrl: node.thumbnailUrl,
                      metadata: updatedMetadata,
                    );
                    editorService.editor.execute([
                      ReplaceNodeRequest(
                        existingNodeId: nodeId,
                        newNode: updatedNode,
                      ),
                    ]);
                    editorService.saveHistoryNow();
                  }
                } catch (e) {
                  debugPrint('[SelectedToolbar] padding 토글 실패: $e');
                }

                // ✅ 토글 후에도 SelectedToolbar가 닫히지 않게:
                // - 문서 Replace로 인해 composer selection이 잠깐 바뀌면서 EditorService가 선택을 해제할 수 있다.
                // - 다음 프레임에 "해당 노드 downstream caret" + "NodeComponentService selection"을 복구한다.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  try {
                    final editorService =
                        widget.editorService ?? context.read<EditorService>();

                    // 1) 토글 후: 문서 selection(하이라이트/캐럿) 제거
                    try {
                      editorService.editor.composer.clearSelection();
                    } catch (_) {}

                    // 2) NodeComponentService 선택 강제 유지 (토글 X)
                    context.read<NodeComponentService>().setSelectedNode(
                      nodeId,
                    );
                  } catch (e) {
                    debugPrint('[SelectedToolbar] selection 복구 실패: $e');
                  }
                });

                if (mounted) setState(() {});
              },
            ),
            const SizedBox(width: 8),
          ],

          // 링크: 간략/풀 모드 토글 (간략=썸네일 영역 제거)
          if (currentNode is LinkNode) ...[
            ToolbarMainIcon(
              svgPath: isCompactLink
                  ? 'assets/icons/gallery.svg'
                  : 'assets/icons/text.svg',
              isActive: false,
              height: 40,
              onTap: () {
                final nodeId = widget.selectedId;
                if (nodeId == null) return;
                final editorService = widget.editorService;
                if (editorService == null) return;
                try {
                  final node = editorService.document.getNodeById(nodeId);
                  if (node is! LinkNode) return;
                  final meta = Map<String, dynamic>.from(node.metadata);
                  meta['viewMode'] = isCompactLink ? 'full' : 'compact';
                  final updatedNode = LinkNode(
                    id: node.id,
                    url: node.url,
                    title: node.title,
                    description: node.description,
                    thumbnailUrl: node.thumbnailUrl,
                    metadata: meta,
                  );
                  editorService.editor.execute([
                    ReplaceNodeRequest(
                      existingNodeId: nodeId,
                      newNode: updatedNode,
                    ),
                  ]);
                  // 🎯 링크 viewMode 토글을 히스토리에 저장
                  editorService.saveHistoryNow();
                  if (mounted) setState(() {});
                } catch (e) {
                  debugPrint('[SelectedToolbar] 링크 viewMode 업데이트 실패: $e');
                }
              },
            ),
            const SizedBox(width: 8),
          ],

          // ✅ 수정(크롭/편집) 버튼: 싱글/로우/페이지뷰 모두 활성화
          if (widget.node is ImageNode ||
              widget.node is ImageRowNode ||
              widget.node is PageViewImageNode) ...[
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ToolbarMainIcon(
                size: 28,
                svgPath: 'assets/icons/crop.svg',
                isActive: false,
                height: 40,
                onTap: widget.onEdit,
              ),
            ),
            const SizedBox(width: 8),
          ],

          ToolbarMainIcon(
            size: 28,
            svgPath: 'assets/icons/delete.svg',
            isActive: false,
            height: 40,
            onTap: (widget.node != null && widget.selectedId != null)
                ? () => widget.onDelete(widget.node!, widget.selectedId!)
                : () {},
          ),
        ],
      ),
    );
  }
}
