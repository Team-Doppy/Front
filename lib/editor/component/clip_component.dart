import 'dart:typed_data';
import 'dart:ui';
import 'dart:io';

import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:doppy/editor/component/row_image_component.dart';
import 'package:doppy/editor/component/link_component.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:doppy/pages/components/shimmer_box.dart';

/// VideoPlayer 컨트롤러를 저장하는 맵
final videoPlayerControllers = <String, VideoPlayerControllerProxy>{};

/// 🎯 reader 모드에서 ClipComponent와 FullscreenVideoPlayer가 공유하는 컨트롤러 맵
final readerVideoControllers = <String, VideoPlayerController>{};

/// 🎯 에디터 모드에서 비디오 컨트롤러 캐시 (드래그앤드롭 시 재사용)
final editorVideoControllers = <String, VideoPlayerController>{};

/// VideoPlayer 프록시 클래스
class VideoPlayerControllerProxy {
  void Function()? toggleMute;
  void Function()? restartVideo;
  bool Function()? hasPlayedOnce;
  void Function()? pause;
}

/// 모든 비디오 플레이어 정리
void cleanupAllVideoPlayers() {
  debugPrint('[ClipComponent] 모든 비디오 플레이어 정리 시작');
  for (final entry in videoPlayerControllers.entries) {
    final controller = entry.value;
    // 모든 비디오 일시정지
    controller.pause?.call();
  }
  // 맵 비우기
  videoPlayerControllers.clear();

  // 🎯 에디터 모드 비디오 컨트롤러 캐시 정리
  for (final entry in editorVideoControllers.entries) {
    try {
      final controller = entry.value;
      if (controller.value.isInitialized) {
        controller.pause();
        controller.dispose();
      }
    } catch (e) {
      debugPrint('[ClipComponent] 에디터 컨트롤러 정리 오류: $e');
    }
  }
  editorVideoControllers.clear();

  debugPrint('[ClipComponent] 모든 비디오 플레이어 정리 완료');
}

/// 주어진 key를 제외한 모든 비디오를 일시정지한다
void pauseAllVideosExcept(String keepKey) {
  // build 중 setState를 유발하지 않도록 프레임 이후로 미룸
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final entry in videoPlayerControllers.entries) {
      if (entry.key == keepKey) continue;
      entry.value.pause?.call();
    }
  });
}

/// 텍스트와 독립적인 핀 블록 노드
class ClipNode extends BlockNode {
  ClipNode({
    required this.id,
    this.label = '',
    this.colorHex = '#FF5252',
    this.url = '',
    this.localPath = '',
    this.thumbnailPath = '',
    Map<String, dynamic>? metadata,
  }) : _metadata = metadata ?? const {};

  @override
  bool get isDeletable => false;
  String get nodeType => 'pin';

  @override
  final String id;
  final String label;
  final String colorHex;
  final String url;
  final String localPath;
  final String thumbnailPath;
  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => _metadata;

  @override
  bool containsPosition(Object position) =>
      position is UpstreamDownstreamNodePosition;

  @override
  UpstreamDownstreamNodeSelection computeSelection({
    required NodePosition base,
    required NodePosition extent,
  }) {
    return UpstreamDownstreamNodeSelection(
      base: base as UpstreamDownstreamNodePosition,
      extent: extent as UpstreamDownstreamNodePosition,
    );
  }

  @override
  UpstreamDownstreamNodePosition selectDownstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => const UpstreamDownstreamNodePosition.downstream();

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => const UpstreamDownstreamNodePosition.upstream();

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return ClipNode(
      id: id,
      label: label,
      colorHex: colorHex,
      url: url,
      localPath: localPath,
      thumbnailPath: thumbnailPath,
      metadata: newMetadata,
    );
  }

  @override
  String? copyContent(NodeSelection selection) => label;

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return ClipNode(
      id: id,
      label: label,
      colorHex: colorHex,
      url: url,
      localPath: localPath,
      thumbnailPath: thumbnailPath,
      metadata: {...metadata, ...newProperties},
    );
  }
}

class ClipComponentViewModel extends SingleColumnLayoutComponentViewModel {
  ClipComponentViewModel({
    required super.nodeId,
    required this.label,
    required this.colorHex,
    required this.url,
    required this.localPath,
    required this.thumbnailPath,
  }) : super(padding: EdgeInsets.zero, createdAt: DateTime.now());

  final String label;
  final String colorHex;
  final String url;
  final String localPath;
  final String thumbnailPath;

  @override
  SingleColumnLayoutComponentViewModel copy() => ClipComponentViewModel(
    nodeId: nodeId,
    label: label,
    colorHex: colorHex,
    url: url,
    localPath: localPath,
    thumbnailPath: thumbnailPath,
  );
}

class ClipComponentBuilder implements ComponentBuilder {
  const ClipComponentBuilder({
    this.dragService,
    this.isEditing = false,
    this.isDarkMode = false,
  });
  final DragService? dragService;
  final bool isEditing; // 에디터에서는 true, 리더에서는 false
  final bool isDarkMode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext context,
    SingleColumnLayoutComponentViewModel viewModel,
  ) {
    if (viewModel is ClipComponentViewModel) {
      return _ClipComponent(
        componentKey: context.componentKey,
        nodeId: viewModel.nodeId,
        label: viewModel.label,
        colorHex: viewModel.colorHex,
        isDarkMode: isDarkMode,
        url: viewModel.url,
        localPath: viewModel.localPath,
        thumbnailPath: viewModel.thumbnailPath,
        dragService: dragService,
        isEditing: isEditing,
      );
    }
    return null;
  }

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is ClipNode) {
      return ClipComponentViewModel(
        nodeId: node.id,
        label: node.label,
        colorHex: node.colorHex,
        url: node.url,
        localPath: node.localPath,
        thumbnailPath: node.thumbnailPath,
      );
    }
    return null;
  }
}

class _ClipComponent extends StatefulWidget {
  const _ClipComponent({
    required GlobalKey componentKey,
    required this.nodeId,
    required this.label,
    required this.colorHex,
    required this.url,
    required this.localPath,
    required this.thumbnailPath,
    this.dragService,
    this.isEditing = false,
    this.isDarkMode = false,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final GlobalKey _componentKey;
  final String nodeId;
  final String label;
  final String colorHex;
  final String url;
  final String localPath;
  final String thumbnailPath;
  final DragService? dragService;
  final bool isEditing;
  final bool isDarkMode;

  @override
  State<_ClipComponent> createState() => _ClipComponentState();
}

class _ClipComponentState extends State<_ClipComponent> with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  static const double marginTop = 4;

  // 특수 영역(음소거 버튼, 다시보기 버튼) 탭 여부
  bool _clipNodeSpecialAreaTapped = false;

  // 🎯 클립 노드 액션 실행 (음소거, 재시작 등)
  void _triggerClipNodeAction(String action) {
    debugPrint(
      '[ClipComponent] Action triggered: $action for node: ${widget.nodeId}',
    );

    // 컨트롤러 찾기
    final key = 'video_${widget.url.hashCode}';
    final controller = videoPlayerControllers[key];

    if (controller == null) {
      debugPrint('[ClipComponent] 컨트롤러를 찾을 수 없습니다: $key');
      return;
    }

    // 액션 실행
    if (action == 'toggleMute') {
      controller.toggleMute?.call();
      debugPrint('[ClipComponent] toggleMute() 호출됨');
    } else if (action == 'restartVideo') {
      controller.restartVideo?.call();
      debugPrint('[ClipComponent] restartVideo() 호출됨');
    }
  }

  static const double marginBottom = 2;
  static const double paddingWithText = 12;

  // 🎯 특수 노드 사이/마지막 노드 아래 빈 문단 추가 처리
  void _handleSpecialNodeTap(Offset globalPosition) {
    if (widget.dragService == null) return;
    final editorService = widget.dragService!.editorService;
    final doc = editorService.document;
    final dragService = widget.dragService!;

    // 자신의 인덱스와 Rect 확인
    final currentNodeIndex = doc.getNodeIndexById(widget.nodeId);
    if (currentNodeIndex == -1) return;

    final nodeRect = dragService.getNodeGlobalRect(widget.nodeId);
    if (nodeRect == null) return;

    // 🎯 마지막 노드이고 패딩 부분(아래 20px)을 클릭한 경우
    final isLastNode = currentNodeIndex == doc.nodeCount - 1;
    if (isLastNode && globalPosition.dy > nodeRect.bottom + 20) {
      // 마지막 노드 아래 빈 문단 추가
      editorService.insertEmptyParagraphAtIndex(currentNodeIndex + 1);
      dragService.invalidateNodeRectCache();
      context.read<NodeComponentService>().selectNode(null);
      return;
    }

    // 🎯 위쪽 이웃 노드 확인
    if (currentNodeIndex > 0) {
      final prevNode = doc.getNodeAt(currentNodeIndex - 1);
      if (prevNode != null) {
        final isSpecialPrev =
            prevNode is ImageNode ||
            prevNode is ImageRowNode ||
            prevNode is ClipNode ||
            prevNode is LinkNode;

        if (isSpecialPrev) {
          final prevRect = dragService.getNodeGlobalRect(prevNode.id);
          if (prevRect != null) {
            // 위쪽 노드와 자신 사이의 간격 확인 (위쪽 노드 아래 20px ~ 자신 위쪽 20px)
            final gapTop = prevRect.bottom - 20;
            final gapBottom = nodeRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return;
            }
          }
        }
      }
    }

    // 🎯 아래쪽 이웃 노드 확인
    if (currentNodeIndex < doc.nodeCount - 1) {
      final nextNode = doc.getNodeAt(currentNodeIndex + 1);
      if (nextNode != null) {
        final isSpecialNext =
            nextNode is ImageNode ||
            nextNode is ImageRowNode ||
            nextNode is ClipNode ||
            nextNode is LinkNode;

        if (isSpecialNext) {
          final nextRect = dragService.getNodeGlobalRect(nextNode.id);
          if (nextRect != null) {
            // 자신과 아래쪽 노드 사이의 간격 확인 (자신 아래 20px ~ 아래쪽 노드 위쪽 20px)
            final gapTop = nodeRect.bottom - 20;
            final gapBottom = nextRect.top + 20;
            if (globalPosition.dy >= gapTop && globalPosition.dy <= gapBottom) {
              // 특수 노드 사이 빈 문단 추가
              editorService.insertEmptyParagraphAtIndex(currentNodeIndex + 1);
              dragService.invalidateNodeRectCache();
              context.read<NodeComponentService>().selectNode(null);
              return;
            }
          }
        }
      }
    }
  }

  // 업로드 중 로컬 비디오 썸네일 캐시
  Uint8List? _localVideoThumbnailBytes;
  String? _localVideoThumbPath;
  double? _localVideoThumbAspectRatio; // width / height

  Future<void> _ensureLocalVideoThumbnail() async {
    final String path = widget.localPath;
    if (path.isEmpty) return;
    if (_localVideoThumbPath == path && _localVideoThumbnailBytes != null)
      return;
    _localVideoThumbPath = path;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        quality: 100, // 🎯 최고 화질로 설정
      );
      if (mounted && _localVideoThumbPath == path) {
        // 썸네일 바이트 저장 + 실제 가로세로 비율 계산
        double? aspect;
        try {
          if (bytes != null) {
            final img = await decodeImageFromList(bytes);
            if (img.width > 0 && img.height > 0) {
              aspect = img.width / img.height;
            }
          }
        } catch (_) {}
        setState(() {
          _localVideoThumbnailBytes = bytes;
          if (aspect != null) _localVideoThumbAspectRatio = aspect;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // selection 핸들이 링크 노드를 포함하는지 확인
    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    final composerSelection = seState?.editContext.composer.selection;
    // ignore: invalid_use_of_visible_for_testing_member
    final doc = seState?.editContext.editor.document;

    // 이웃하는 특수 노드 체크 (이미지, 클립, 링크)
    final bool hasImageAbove =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, 1);

    final imageService = context.watch<NodeComponentService>();
    final isSelected = imageService.selectedImageId == widget.nodeId;

    bool isSelectionHighlighted = false;
    if (composerSelection != null &&
        !composerSelection.isCollapsed &&
        doc != null) {
      isSelectionHighlighted = _isNodeCoveredBySelection(
        doc,
        composerSelection,
        widget.nodeId,
      );
    }

    // 스타일시트 패딩 적용: metadata에서 패딩 모드 확인 (기본값: 'center' = 패딩 있음)
    double horizontalPadding = 20.0; // 기본 패딩
    try {
      final node = doc?.getNodeById(widget.nodeId);
      if (node is ClipNode) {
        final paddingMode = node.metadata['padding'] as String? ?? 'center';
        horizontalPadding = paddingMode == 'full' ? 0.0 : 20.0;
      }
    } catch (_) {}

    // 댓글 배지 표시 여부/카운트 (metadata.hasComments/commentCount)
    bool hasCommentsFlag = false;

    try {
      final node = doc?.getNodeById(widget.nodeId);
      if (node is ClipNode) {
        final meta = node.metadata;
        hasCommentsFlag = meta['hasComments'] == true;
      }
    } catch (_) {}

    return Column(
      children: [
        if (!hasImageAbove) SizedBox(height: paddingWithText),
        // 실제 비디오 내용 + 좌/우 세로 라인 (머지 모드에서)
        LayoutBuilder(
          builder: (context, constraints) {
            final card = Container(
              width: double.infinity,
              margin: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
              ),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceVariant.withOpacity(0.25),
              ),
              child: _buildVideoContent(context, horizontalPadding),
            );

            return Stack(
              children: [
                // 🎯 편집 모드에서 탭/롱프레스 처리
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown:
                      widget.isEditing && widget.dragService != null
                          ? (details) {
                            // 특수 노드 사이/마지막 노드 아래 빈 문단 추가 처리
                            _handleSpecialNodeTap(details.globalPosition);

                            // 특수 영역(음소거 버튼, 다시보기 버튼) 감지
                            final action = widget.dragService!
                                .handleClipNodeTap(
                                  widget.nodeId,
                                  details.globalPosition,
                                );
                            if (action != null) {
                              // 특수 영역이면 action 실행
                              _triggerClipNodeAction(action);
                              // 특수 영역이면 탭 처리 안 함 (비디오 컨트롤이 처리)
                              // onTap이 호출되지 않도록 상태 변수 사용
                              setState(() {
                                _clipNodeSpecialAreaTapped = true;
                              });
                            } else {
                              setState(() {
                                _clipNodeSpecialAreaTapped = false;
                              });
                            }
                          }
                          : null,
                  onTap:
                      widget.isEditing && widget.dragService != null
                          ? () {
                            // 특수 영역이 탭되었으면 노드 선택 처리 안 함
                            if (_clipNodeSpecialAreaTapped) {
                              setState(() {
                                _clipNodeSpecialAreaTapped = false;
                              });
                              return;
                            }

                            debugPrint(
                              '[ClipComponent] onTap 호출됨: nodeId=${widget.nodeId}',
                            );
                            // 노드 선택/해제
                            final imageService =
                                context.read<NodeComponentService>();
                            final currentSelected =
                                imageService.selectedImageId;
                            if (currentSelected == widget.nodeId) {
                              // 같은 노드 재탭: 선택 해제
                              debugPrint('[ClipComponent] 선택 해제');
                              imageService.selectNode(null);
                              widget.dragService?.invalidateNodeRectCache();
                            } else {
                              // 다른 노드 선택
                              debugPrint(
                                '[ClipComponent] 노드 선택: nodeId=${widget.nodeId}',
                              );
                              imageService.selectNode(widget.nodeId);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  widget.dragService?.invalidateNodeRectCache();
                                }
                              });
                            }
                          }
                          : null,
                  onLongPressStart:
                      widget.isEditing && widget.dragService != null
                          ? (details) {
                            // 키보드 내리기
                            final keyboardVisible =
                                MediaQuery.of(context).viewInsets.bottom > 0;
                            if (keyboardVisible) {
                              FocusScope.of(context).unfocus();
                            }
                            // 드래그 시작
                            widget.dragService?.startDrag(
                              widget.nodeId,
                              context,
                              details.globalPosition,
                            );
                          }
                          : null,
                  onLongPressMoveUpdate:
                      widget.isEditing && widget.dragService != null
                          ? (details) {
                            // 드래그 업데이트
                            widget.dragService?.updateDrag(
                              details.globalPosition,
                              context,
                            );
                          }
                          : null,
                  onLongPressEnd:
                      widget.isEditing && widget.dragService != null
                          ? (_) {
                            // 드래그 종료
                            widget.dragService?.endDrag();
                          }
                          : null,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: marginTop,
                      bottom: marginBottom,
                    ),
                    child: Stack(
                      children: [
                        card,
                        // 댓글 배지 (읽기 전용 - 포인터 통과)
                        if (hasCommentsFlag)
                          Positioned(
                            top: 4,
                            right: horizontalPadding + 5,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                                child: SvgPicture.asset(
                                  'assets/icons/comment.svg',
                                  width: 12,
                                  height: 12,
                                  colorFilter: ColorFilter.mode(
                                    Theme.of(context).colorScheme.surface,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // 선택 하이라이트 오버레이
                        if (isSelectionHighlighted)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: AppColors.primary.withOpacity(0.4),
                              ),
                            ),
                          ),
                        // 선택 테두리 (horizontalPadding 고려)
                        if (isSelected)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                margin: EdgeInsets.only(
                                  left: horizontalPadding,
                                  right: horizontalPadding,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_shouldShowTopDropLine())
                  Positioned(
                    top: 0,
                    left: horizontalPadding,
                    right: horizontalPadding,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Container(height: 5, color: AppColors.primary),
                    ),
                  ),
                if (_shouldShowBottomDropLine())
                  Positioned(
                    bottom: 0,
                    left: horizontalPadding,
                    right: horizontalPadding,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Container(height: 5, color: AppColors.primary),
                    ),
                  ),
              ],
            );
          },
        ),
        if (!hasImageBelow) SizedBox(height: paddingWithText),
      ],
    );
  }

  // DocumentComponent 최소 구현 (이미지/위치와 동일 정책)
  @override
  NodePosition getBeginningPosition() =>
      const UpstreamDownstreamNodePosition.upstream();
  @override
  NodePosition getEndPosition() =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  NodePosition? getPositionAtOffset(Offset localOffset) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  Offset getOffsetForPosition(NodePosition nodePosition) => Offset.zero;
  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Rect.zero : (Offset.zero & box.size);
  }

  @override
  Rect getRectForSelection(NodePosition base, NodePosition extent) =>
      getRectForPosition(extent);
  @override
  NodeSelection getCollapsedSelectionAt(NodePosition nodePosition) =>
      UpstreamDownstreamNodeSelection(
        base: const UpstreamDownstreamNodePosition.upstream(),
        extent: const UpstreamDownstreamNodePosition.upstream(),
      );
  @override
  NodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) => UpstreamDownstreamNodeSelection(
    base: const UpstreamDownstreamNodePosition.upstream(),
    extent: const UpstreamDownstreamNodePosition.downstream(),
  );
  @override
  NodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) => null;
  @override
  NodeSelection getSelectionOfEverything() => UpstreamDownstreamNodeSelection(
    base: const UpstreamDownstreamNodePosition.upstream(),
    extent: const UpstreamDownstreamNodePosition.downstream(),
  );
  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Rect.zero : (Offset.zero & box.size);
  }

  @override
  bool isVisualSelectionSupported() => false;
  @override
  NodePosition? movePositionLeft(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) => null;
  @override
  NodePosition? movePositionRight(
    NodePosition currentPosition, [
    MovementModifier? movementModifier,
  ]) => null;
  @override
  NodePosition? movePositionUp(NodePosition currentPosition) => null;
  @override
  NodePosition? movePositionDown(NodePosition currentPosition) => null;
  @override
  NodePosition getBeginningPositionNearX(double x) =>
      const UpstreamDownstreamNodePosition.upstream();
  @override
  NodePosition getEndPositionNearX(double x) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  // 드래그 삽입 라인 표시 로직
  bool _shouldShowTopDropLine() {
    if (widget.dragService == null) return false;
    final dropIndex = widget.dragService!.dropIndex;
    if (dropIndex == null) return false;
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;

    // 이 노드 위에 삽입하는 경우
    if (dropIndex == currentNodeIndex) {
      return _shouldShowInsertionLine(currentNodeIndex, true);
    }
    return false;
  }

  bool _shouldShowBottomDropLine() {
    if (widget.dragService == null) return false;
    final dropIndex = widget.dragService!.dropIndex;
    if (dropIndex == null) return false;
    final currentNodeIndex = _getCurrentNodeIndex();
    if (currentNodeIndex == -1) return false;

    // 마지막 노드인지 확인
    final documentLength = widget.dragService!.editorService.document.length;
    final isLastNode = currentNodeIndex == documentLength - 1;

    if (isLastNode) {
      // 마지막 노드일 때는 문서 끝에 삽입하는 경우
      return dropIndex == documentLength;
    } else {
      // 다음 인덱스에 삽입하는 경우
      if (dropIndex == currentNodeIndex + 1) {
        return _shouldShowInsertionLine(currentNodeIndex, false);
      }
    }
    return false;
  }

  /// 삽입 라인 표시 여부를 결정하는 공통 로직
  bool _shouldShowInsertionLine(int currentNodeIndex, bool isTopLine) {
    if (widget.dragService == null) return false;

    final doc = widget.dragService!.editorService.document;
    final documentLength = doc.length;

    // 특수 노드 타입 체크
    bool isSpecialNode(DocumentNode? node) {
      if (node == null) return false;
      return node is LinkNode ||
          (node is ParagraphNode && node.metadata['mention'] == true) ||
          node is ImageNode ||
          node is ImageRowNode ||
          node is ClipNode; // 🎯 ClipNode도 특수 노드로 취급
    }

    // 텍스트 노드 타입 체크
    bool isTextNode(DocumentNode? node) {
      if (node == null) return false;
      return node is ParagraphNode;
    }

    if (isTopLine) {
      // 위쪽 라인 표시 로직
      if (currentNodeIndex > 0) {
        final prevNode = doc.getNodeAt(currentNodeIndex - 1);

        // 케이스 1: 앞이 특수 노드인 경우 - 이 노드에서는 라인을 표시하지 않음
        // (위쪽 특수 노드가 아래쪽 라인을 표시하므로)
        if (isSpecialNode(prevNode)) {
          return false;
        }
      }
      return true;
    } else {
      // 아래쪽 라인 표시 로직
      if (currentNodeIndex + 1 < documentLength) {
        final nextNode = doc.getNodeAt(currentNodeIndex + 1);

        // 케이스 1: 뒤가 특수 노드인 경우 - 이 노드에서는 라인을 표시함
        // (특수-특수 사이에서는 위쪽 특수 노드가 아래쪽 라인을 표시)
        if (isSpecialNode(nextNode)) {
          return true;
        }

        // 케이스 2: 뒤가 텍스트 노드인 경우 - 이 노드에서는 라인을 표시함
        if (isTextNode(nextNode)) {
          return true;
        }
      }
      return true;
    }
  }

  int _getCurrentNodeIndex() {
    final svc = widget.dragService;
    if (svc == null) return -1;
    return svc.getNodeIndex(widget.nodeId);
  }

  // selection이 이 링크 노드를 포함하는지 계산
  bool _isNodeCoveredBySelection(
    Document doc,
    DocumentSelection selection,
    String nodeId,
  ) {
    final baseIndex = doc.getNodeIndexById(selection.base.nodeId);
    final extentIndex = doc.getNodeIndexById(selection.extent.nodeId);
    final myIndex = doc.getNodeIndexById(nodeId);
    if (baseIndex == -1 || extentIndex == -1 || myIndex == -1) return false;

    final start = math.min(baseIndex, extentIndex);
    final end = math.max(baseIndex, extentIndex);
    if (myIndex < start || myIndex > end) return false;

    // 시작 경계가 이 노드인 경우
    if (myIndex == start) {
      final boundary = baseIndex == start ? selection.base : selection.extent;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    // 끝 경계가 이 노드인 경우
    if (myIndex == end) {
      final boundary = extentIndex == end ? selection.extent : selection.base;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    // 범위 내부에 완전히 포함
    return true;
  }

  bool _hasNeighborImage(Document doc, String nodeId, int direction) {
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;
    final neighborIndex = myIndex + direction;
    if (neighborIndex < 0 || neighborIndex >= doc.nodeCount) return false;
    final neighbor = doc.getNodeAt(neighborIndex);
    return neighbor is ImageNode ||
        neighbor is ImageRowNode ||
        neighbor is ClipNode ||
        neighbor is LinkNode;
  }

  /// 업로드 로딩 표시 위젯 (로딩 스피너만)
  Widget _buildUploadProgress(BuildContext context) {
    return const SizedBox(
      width: 28,
      height: 28,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }

  Widget _buildVideoContent(BuildContext context, double horizontalPadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    // horizontalPadding을 고려한 실제 비디오 너비
    final videoWidth = screenWidth - (horizontalPadding * 2);
    final maxHeight = videoWidth * 1.5;

    // 로컬 파일 경로가 있으면 (업로드 중) 썸네일과 로딩 표시
    if (widget.localPath.isNotEmpty) {
      _ensureLocalVideoThumbnail();
      // 기본 비율로 계산한 높이 (썸네일이 준비되면 실제 비율 사용)
      final double aspect = _localVideoThumbAspectRatio ?? (16 / 9);
      // horizontalPadding을 고려한 너비로 높이 계산
      final calculatedHeight = videoWidth / aspect;
      final finalHeight =
          calculatedHeight > maxHeight ? maxHeight : calculatedHeight;

      // 썸네일 경로가 있으면 썸네일을 배경으로 사용
      if (widget.thumbnailPath.isNotEmpty) {
        return SizedBox(
          width: videoWidth,
          height: finalHeight,
          child: Stack(
            children: [
              // 썸네일 배경
              ClipRRect(
                child: Image.file(
                  File(widget.thumbnailPath),
                  fit: BoxFit.contain, // full 모드에서 자연스럽게 높이 늘어나도록 contain 사용
                  width: videoWidth,
                  height: calculatedHeight,
                ),
              ),
              // 업로드 진행 오버레이 (이미지 업로드와 통일: 검정 0.6)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Center(child: _buildUploadProgress(context)),
                ),
              ),
            ],
          ),
        );
      }

      // 썸네일이 없으면 비디오 첫 프레임 썸네일 생성 후 표시 (도착 전까지는 쉬머)
      return SizedBox(
        width: videoWidth,
        height: finalHeight,
        child: Stack(
          children: [
            if (_localVideoThumbnailBytes != null)
              Image.memory(
                _localVideoThumbnailBytes!,
                fit: BoxFit.contain, // full 모드에서 자연스럽게 높이 늘어나도록 contain 사용
                width: videoWidth,
                height: calculatedHeight,
              )
            else
              ShimmerBox(
                width: videoWidth,
                height: videoWidth / (4 / 5),
                isDarkMode: widget.isDarkMode,
              ),
            // 업로드 진행 오버레이 (이미지 업로드와 통일: 검정 0.6)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.6),
                child: Center(child: _buildUploadProgress(context)),
              ),
            ),
          ],
        ),
      );
    }

    // 네트워크 URL이 있으면 비디오 플레이어
    if (widget.url.isNotEmpty) {
      return _VisibilityAwareVideoPlayer(
        url: widget.url,
        thumbnailPath: widget.thumbnailPath,
        isEditing: widget.isEditing,
        isDarkMode: widget.isDarkMode,
        horizontalPadding: horizontalPadding,
      );
    }

    // 업로드 완료되지 않으면 텍스트만 표시
    return Row(
      children: [
        const SizedBox(width: 12),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              widget.label.isNotEmpty ? widget.label : 'clip',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

/// 가시성 감지 래퍼
class _VisibilityAwareVideoPlayer extends StatefulWidget {
  final String url;
  final String thumbnailPath;
  final bool isEditing;
  final bool isDarkMode;
  final double horizontalPadding;

  const _VisibilityAwareVideoPlayer({
    required this.url,
    required this.thumbnailPath,
    required this.isEditing,
    this.isDarkMode = false,
    required this.horizontalPadding,
  });

  @override
  State<_VisibilityAwareVideoPlayer> createState() =>
      _VisibilityAwareVideoPlayerState();
}

class _VisibilityAwareVideoPlayerState
    extends State<_VisibilityAwareVideoPlayer> {
  bool _isVisible = false;
  late final GlobalKey _key;

  @override
  void initState() {
    super.initState();
    // 각 비디오마다 고유한 GlobalKey 생성 (URL 기반)
    _key = GlobalKey(debugLabel: 'visibility_${widget.url.hashCode}');
    _checkVisibility();
  }

  void _checkVisibility() {
    // 주기적으로 가시성 체크
    Future.delayed(Duration(milliseconds: 100), () {
      if (!mounted) return;
      _updateVisibility();
      _checkVisibility();
    });
  }

  void _updateVisibility() {
    final context = _key.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);

    final screenHeight = MediaQuery.of(context).size.height;
    final viewportTop = 0.0;
    final viewportBottom = screenHeight;

    // 화면에 보이는 비율 계산
    final visibleTop = math.max(position.dy, viewportTop);
    final visibleBottom = math.min(position.dy + size.height, viewportBottom);
    final visibleHeight = math.max(0.0, visibleBottom - visibleTop);
    final visibleRatio = size.height > 0 ? visibleHeight / size.height : 0.0;

    // 기준 상향: 최소 60%가 보이면 재생
    final isVisible = visibleRatio >= 0.7;

    if (_isVisible != isVisible) {
      setState(() {
        _isVisible = isVisible;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _key,
      child: _VideoPlayerWidget(
        // key 제거 - 각 인스턴스는 이미 고유함
        url: widget.url,
        thumbnailPath: widget.thumbnailPath,
        shouldAutoPlay: _isVisible,
        isEditing: widget.isEditing,
        isDarkMode: widget.isDarkMode,
        horizontalPadding: widget.horizontalPadding,
      ),
    );
  }
}

/// 비디오 플레이어 위젯
class _VideoPlayerWidget extends StatefulWidget {
  final String url;
  final String thumbnailPath;
  final bool shouldAutoPlay;
  final bool isEditing;
  final bool isDarkMode;
  final double horizontalPadding;

  const _VideoPlayerWidget({
    required this.url,
    required this.thumbnailPath,
    this.shouldAutoPlay = true,
    required this.isEditing,
    this.isDarkMode = false,
    required this.horizontalPadding,
  });

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isReadyToPlay = false; // 🎯 실제 재생 준비 완료 여부 (버퍼링 포함)
  bool _hasError = false;
  bool _hasPlayedOnce = false;
  bool _isPlaying = false;
  bool _isPausedByUser = false; // 사용자가 일시정지한 경우
  bool _isPreloaded = false; // 프리로드된 컨트롤러인지 여부
  final VideoMuteService _muteService = VideoMuteService();

  @override
  void initState() {
    super.initState();
    // 음소거 서비스 리스너 등록
    _muteService.addListener(_onMuteServiceChanged);

    // 항상 프록시 등록(외부 제어용)
    _registerVideoPlayerController();

    // 🎯 캐시된 컨트롤러가 있으면 재사용, 없으면 초기화
    if (widget.isEditing && editorVideoControllers.containsKey(widget.url)) {
      // 에디터 모드: 캐시된 컨트롤러 재사용
      _controller = editorVideoControllers[widget.url];
      if (_controller != null && _controller!.value.isInitialized) {
        _isInitialized = true;
        _isReadyToPlay = true;
        _controller!.addListener(_onVideoStatusChanged);
        debugPrint('[ClipComponent] 캐시된 컨트롤러 재사용: ${widget.url}');
        if (mounted) {
          setState(() {});
        }
        return;
      }
    } else if (!widget.isEditing &&
        readerVideoControllers.containsKey(widget.url)) {
      // reader 모드: 캐시된 컨트롤러 재사용
      _controller = readerVideoControllers[widget.url];
      if (_controller != null && _controller!.value.isInitialized) {
        _isInitialized = true;
        _isReadyToPlay = true;
        _controller!.addListener(_onVideoStatusChanged);
        debugPrint('[ClipComponent] reader 캐시된 컨트롤러 재사용: ${widget.url}');
        if (mounted) {
          setState(() {});
        }
        return;
      }
    }

    // 캐시된 컨트롤러가 없으면 초기화
    _initializeVideo();
  }

  void _registerVideoPlayerController() {
    final proxy = VideoPlayerControllerProxy();
    proxy.toggleMute = toggleMute;
    proxy.restartVideo = restartVideo;
    proxy.hasPlayedOnce = () => _hasPlayedOnce;
    proxy.pause = _pauseVideo;

    // nodeId 추출 (url을 사용하여 임시로 key 생성)
    final key = 'video_${widget.url.hashCode}';
    videoPlayerControllers[key] = proxy;

    debugPrint('[VideoPlayer] 컨트롤러 등록됨: $key');
  }

  @override
  void dispose() {
    // 음소거 서비스 리스너 제거
    _muteService.removeListener(_onMuteServiceChanged);

    // 컨트롤러 해제
    final key = 'video_${widget.url.hashCode}';
    videoPlayerControllers.remove(key);

    // 리스너 제거
    if (_controller != null) {
      _controller!.removeListener(_onVideoStatusChanged);
    }

    // 🎯 모든 모드에서 직접 생성한 컨트롤러 처리
    if (_controller != null && !_isPreloaded) {
      // 먼저 일시정지
      try {
        if (_controller!.value.isInitialized) {
          _controller!.pause();
        }
      } catch (e) {
        debugPrint('[ClipComponent] pause 오류: $e');
      }

      // reader 모드: 전역 맵에서 제거 (PostReaderScreen dispose에서 dispose 처리)
      if (!widget.isEditing) {
        readerVideoControllers.remove(widget.url);
        debugPrint('[ClipComponent] reader 컨트롤러 일시정지 및 맵에서 제거: ${widget.url}');
        // dispose는 PostReaderScreen에서 처리
      } else {
        // 🎯 에디터 모드: 컨트롤러는 캐시에 남겨두고 dispose하지 않음 (드래그앤드롭 시 재사용)
        // editorVideoControllers에 남겨두어 다음에 재사용 가능
        debugPrint('[ClipComponent] 에디터 컨트롤러 일시정지 (캐시에 유지): ${widget.url}');
      }
    }

    super.dispose();
  }

  @override
  void didUpdateWidget(_VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🎯 URL이 변경된 경우에만 컨트롤러 재초기화
    if (oldWidget.url != widget.url) {
      debugPrint('[ClipComponent] URL 변경 감지: ${oldWidget.url} → ${widget.url}');
      // 기존 컨트롤러 정리
      if (_controller != null) {
        _controller!.removeListener(_onVideoStatusChanged);
        // 컨트롤러는 캐시에 남겨두고, 새 URL로 초기화
        _controller = null;
        _isInitialized = false;
        _isReadyToPlay = false;
      }
      // 새 URL로 초기화
      _initializeVideo();
      return;
    }

    // URL이 동일하면 컨트롤러 재사용 (드래그앤드롭 시 깜빡임 방지)
    if (oldWidget.url == widget.url && _controller == null && !_isInitialized) {
      // 캐시에서 컨트롤러 찾기
      if (widget.isEditing && editorVideoControllers.containsKey(widget.url)) {
        _controller = editorVideoControllers[widget.url];
        if (_controller != null && _controller!.value.isInitialized) {
          _isInitialized = true;
          _isReadyToPlay = true;
          _controller!.addListener(_onVideoStatusChanged);
          debugPrint(
            '[ClipComponent] didUpdateWidget에서 캐시된 컨트롤러 재사용: ${widget.url}',
          );
          if (mounted) {
            setState(() {});
          }
        }
      } else if (!widget.isEditing &&
          readerVideoControllers.containsKey(widget.url)) {
        _controller = readerVideoControllers[widget.url];
        if (_controller != null && _controller!.value.isInitialized) {
          _isInitialized = true;
          _isReadyToPlay = true;
          _controller!.addListener(_onVideoStatusChanged);
          debugPrint(
            '[ClipComponent] didUpdateWidget에서 reader 캐시된 컨트롤러 재사용: ${widget.url}',
          );
          if (mounted) {
            setState(() {});
          }
        }
      }
    }

    // 지연 초기화: 가시성 변화로 재생이 필요해졌는데 컨트롤러가 없으면 초기화
    if (!oldWidget.shouldAutoPlay && widget.shouldAutoPlay) {
      if (_controller == null && !_isInitialized && !widget.isEditing) {
        _initializeVideo();
      }
    }
    // shouldAutoPlay가 변경되면 재생/정지
    if (oldWidget.shouldAutoPlay != widget.shouldAutoPlay &&
        _controller != null &&
        _isInitialized &&
        _isReadyToPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.shouldAutoPlay && !_isPlaying && !_hasPlayedOnce) {
          _playVideo();
        } else if (!widget.shouldAutoPlay && _isPlaying) {
          // 가시성에서 벗어나면 프리로드 여부와 관계없이 일시정지
          _pauseVideo();
        }
      });
    }
  }

  Future<void> _initializeVideo() async {
    try {
      debugPrint('[VideoPlayer] 초기화 시작: ${widget.url}');

      // 🎯 모든 모드에서 직접 컨트롤러 생성 (VideoCacheService 사용 안 함)
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: {'Accept': 'video/*', 'Connection': 'keep-alive'},
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );
      _isPreloaded = false;

      // 직접 초기화
      await _controller!.initialize();

      _isInitialized = true;
      debugPrint('[ClipComponent] 직접 생성 컨트롤러 사용: ${widget.url}');

      // 🎯 전역 맵에 컨트롤러 저장 (드래그앤드롭 시 재사용)
      if (widget.isEditing) {
        editorVideoControllers[widget.url] = _controller!;
        debugPrint('[ClipComponent] 에디터 컨트롤러 등록: ${widget.url}');
      } else {
        readerVideoControllers[widget.url] = _controller!;
        debugPrint('[ClipComponent] reader 컨트롤러 등록: ${widget.url}');
      }

      // 음소거 설정
      await _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);

      // 재생 완료 리스너
      _controller!.addListener(_onVideoStatusChanged);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        debugPrint('[ClipComponent] ✅ 초기화 완료: ${widget.url}');
      }

      // 🎯 첫 프레임이 준비될 때까지 대기 (최대 2초)
      int attempts = 0;
      debugPrint('[ClipComponent] 🔍 첫 프레임 대기 시작: ${widget.url}');
      while (attempts < 20 && mounted && _controller != null) {
        final size = _controller!.value.size;
        final hasFirstFrame = size.width > 0 && size.height > 0;
        final buffered = _controller!.value.buffered;
        final position = _controller!.value.position;

        debugPrint(
          '[ClipComponent] 시도 ${attempts + 1}/20: size=${size.width}x${size.height}, '
          'buffered=${buffered.length}개, position=${position.inMilliseconds}ms',
        );

        if (hasFirstFrame) {
          debugPrint('[ClipComponent] ✅ 첫 프레임 준비 완료: ${widget.url}');
          if (mounted) {
            setState(() {
              _isReadyToPlay = true;
            });
          }
          // 🎯 첫 프레임 준비 후 바로 재생 (뷰포트에 있으면)
          if (widget.shouldAutoPlay) {
            debugPrint(
              '[ClipComponent] 🎬 자동 재생 시작 (shouldAutoPlay=true): ${widget.url}',
            );
            _playVideo();
          } else {
            debugPrint(
              '[ClipComponent] ⏸️ 자동 재생 스킵 (shouldAutoPlay=false): ${widget.url}',
            );
          }
          return;
        }
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      // 타임아웃이어도 첫 프레임이 있으면 재생 준비 완료
      if (mounted && _controller != null) {
        final size = _controller!.value.size;
        final hasFirstFrame = size.width > 0 && size.height > 0;
        if (hasFirstFrame) {
          debugPrint('[ClipComponent] ✅ 타임아웃 후 첫 프레임 확인: ${widget.url}');
          setState(() {
            _isReadyToPlay = true;
          });
          if (widget.shouldAutoPlay) {
            _playVideo();
          }
        } else {
          debugPrint('[ClipComponent] ⚠️ 첫 프레임 없음, 리스너에서 처리: ${widget.url}');
          // 첫 프레임이 없어도 재생 준비 완료로 설정 (리스너에서 처리)
          setState(() {
            _isReadyToPlay = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[VideoPlayer] 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _onVideoStatusChanged() {
    if (_controller == null || !mounted) return; // ✅ mounted 체크 추가

    final position = _controller!.value.position;
    final duration = _controller!.value.duration;
    final isAtEnd = duration > Duration.zero && position >= duration;

    // 🎯 초기화 완료 후 바로 재생 준비 완료로 설정
    if (_isInitialized && !_isReadyToPlay) {
      debugPrint('[ClipComponent] 📝 리스너에서 재생 준비 완료 설정: ${widget.url}');
      setState(() {
        _isReadyToPlay = true;
      });
      // 🎯 뷰포트에 있으면 바로 재생
      if (widget.shouldAutoPlay && !_isPlaying && !_hasPlayedOnce) {
        debugPrint('[ClipComponent] 🎬 리스너에서 자동 재생 시작: ${widget.url}');
        _playVideo();
      }
    }

    // 재생 상태 업데이트 (먼저 실행)
    final isPlaying = _controller!.value.isPlaying;
    final wasPlaying = _isPlaying;

    // 재생 상태 변경 로그
    if (_isPlaying != isPlaying) {
      debugPrint(
        '[ClipComponent] 🔄 재생 상태 변경: $wasPlaying -> $isPlaying, '
        'position=${position.inMilliseconds}ms/${duration.inMilliseconds}ms, url=${widget.url}',
      );
    }

    // 🎯 재생 상태 먼저 업데이트
    if (_isPlaying != isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
        // 🎯 재생 중이었다가 일시정지되면 사용자가 일시정지한 것으로 간주
        // (단, 비디오가 끝나서 일시정지된 경우는 제외)
        if (wasPlaying && !isPlaying) {
          if (!isAtEnd) {
            _isPausedByUser = true;
          } else {
            // 🎯 비디오가 끝났을 때는 일시정지 플래그 해제하고 다시보기 버튼 표시
            _isPausedByUser = false;
            _hasPlayedOnce = true;
          }
        } else if (isPlaying) {
          // 재생이 시작되면 일시정지 플래그 해제
          _isPausedByUser = false;
          // 재생 중이면 다시보기 버튼 숨김
          if (isAtEnd) {
            _hasPlayedOnce = false;
          }
        }
      });
    }

    // 🎯 비디오가 끝났을 때 자동으로 처음부터 돌아가지 않고 일시정지
    if (isAtEnd && isPlaying) {
      // 비디오가 끝났는데 재생 중이면 일시정지하고 다시보기 버튼 표시
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller != null) {
          _controller!.pause();
          setState(() {
            _isPlaying = false;
            _hasPlayedOnce = true;
            _isPausedByUser = false;
          });
        }
      });
      return;
    }

    // 🎯 비디오가 끝났거나 사용자가 일시정지한 경우 다시보기 버튼 표시
    if (duration > Duration.zero) {
      final shouldShowReplay =
          (isAtEnd && !isPlaying) ||
          (_isPausedByUser && !isPlaying && _hasPlayedOnce);

      if (_hasPlayedOnce != shouldShowReplay) {
        setState(() {
          _hasPlayedOnce = shouldShowReplay;
        });
      }
    }
  }

  void _onMuteServiceChanged() {
    // 리더 음소거 상태가 변경되면 비디오 볼륨 조정
    if (_controller != null && _isInitialized) {
      _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);
      if (mounted) setState(() {});
    }
  }

  // 외부에서 호출하기 위한 public 메서드들
  void toggleMute() {
    if (_controller == null) return;
    // 리더 음소거 상태 토글
    _muteService.toggleReaderMute();
  }

  void restartVideo() {
    if (_controller == null) return;
    _controller!.seekTo(Duration.zero);
    _controller!.play();
    setState(() {
      _hasPlayedOnce = false;
      _isPausedByUser = false;
    });
  }

  void _playVideo() {
    if (_controller == null || !_isInitialized || !_isReadyToPlay) {
      debugPrint(
        '[ClipComponent] ❌ 재생 불가: controller=${_controller != null}, '
        'initialized=$_isInitialized, ready=$_isReadyToPlay, url=${widget.url}',
      );
      return;
    }

    final size = _controller!.value.size;
    final buffered = _controller!.value.buffered;
    final position = _controller!.value.position;
    final isCurrentlyPlaying = _controller!.value.isPlaying;

    debugPrint(
      '[ClipComponent] 🎬 _playVideo 호출: url=${widget.url}, '
      'size=${size.width}x${size.height}, buffered=${buffered.length}개, '
      'position=${position.inMilliseconds}ms, isPlaying=$isCurrentlyPlaying',
    );

    // build 중 setState 방지: 프레임 이후에 정지/재생 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller == null) {
        debugPrint(
          '[ClipComponent] ⚠️ _playVideo 취소: mounted=$mounted, controller=${_controller != null}',
        );
        return;
      }
      final key = 'video_${widget.url.hashCode}';
      pauseAllVideosExcept(key);

      final beforePlay = _controller!.value.isPlaying;
      _controller!.play();
      final afterPlay = _controller!.value.isPlaying;

      debugPrint(
        '[ClipComponent] ✅ play() 호출 완료: before=$beforePlay, after=$afterPlay, url=${widget.url}',
      );

      // 재생 시작 시 일시정지 플래그 해제
      if (mounted) {
        setState(() {
          _isPausedByUser = false;
        });
      }
    });
  }

  void _pauseVideo() {
    if (_controller == null) return;
    _controller!.pause();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return AspectRatio(
        aspectRatio: 4 / 5, // 기본 비율
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 38,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                SizedBox(height: 8),
                Text(
                  context.tr('video_load_failed'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    // horizontalPadding을 고려한 실제 비디오 너비
    final videoWidth = screenWidth - (widget.horizontalPadding * 2);
    final maxHeight = videoWidth * 1.5;

    // 🎯 초기화 전 또는 재생 준비 전: 썸네일 또는 쉬머 표시
    if (!_isInitialized || !_isReadyToPlay || _controller == null) {
      // 기본 비율 사용
      final aspectRatio = 16 / 9;
      final calculatedHeight = videoWidth / aspectRatio;
      final finalHeight =
          calculatedHeight > maxHeight ? maxHeight : calculatedHeight;

      // thumbnailPath가 있으면 썸네일 표시
      if (widget.thumbnailPath.isNotEmpty) {
        return SizedBox(
          width: videoWidth,
          height: finalHeight,
          child: ClipRRect(
            child: Image.file(
              File(widget.thumbnailPath),
              fit: BoxFit.contain, // full 모드에서 자연스럽게 높이 늘어나도록 contain 사용
              width: videoWidth,
              height: finalHeight,
            ),
          ),
        );
      }

      return ClipRRect(
        child: ShimmerBox(
          width: videoWidth,
          height: finalHeight,
          isDarkMode: widget.isDarkMode,
        ),
      );
    }

    // 원본 비율 계산
    final videoSize = _controller!.value.size;
    final originalAspectRatio =
        videoSize.height > 0 ? videoSize.width / videoSize.height : 16 / 9;

    // 원본 비율에서 계산한 높이
    final calculatedHeight = videoWidth / originalAspectRatio;
    final finalHeight =
        calculatedHeight > maxHeight ? maxHeight : calculatedHeight;

    // 🎯 AnimatedSwitcher로 부드러운 전환
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: SizedBox(
        key: ValueKey(_isInitialized ? 'video' : 'thumbnail'),
        width: videoWidth,
        height: finalHeight,
        child: Stack(
          children: [
            // 🎯 FittedBox 제거하고 AspectRatio로 원본 비율 유지 (화질 보존)
            // horizontalPadding을 고려한 너비로 비디오 렌더링
            ClipRRect(
              child: SizedBox(
                width: videoWidth,
                height: finalHeight,
                child: AspectRatio(
                  aspectRatio: originalAspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
            // 다시보기 버튼 배경 (한 번 재생 후 표시 또는 사용자가 일시정지한 경우)
            if (_hasPlayedOnce)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    // 다시보기 버튼 탭 시 재생 시작
                    if (_isPausedByUser) {
                      // 사용자가 일시정지한 경우: 현재 위치에서 재생
                      _playVideo();
                    } else {
                      // 비디오가 끝난 경우: 처음부터 재생
                      restartVideo();
                    }
                  },
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.replay, color: Colors.white, size: 24),
                            SizedBox(width: 8),
                            Text(
                              context.tr('replay'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 음소거 버튼
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: toggleMute,
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _muteService.isReaderMuted
                        ? Icons.volume_off
                        : Icons.volume_up,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
