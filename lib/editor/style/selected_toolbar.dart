import 'package:doppy/editor/component/clip_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/pageview_image_component.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:provider/provider.dart';
import 'package:doppy/editor/component/app_image_node.dart';

class SelectedToolbar extends StatefulWidget {
  const SelectedToolbar({
    super.key,
    required this.selectedId,
    required this.node,
    required this.onEdit,
    required this.onDelete,
    this.onChangeAlignment,
    this.editorService, // 🎯 Provider context 문제 방지
  });

  final String? selectedId;
  final DocumentNode? node;
  final VoidCallback onEdit;
  final void Function(DocumentNode node, String selectedId) onDelete;
  final Future<void> Function(DocumentNode node, String selectedId)?
  onChangeAlignment;
  final EditorService? editorService; // 🎯 Provider context 문제 방지

  @override
  State<SelectedToolbar> createState() => _SelectedToolbarState();
}

class _SelectedToolbarState extends State<SelectedToolbar> {
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

    // 이미지 스포일러 적용 여부
    bool isImageSpoiler = false;
    if (currentNode is ImageNode || currentNode is ImageRowNode) {
      try {
        final nodeService = NodeComponentService();
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
          Text(
            '선택됨',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          /*
          Text(
            '선택됨: ${node.runtimeType}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
         */
          const Spacer(),
          if (currentNode is ImageNode || currentNode is ImageRowNode) ...[
            // 스포일러 토글
            if (widget.node is ImageNode || widget.node is ImageRowNode)
              _buildSvgToggleIcon(
                svgPath: 'assets/icons/spoiler.svg',
                isActive: isImageSpoiler,
                label: '스포일러',
                onTap: () {
                  if (widget.selectedId != null) {
                    final newSpoilerValue = !isImageSpoiler;
                    final nodeId = widget.selectedId!;

                    // ✅ 편집 모드(문서 기반)에서는 NodeComponentService의 세션 캐시가
                    // 문서 metadata와 충돌하면 undo/redo 시 상태가 어긋날 수 있다.
                    // 따라서 토글 시 세션 캐시를 제거하고, 문서 metadata만 변경한다.
                    NodeComponentService().clearSpoilerForNode(
                      nodeId,
                      notify: false,
                    );

                    // 문서의 metadata 업데이트 (undo/redo 포함 복원 시 스포일러 상태 유지)
                    try {
                      // 🎯 prop으로 전달받은 editorService 우선 사용, 없으면 Provider로 접근
                      final editorService =
                          widget.editorService ?? context.read<EditorService>();
                      final node = editorService.document.getNodeById(nodeId);

                      if (node is ImageNode) {
                        final meta = Map<String, dynamic>.from(
                          (node as dynamic).metadata as Map<String, dynamic>? ??
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
                      }
                    } catch (e) {
                      debugPrint('[SelectedToolbar] 스포일러 metadata 업데이트 실패: $e');
                    }

                    // ✅ 스포일러 토글 후에도 SelectedToolbar 유지:
                    // padding 토글과 동일하게 다음 프레임에 selection을 복구한다.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      try {
                        final editorService =
                            widget.editorService ??
                            context.read<EditorService>();

                        // composer selection 복구 (특수 노드 downstream)
                        try {
                          editorService.editor.execute([
                            ChangeSelectionRequest(
                              DocumentSelection.collapsed(
                                position: DocumentPosition(
                                  nodeId: nodeId,
                                  nodePosition:
                                      const UpstreamDownstreamNodePosition.downstream(),
                                ),
                              ),
                              SelectionChangeType.placeCaret,
                              SelectionReason.userInteraction,
                            ),
                          ]);
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
            SizedBox(width: 8),
          ],

          // 패딩 조절 버튼 (이미지/영상/링크)
          if (currentNode is ImageNode ||
              currentNode is ClipNode ||
              currentNode is LinkNode) ...[
            _buildMainSvgIcon(
              context: context,
              svgPath:
                  isExpanded
                      ? 'assets/icons/arrow-double-shrink.svg' // 확장됨 → 축소 아이콘
                      : 'assets/icons/arrow-double-expand.svg', // 축소됨 → 확장 아이콘
              isActive: true,
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
                    meta['padding'] =
                        currentPadding == 'full' ? 'center' : 'full';
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
                  } else if (node is ClipNode) {
                    final meta = Map<String, dynamic>.from(node.metadata);
                    currentPadding = (meta['padding'] as String?) ?? 'center';
                    meta['padding'] =
                        currentPadding == 'full' ? 'center' : 'full';
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
                  } else if (node is LinkNode) {
                    final meta = Map<String, dynamic>.from(node.metadata);
                    currentPadding = (meta['padding'] as String?) ?? 'center';
                    meta['padding'] =
                        currentPadding == 'full' ? 'center' : 'full';
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

                    // 1) composer selection 복구 (특수 노드 downstream)
                    try {
                      editorService.editor.execute([
                        ChangeSelectionRequest(
                          DocumentSelection.collapsed(
                            position: DocumentPosition(
                              nodeId: nodeId,
                              nodePosition:
                                  const UpstreamDownstreamNodePosition.downstream(),
                            ),
                          ),
                          SelectionChangeType.placeCaret,
                          SelectionReason.userInteraction,
                        ),
                      ]);
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
            _buildMainSvgIcon(
              context: context,
              svgPath:
                  isCompactLink
                      ? 'assets/icons/editor_gallery.svg'
                      : 'assets/icons/ic_text.svg',
              isActive: false,
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
              child: _buildMainSvgIcon(
                size: 28,
                context: context,
                svgPath: 'assets/icons/crop.svg',
                isActive: false,
                onTap: widget.onEdit,
              ),
            ),
            const SizedBox(width: 8),
          ],

          _buildMainSvgIcon(
            size: 24,
            context: context,
            svgPath: 'assets/icons/delete.svg',
            isActive: false,
            onTap:
                (widget.node != null && widget.selectedId != null)
                    ? () => widget.onDelete(widget.node!, widget.selectedId!)
                    : () {},
          ),
        ],
      ),
    );
  }

  Widget _buildMainSvgIcon({
    required BuildContext context,
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    double? size,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color = onSurface.withOpacity(0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 40,
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder:
                (child, anim) => FadeTransition(opacity: anim, child: child),
            child: SvgPicture.asset(
              svgPath,
              key: ValueKey(svgPath),
              width: size ?? (isActive ? 28 : 25),
              height: size ?? (isActive ? 28 : 25),
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSvgToggleIcon({
    required String svgPath,
    required bool isActive,
    required VoidCallback onTap,
    required String label,
    double? size,
  }) {
    final Color surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;
    final Color onSurface =
        isActive
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

    return Material(
      color: isActive ? surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: SvgPicture.asset(
            svgPath,
            width: size ?? 24,
            height: size ?? 24,
            colorFilter: ColorFilter.mode(onSurface, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
