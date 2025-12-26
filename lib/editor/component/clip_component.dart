import 'dart:typed_data';
import 'dart:io';
import 'dart:async';

import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:super_editor/super_editor.dart';
import 'package:doppy/editor/service/drag_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
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

/// 🎯 비디오 썸네일 캐시 (URL을 키로 사용, ClipComponent와 드래그 오버레이에서 공유)
final videoThumbnailCache = <String, Uint8List>{};

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

  // 🎯 1단계: 모든 비디오 일시정지 및 리스너 제거 (setState 방지)
  for (final entry in videoPlayerControllers.entries) {
    final controller = entry.value;
    // 모든 비디오 일시정지
    controller.pause?.call();
  }
  // 맵 비우기
  videoPlayerControllers.clear();

  // 🎯 2단계: 에디터 모드 비디오 컨트롤러의 모든 리스너 제거 후 dispose
  final urlsToRemove = <String>[];
  final controllersToDispose = <VideoPlayerController>[];

  for (final entry in editorVideoControllers.entries) {
    try {
      final controller = entry.value;

      // 🎯 먼저 일시정지 (리스너가 호출될 수 있으므로 먼저)
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
        }
      } catch (e) {
        debugPrint('[ClipComponent] 일시정지 오류 (${entry.key}): $e');
      }

      // 🎯 리스너는 각 ClipComponent의 dispose에서 제거되지만,
      // 게시 중에는 위젯이 아직 dispose되지 않았을 수 있으므로
      // 여기서는 맵에서 먼저 제거하여 새로운 리스너 등록 방지
      controllersToDispose.add(controller);
      urlsToRemove.add(entry.key);
    } catch (e) {
      debugPrint('[ClipComponent] 에디터 컨트롤러 정리 오류 (${entry.key}): $e');
      urlsToRemove.add(entry.key); // 오류가 나도 맵에서 제거
    }
  }

  // 🎯 3단계: 맵에서 먼저 제거 (리스너가 다시 추가되는 것 방지)
  for (final url in urlsToRemove) {
    editorVideoControllers.remove(url);
  }

  // 🎯 4단계: 컨트롤러 dispose (맵에서 제거된 후)
  for (final controller in controllersToDispose) {
    try {
      controller.dispose();
    } catch (e) {
      debugPrint('[ClipComponent] 컨트롤러 dispose 오류: $e');
    }
  }

  debugPrint('[ClipComponent] 모든 비디오 플레이어 정리 완료 (${urlsToRemove.length}개)');
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
  bool get isDeletable => true;
  String get nodeType => 'clip';

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
    required this.screenWidth, // 🎯 외부에서 전달받음
    this.dragService,
    this.isEditing = false,
    this.isDarkMode = false,
  });
  final double screenWidth; // 🚀 한 번만 계산된 화면 너비
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
        screenWidth: screenWidth, // 🚀 전달
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
    required this.screenWidth, // 🎯 외부에서 전달받음
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
  final double screenWidth; // 🚀 최고 효율: 외부에서 한 번만 계산된 값
  final DragService? dragService;
  final bool isEditing;
  final bool isDarkMode;

  @override
  State<_ClipComponent> createState() => _ClipComponentState();
}

class _ClipComponentState extends State<_ClipComponent> with DocumentComponent {
  GlobalKey get componentKey => widget._componentKey;

  // 특수 영역(음소거 버튼, 다시보기 버튼) 탭 여부
  bool _clipNodeSpecialAreaTapped = false;
  // 🎯 특수 노드 사이 클릭 감지 플래그
  bool _isSpecialNodeGapTap = false;

  // 🎯 싱글 이미지와 동일: 드롭라인용 마진 상수
  static const double marginTop = 2.5;
  static const double marginBottom = 2.5;

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

  // 🎯 특수 노드 사이 클릭 감지 (true: 특수 노드 사이 클릭, false: 일반 클릭)
  bool _handleSpecialNodeTap(Offset globalPosition) {
    if (widget.dragService == null) return false;
    final editorService = widget.dragService!.editorService;
    final doc = editorService.document;
    final dragService = widget.dragService!;

    // 자신의 인덱스와 Rect 확인
    final currentNodeIndex = doc.getNodeIndexById(widget.nodeId);
    if (currentNodeIndex == -1) return false;

    final nodeRect = dragService.getNodeGlobalRect(widget.nodeId);
    if (nodeRect == null) return false;

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
              return true;
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
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  double? _metadataAspectRatio; // metadata에서 가져온 비율 (캐싱)

  // 🎯 metadata에서 비율 정보를 한 번만 가져오기 (플레이스홀더용)
  void _loadMetadataAspectRatio() {
    if (_metadataAspectRatio != null) return; // 이미 로드됨

    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      // ignore: invalid_use_of_visible_for_testing_member
      final doc = seState?.editContext.editor.document;
      final node = doc?.getNodeById(widget.nodeId);
      if (node is ClipNode) {
        final aspectRatioValue = node.metadata['aspectRatio'];
        if (aspectRatioValue != null) {
          _metadataAspectRatio =
              (aspectRatioValue is num)
                  ? aspectRatioValue.toDouble()
                  : double.tryParse(aspectRatioValue.toString());
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 읽기/편집 모드 통합: 특수 노드 간격 확인 로직 통일
    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    final doc = seState?.editContext.editor.document;
    // ignore: invalid_use_of_visible_for_testing_member
    final composerSelection =
        widget.isEditing ? seState?.editContext.composer.selection : null;

    // 이웃하는 특수 노드 체크
    final bool hasImageAbove =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow =
        doc == null ? false : _hasNeighborImage(doc, widget.nodeId, 1);

    // 🎯 업로드 중 상태 확인 (편집 모드에서만, 읽기 전용 모드에서는 항상 false)
    bool isUploading = false;
    if (widget.isEditing) {
      try {
        isUploading = context.select<UploadService, bool>(
          (service) => service.hasActiveUploadForRef(widget.nodeId),
        );
      } catch (e) {
        debugPrint('[ClipComponent] UploadService 확인 실패: $e');
      }
    }

    // 🎯 성능 최적화: context.watch → context.select로 변경
    final isSelected = context.select<NodeComponentService, bool>(
      (service) => service.selectedImageId == widget.nodeId,
    );

    // downstream 위치에 커서가 있을 때도 selection 효과 표시
    bool isDownstreamSelected = false;
    if (composerSelection != null &&
        composerSelection.isCollapsed &&
        composerSelection.extent.nodeId == widget.nodeId) {
      final position = composerSelection.extent.nodePosition;
      if (position is UpstreamDownstreamNodePosition &&
          position == const UpstreamDownstreamNodePosition.downstream()) {
        isDownstreamSelected = true;
      }
    }

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

    // 댓글 배지 표시 여부 및 패딩 모드 확인 (디버그용)
    bool hasCommentsFlag = false;
    String? currentPaddingMode;
    try {
      final node = doc?.getNodeById(widget.nodeId);
      if (node is ClipNode) {
        final meta = node.metadata;
        hasCommentsFlag = meta['hasComments'] == true;
        currentPaddingMode = meta['padding'] as String? ?? 'center';
        debugPrint(
          '[ClipComponent] build 호출: nodeId=${widget.nodeId}, paddingMode=$currentPaddingMode, metadata=$meta',
        );
      }
    } catch (_) {}

    // 🎯 싱글 이미지와 동일한 레이아웃: RepaintBoundary + Column 구조
    return RepaintBoundary(
      child: Column(
        children: [
          if (!hasImageAbove)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
          // 실제 비디오 내용 + 좌/우 세로 라인 (머지 모드에서)
          LayoutBuilder(
            builder: (context, constraints) {
              debugPrint(
                '[ClipComponent] LayoutBuilder 호출: nodeId=${widget.nodeId}, constraints.maxWidth=${constraints.maxWidth}, screenWidth=${widget.screenWidth}',
              );

              // 🎯 싱글 이미지와 동일: constraints를 통해 스타일시트 패딩 자동 반영
              // 🎯 paddingMode를 ValueKey에 포함하여 리빌드 트리거
              final video = RepaintBoundary(
                key: ValueKey(
                  'clip_video_${widget.nodeId}_$currentPaddingMode',
                ),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: _buildVideoContent(context),
                ),
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
                              final isGapTap = _handleSpecialNodeTap(
                                details.globalPosition,
                              );

                              // 특수 영역(음소거 버튼, 다시보기 버튼) 감지
                              final action = widget.dragService!
                                  .handleClipNodeTap(
                                    widget.nodeId,
                                    details.globalPosition,
                                  );
                              if (action != null) {
                                // 특수 영역이면 action 실행
                                _triggerClipNodeAction(action);
                                setState(() {
                                  _clipNodeSpecialAreaTapped = true;
                                  _isSpecialNodeGapTap = false;
                                });
                              } else {
                                setState(() {
                                  _clipNodeSpecialAreaTapped = false;
                                  _isSpecialNodeGapTap = isGapTap;
                                });
                              }
                            }
                            : null,
                    onTap:
                        widget.isEditing && widget.dragService != null
                            ? () {
                              // 🎯 특수 노드 사이 클릭이면 셀렉 보류
                              if (_isSpecialNodeGapTap) {
                                setState(() {
                                  _isSpecialNodeGapTap = false;
                                });
                                return;
                              }

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
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    widget.dragService
                                        ?.invalidateNodeRectCache();
                                  }
                                });
                              }
                            }
                            : null,
                    onLongPressStart:
                        widget.isEditing && widget.dragService != null
                            ? (details) {
                              // 🎯 키보드 내리기 + 포커스 해제 (드래그 시작 시)
                              FocusManager.instance.primaryFocus?.unfocus();
                              FocusScope.of(context).unfocus();
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
                          video,
                          if (hasCommentsFlag)
                            Positioned(
                              top: 4,
                              right: 5,
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
                          // 🎯 업로드 중 오버레이는 _VideoPlayerWidget 내부에서 처리
                          if (isSelectionHighlighted)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  color: AppColors.primary.withOpacity(0.4),
                                ),
                              ),
                            ),
                          if (isSelected || isDownstreamSelected)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
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
                  if (!isUploading && _shouldShowTopDropLine())
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Container(height: 5, color: AppColors.primary),
                      ),
                    ),
                  if (!isUploading && _shouldShowLeftVerticalLine())
                    Positioned(
                      top: marginTop,
                      bottom: marginBottom,
                      left: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Container(width: 5, color: AppColors.primary),
                      ),
                    ),
                  if (!isUploading && _shouldShowRightVerticalLine())
                    Positioned(
                      top: marginTop,
                      bottom: marginBottom,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Container(width: 5, color: AppColors.primary),
                      ),
                    ),
                  if (!isUploading && _shouldShowBottomDropLine())
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Container(height: 5, color: AppColors.primary),
                      ),
                    ),
                ],
              );
            },
          ),
          if (!hasImageBelow)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
        ],
      ),
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
    if (box == null) return Rect.zero;

    // upstream/downstream 위치일 때는 커서를 표시하지 않음 (사용자 요청)
    // selection 효과만 표시
    if (nodePosition is UpstreamDownstreamNodePosition) {
      return Offset.zero & box.size;
    }

    return Offset.zero & box.size;
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
      // 🎯 upstream 위치로 커서가 가지 못하도록 항상 downstream 반환
      const UpstreamDownstreamNodePosition.downstream();
  @override
  NodePosition getEndPositionNearX(double x) =>
      const UpstreamDownstreamNodePosition.downstream();
  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  // 드래그 삽입 라인 표시 로직
  bool _shouldShowLeftVerticalLine() {
    return DropLineConfig.shouldShowLeftVerticalLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowRightVerticalLine() {
    return DropLineConfig.shouldShowRightVerticalLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowTopDropLine() {
    return DropLineConfig.shouldShowTopDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowBottomDropLine() {
    return DropLineConfig.shouldShowBottomDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
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

    // 🎯 바로 인접한 노드 확인
    final immediateIndex = myIndex + direction;
    if (immediateIndex >= 0 && immediateIndex < doc.nodeCount) {
      final immediateNeighbor = doc.getNodeAt(immediateIndex);
      if (immediateNeighbor != null) {
        // 바로 인접한 노드가 특수 노드인 경우
        if (immediateNeighbor is ImageNode ||
            immediateNeighbor is ImageRowNode ||
            immediateNeighbor is ClipNode ||
            immediateNeighbor is LinkNode) {
          return true;
        }

        // 바로 인접한 노드가 빈 ParagraphNode인 경우
        if (immediateNeighbor is ParagraphNode) {
          final isEmpty = immediateNeighbor.text.text.trim().isEmpty;
          final isTitle = immediateNeighbor.metadata['isTitle'] == true;

          // 빈 ParagraphNode면 그 다음 노드를 확인
          if (!isTitle && isEmpty) {
            // 빈 ParagraphNode 다음 노드 확인
            final nextIndex = immediateIndex + direction;
            if (nextIndex >= 0 && nextIndex < doc.nodeCount) {
              final nextNeighbor = doc.getNodeAt(nextIndex);
              if (nextNeighbor is ImageNode ||
                  nextNeighbor is ImageRowNode ||
                  nextNeighbor is ClipNode ||
                  nextNeighbor is LinkNode) {
                // 빈 ParagraphNode를 사이에 둔 특수 노드 → 패딩 필요 (false 반환)
                return false;
              }
            }
            // 빈 ParagraphNode 다음에 특수 노드가 없으면 계속 검색
          } else if (!isTitle && !isEmpty) {
            // 텍스트가 있는 ParagraphNode → 패딩 필요
            return false;
          }
        } else {
          // 다른 타입의 노드면 패딩 필요
          return false;
        }
      }
    }

    // 🎯 빈 ParagraphNode를 건너뛰고 실제 특수 노드나 텍스트가 있는 노드를 찾음
    int searchIndex = myIndex + direction;
    while (searchIndex >= 0 && searchIndex < doc.nodeCount) {
      final neighbor = doc.getNodeAt(searchIndex);
      if (neighbor == null) break;

      // 특수 노드인 경우
      if (neighbor is ImageNode ||
          neighbor is ImageRowNode ||
          neighbor is ClipNode ||
          neighbor is LinkNode) {
        return true;
      }

      // 빈 ParagraphNode가 아니면 (텍스트가 있는 경우) 패딩 필요
      if (neighbor is ParagraphNode) {
        final isEmpty = neighbor.text.text.trim().isEmpty;
        final isTitle = neighbor.metadata['isTitle'] == true;
        // 제목이 아니고 비어있지 않으면 텍스트 노드이므로 패딩 필요
        if (!isTitle && !isEmpty) {
          return false; // 텍스트 노드가 있으면 패딩 필요
        }
        // 빈 ParagraphNode면 계속 검색
      } else {
        // 다른 타입의 노드면 패딩 필요
        return false;
      }

      searchIndex += direction;
    }

    return false;
  }

  Widget _buildVideoContent(BuildContext context) {
    // 🎯 싱글 이미지와 동일: 부모 constraints를 따름 (스타일시트가 패딩을 자동으로 적용)

    // 🎯 업로드 중 상태 확인 (편집 모드에서만, Selector로 최적화)
    bool isUploading = false;
    if (widget.isEditing) {
      try {
        isUploading = context.select<UploadService, bool>(
          (service) => service.hasActiveUploadForRef(widget.nodeId),
        );
      } catch (e) {
        debugPrint('[ClipComponent] UploadService 확인 실패: $e');
      }
    }

    // 🎯 로컬 파일 경로가 있으면 바로 비디오 플레이어 표시 (썸네일 X)
    if (widget.localPath.isNotEmpty) {
      // 로컬 비디오를 바로 재생
      return RepaintBoundary(
        child: _VisibilityAwareVideoPlayer(
          key: ValueKey('local_video_${widget.localPath}_${widget.nodeId}'),
          nodeId: widget.nodeId,
          url: '', // 로컬이므로 url은 빈 문자열
          localPath: widget.localPath,
          thumbnailPath: widget.thumbnailPath,
          isEditing: widget.isEditing,
          isDarkMode: widget.isDarkMode,
          horizontalPadding: 0.0, // 🎯 더 이상 사용 안 함
          isUploading: isUploading, // 업로드 중 표시
          dragService: widget.dragService, // 🎯 dragService 전달
        ),
      );
    }

    // 네트워크 URL이 있으면 비디오 플레이어
    if (widget.url.isNotEmpty) {
      // 🎯 썸네일은 _VideoPlayerWidget 내부에서 처리하므로 여기서는 비디오 플레이어만 반환
      return RepaintBoundary(
        child: _VisibilityAwareVideoPlayer(
          key: ValueKey('video_${widget.url}_${widget.nodeId}'),
          nodeId: widget.nodeId, // 🎯 nodeId 전달 (metadata 접근용)
          url: widget.url,
          thumbnailPath: widget.thumbnailPath,
          isEditing: widget.isEditing,
          isDarkMode: widget.isDarkMode,
          horizontalPadding: 0.0, // 🎯 더 이상 사용 안 함
          dragService: widget.dragService, // 🎯 dragService 전달
        ),
      );
    }

    // 🎯 url도 localPath도 없으면 shimmer 표시 (텍스트 깜빡임 방지)
    _loadMetadataAspectRatio();
    final double aspect = _metadataAspectRatio ?? (16 / 9);
    // 🎯 싱글 이미지와 동일: AspectRatio만 사용 (부모 constraints를 따름)
    return AspectRatio(
      aspectRatio: aspect,
      child: ShimmerBox(
        width: 0.0, // 부모 constraints 따름
        height: 0.0,
        isDarkMode: widget.isDarkMode,
      ),
    );
  }
}

/// 가시성 감지 래퍼
class _VisibilityAwareVideoPlayer extends StatefulWidget {
  final String nodeId; // 🎯 nodeId 추가 (metadata 접근용)
  final String url;
  final String localPath; // 🎯 로컬 비디오 경로
  final String thumbnailPath;
  final bool isEditing;
  final bool isDarkMode;
  final double horizontalPadding; // 🎯 더 이상 사용 안 함
  final bool isUploading; // 🎯 업로드 중 표시
  final DragService? dragService; // 🎯 dragService 추가 (EditorService 접근용)

  const _VisibilityAwareVideoPlayer({
    super.key,
    required this.nodeId,
    required this.url,
    this.localPath = '',
    required this.thumbnailPath,
    required this.isEditing,
    this.isDarkMode = false,
    required this.horizontalPadding, // 🎯 더 이상 사용 안 함
    this.isUploading = false,
    this.dragService, // 🎯 dragService 추가
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

  bool _isDisposed = false; // dispose 플래그
  Timer? _visibilityTimer; // 타이머 추적

  void _checkVisibility() {
    // 🎯 dispose되었거나 mounted가 아니면 중단
    if (_isDisposed || !mounted) return;

    // 🎯 성능 최적화: 가시성 체크 주기를 100ms → 300ms로 증가 (스크롤 버벅임 방지)
    _visibilityTimer?.cancel(); // 기존 타이머 취소
    _visibilityTimer = Timer(Duration(milliseconds: 300), () {
      // 🎯 타이머 콜백 실행 시점에 다시 확인 (dispose 후 실행될 수 있음)
      if (_isDisposed || !mounted) return;

      try {
        _updateVisibility();
      } catch (e) {
        debugPrint('[VisibilityAwareVideoPlayer] _updateVisibility error: $e');
        return;
      }

      // 🎯 dispose되지 않았을 때만 재귀 호출
      if (!_isDisposed && mounted) {
        _checkVisibility();
      }
    });
  }

  void _updateVisibility() {
    // 🎯 mounted 체크 (가장 먼저)
    if (!mounted || _isDisposed) return;

    final elementContext = _key.currentContext;
    if (elementContext == null) return;

    // 🎯 context가 active 상태인지 엄격하게 확인
    if (!elementContext.mounted) return;

    // 🎯 owner가 null이면 inactive 상태
    if (elementContext.owner == null) return;

    // 🎯 성능 최적화: addPostFrameCallback 대신 직접 체크 (불필요한 프레임 지연 제거)
    // 🎯 콜백 실행 시점에 다시 확인
    if (!mounted || _isDisposed) return;

    final currentContext = _key.currentContext;
    if (currentContext == null ||
        !currentContext.mounted ||
        currentContext.owner == null) {
      return;
    }

    RenderBox? renderBox;
    try {
      renderBox = currentContext.findRenderObject() as RenderBox?;
    } catch (e) {
      // inactive element에서 findRenderObject 호출 시 에러 발생 가능
      // 에러 로그는 출력하지 않음 (너무 많이 출력됨)
      return;
    }

    if (renderBox == null || !renderBox.attached) return;

    // 🎯 mounted 재확인
    if (!mounted || _isDisposed) return;

    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);

    // 🎯 MediaQuery 호출 전 mounted 재확인
    if (!mounted || _isDisposed) return;

    double screenHeight;
    try {
      screenHeight = MediaQuery.of(this.context).size.height;
    } catch (e) {
      return;
    }

    final viewportTop = 0.0;
    final viewportBottom = screenHeight;

    // 화면에 보이는 비율 계산
    final visibleTop = math.max(position.dy, viewportTop);
    final visibleBottom = math.min(position.dy + size.height, viewportBottom);
    final visibleHeight = math.max(0.0, visibleBottom - visibleTop);
    final visibleRatio = size.height > 0 ? visibleHeight / size.height : 0.0;

    // 기준 상향: 최소 70%가 보이면 재생
    final isVisible = visibleRatio >= 0.7;

    if (_isVisible != isVisible) {
      // 🎯 성능 최적화: setState를 다음 프레임으로 지연 (스크롤 중 버벅임 방지)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed && _isVisible != isVisible) {
          setState(() {
            _isVisible = isVisible;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    // 🎯 dispose 플래그 설정하여 재귀 호출 중단
    _isDisposed = true;

    // 🎯 타이머 취소
    _visibilityTimer?.cancel();
    _visibilityTimer = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 성능 최적화: RepaintBoundary로 감싸서 불필요한 repaint 방지
    return RepaintBoundary(
      child: Container(
        key: _key,
        child: _VideoPlayerWidget(
          nodeId: widget.nodeId, // 🎯 nodeId 전달
          url: widget.url,
          localPath: widget.localPath,
          thumbnailPath: widget.thumbnailPath,
          shouldAutoPlay: _isVisible,
          isEditing: widget.isEditing,
          isDarkMode: widget.isDarkMode,
          horizontalPadding: widget.horizontalPadding,
          isUploading: widget.isUploading,
          dragService: widget.dragService, // 🎯 dragService 전달
        ),
      ),
    );
  }
}

/// 비디오 플레이어 위젯
class _VideoPlayerWidget extends StatefulWidget {
  final String nodeId; // 🎯 nodeId 추가 (metadata 접근용)
  final String url;
  final String localPath; // 🎯 로컬 비디오 경로
  final String thumbnailPath;
  final bool shouldAutoPlay;
  final bool isEditing;
  final bool isDarkMode;
  final double horizontalPadding; // 🎯 더 이상 사용 안 함
  final bool isUploading; // 🎯 업로드 중 표시
  final DragService? dragService; // 🎯 dragService 추가 (EditorService 접근용)

  const _VideoPlayerWidget({
    required this.nodeId,
    required this.url,
    this.localPath = '',
    required this.thumbnailPath,
    this.shouldAutoPlay = true,
    required this.isEditing,
    this.isDarkMode = false,
    required this.horizontalPadding, // 🎯 더 이상 사용 안 함
    this.isUploading = false,
    this.dragService, // 🎯 dragService 추가
  });

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  /// 🎯 썸네일 이미지 또는 쉬머 위젯 빌드 (에러 처리 포함)
  Widget _buildThumbnailOrShimmer({
    required String thumbnailPath,
    required double width,
    required double height,
  }) {
    if (thumbnailPath.isEmpty) {
      return ShimmerBox(
        width: width,
        height: height,
        isDarkMode: widget.isDarkMode,
      );
    }

    return ClipRRect(
      child: Image.file(
        File(thumbnailPath),
        key: ValueKey('thumbnail_$thumbnailPath'), // 🎯 스택 오버플로우 방지: key 추가
        fit: BoxFit.contain, // 🎯 싱글 이미지와 동일: contain으로 비율 유지
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) {
          // 🎯 썸네일 로딩 실패 시 쉬머 표시 (임시저장 불러올 때 에러 위젯 방지)
          // 🎯 스택 오버플로우 방지: errorBuilder에서 반환하는 위젯에 key 추가
          return ShimmerBox(
            key: ValueKey('shimmer_$thumbnailPath'),
            width: width,
            height: height,
            isDarkMode: widget.isDarkMode,
          );
        },
      ),
    );
  }

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isReadyToPlay = false; // 🎯 실제 재생 준비 완료 여부 (버퍼링 포함)
  bool _hasError = false;
  bool _hasPlayedOnce = false;
  bool _isPlaying = false;
  bool _isPausedByUser = false; // 사용자가 일시정지한 경우
  bool _isPreloaded = false; // 프리로드된 컨트롤러인지 여부
  bool _isDisposed = false; // 🎯 dispose 플래그
  final VideoMuteService _muteService = VideoMuteService();
  double? _metadataAspectRatio; // metadata에서 가져온 비율 (캐싱)

  @override
  void initState() {
    super.initState();

    // 🎯 메타데이터에서 aspectRatio 미리 로드 (SingleImageComponent와 동일)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMetadataAspectRatio();
    });

    // 음소거 서비스 리스너 등록
    _muteService.addListener(_onMuteServiceChanged);

    // 항상 프록시 등록(외부 제어용)
    _registerVideoPlayerController();

    // 🎯 캐시된 컨트롤러가 있으면 재사용, 없으면 초기화
    if (widget.isEditing && editorVideoControllers.containsKey(widget.url)) {
      // 에디터 모드: 캐시된 컨트롤러 재사용
      final cachedController = editorVideoControllers[widget.url];
      // 🎯 dispose된 컨트롤러는 재사용하지 않음
      if (cachedController != null) {
        try {
          // 컨트롤러가 유효한지 확인 (접근 시도)
          final isInitialized = cachedController.value.isInitialized;
          if (isInitialized) {
            _controller = cachedController;
            _isInitialized = true;
            _isReadyToPlay = true;
            _controller!.addListener(_onVideoStatusChanged);
            // 🎯 초기 음소거 상태 동기화
            _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);
            debugPrint('[ClipComponent] 캐시된 컨트롤러 재사용: ${widget.url}');
            if (mounted) {
              setState(() {});
            }
            return;
          }
        } catch (e) {
          debugPrint(
            '[ClipComponent] 캐시된 컨트롤러가 dispose됨, 새로 생성: ${widget.url} - $e',
          );
          // dispose된 컨트롤러는 맵에서 제거
          editorVideoControllers.remove(widget.url);
        }
      }
    } else if (!widget.isEditing &&
        readerVideoControllers.containsKey(widget.url)) {
      // reader 모드: 캐시된 컨트롤러 재사용
      final cachedController = readerVideoControllers[widget.url];
      if (cachedController != null) {
        try {
          // 컨트롤러가 유효한지 확인 (접근 시도)
          final isInitialized = cachedController.value.isInitialized;
          if (isInitialized) {
            _controller = cachedController;
            _isInitialized = true;
            _isReadyToPlay = true;
            _controller!.addListener(_onVideoStatusChanged);
            // 🎯 초기 음소거 상태 동기화
            _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);
            debugPrint('[ClipComponent] reader 캐시된 컨트롤러 재사용: ${widget.url}');
            if (mounted) {
              setState(() {});
            }
            return;
          }
        } catch (e) {
          debugPrint(
            '[ClipComponent] reader 캐시된 컨트롤러가 dispose됨, 새로 생성: ${widget.url} - $e',
          );
          // dispose된 컨트롤러는 맵에서 제거
          readerVideoControllers.remove(widget.url);
        }
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
    // 🎯 dispose 플래그 설정 (리스너가 setState 호출 방지)
    _isDisposed = true;

    // 음소거 서비스 리스너 제거
    _muteService.removeListener(_onMuteServiceChanged);

    // 컨트롤러 해제
    final key = 'video_${widget.url.hashCode}';
    videoPlayerControllers.remove(key);

    // 리스너 제거 (dispose 전에 먼저 제거하여 콜백 방지)
    if (_controller != null) {
      try {
        _controller!.removeListener(_onVideoStatusChanged);
      } catch (e) {
        debugPrint('[ClipComponent] 리스너 제거 오류: $e');
      }
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
        final cachedController = editorVideoControllers[widget.url];
        if (cachedController != null) {
          try {
            // 컨트롤러가 유효한지 확인 (접근 시도)
            final isInitialized = cachedController.value.isInitialized;
            if (isInitialized) {
              _controller = cachedController;
              _isInitialized = true;
              _isReadyToPlay = true;
              _controller!.addListener(_onVideoStatusChanged);
              // 🎯 초기 음소거 상태 동기화
              _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);
              debugPrint(
                '[ClipComponent] didUpdateWidget에서 캐시된 컨트롤러 재사용: ${widget.url}',
              );
              if (mounted) {
                setState(() {});
              }
            }
          } catch (e) {
            debugPrint(
              '[ClipComponent] didUpdateWidget: 캐시된 컨트롤러가 dispose됨, 새로 생성: ${widget.url} - $e',
            );
            // dispose된 컨트롤러는 맵에서 제거
            editorVideoControllers.remove(widget.url);
          }
        }
      } else if (!widget.isEditing &&
          readerVideoControllers.containsKey(widget.url)) {
        final cachedController = readerVideoControllers[widget.url];
        if (cachedController != null) {
          try {
            // 컨트롤러가 유효한지 확인 (접근 시도)
            final isInitialized = cachedController.value.isInitialized;
            if (isInitialized) {
              _controller = cachedController;
              _isInitialized = true;
              _isReadyToPlay = true;
              _controller!.addListener(_onVideoStatusChanged);
              // 🎯 초기 음소거 상태 동기화
              _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);
              debugPrint(
                '[ClipComponent] didUpdateWidget에서 reader 캐시된 컨트롤러 재사용: ${widget.url}',
              );
              if (mounted) {
                setState(() {});
              }
            }
          } catch (e) {
            debugPrint(
              '[ClipComponent] didUpdateWidget: reader 캐시된 컨트롤러가 dispose됨, 새로 생성: ${widget.url} - $e',
            );
            // dispose된 컨트롤러는 맵에서 제거
            readerVideoControllers.remove(widget.url);
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
    // 🎯 위젯이 dispose되었는지 확인
    if (!mounted) {
      debugPrint('[ClipComponent] 초기화 취소: 위젯이 dispose됨 - ${widget.url}');
      return;
    }

    try {
      debugPrint(
        '[VideoPlayer] 초기화 시작: URL=${widget.url}, Local=${widget.localPath}',
      );

      // 🎯 프리로드된 컨트롤러 확인 및 재사용
      VideoPlayerController? controller;
      bool isPreloaded = false;
      final cacheKey =
          widget.localPath.isNotEmpty ? widget.localPath : widget.url;

      if (!widget.isEditing) {
        // Reader 모드: readerVideoControllers에서 확인
        controller = readerVideoControllers[cacheKey];
        if (controller != null && controller.value.isInitialized) {
          isPreloaded = true;
          debugPrint('[ClipComponent] ✅ 프리로드된 컨트롤러 재사용: $cacheKey');
        } else {
          controller = null; // 무효한 컨트롤러는 무시
        }
      } else {
        // Editor 모드: editorVideoControllers에서 확인
        controller = editorVideoControllers[cacheKey];
        if (controller != null && controller.value.isInitialized) {
          isPreloaded = true;
          debugPrint('[ClipComponent] ✅ 에디터 캐시 컨트롤러 재사용: $cacheKey');
        } else {
          controller = null;
        }
      }

      // 프리로드된 컨트롤러가 없으면 새로 생성
      if (controller == null) {
        // 🎯 로컬 비디오 우선, 없으면 네트워크 URL 사용
        if (widget.localPath.isNotEmpty) {
          controller = VideoPlayerController.file(
            File(widget.localPath),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: false,
            ),
          );
          debugPrint('[ClipComponent] 🔄 새 로컬 컨트롤러 생성: ${widget.localPath}');
        } else {
          controller = VideoPlayerController.networkUrl(
            Uri.parse(widget.url),
            httpHeaders: {'Accept': 'video/*', 'Connection': 'keep-alive'},
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: false,
            ),
          );
          debugPrint('[ClipComponent] 🔄 새 네트워크 컨트롤러 생성: ${widget.url}');
        }
        isPreloaded = false;
      }

      _isPreloaded = isPreloaded;

      // 🎯 위젯이 dispose되었는지 다시 확인
      if (!mounted) {
        try {
          controller.dispose();
        } catch (_) {}
        debugPrint('[ClipComponent] 초기화 취소: 컨트롤러 생성 후 dispose됨 - $cacheKey');
        return;
      }

      _controller = controller;

      // 🎯 프리로드된 컨트롤러가 아니면 초기화 필요
      if (!isPreloaded) {
        await _controller!.initialize();

        // 🎯 초기화 완료 후에도 위젯이 살아있는지 확인
        if (!mounted) {
          try {
            _controller!.dispose();
          } catch (_) {}
          _controller = null;
          debugPrint('[ClipComponent] 초기화 취소: 초기화 완료 후 dispose됨 - $cacheKey');
          return;
        }
      } else {
        // 프리로드된 컨트롤러는 이미 초기화됨
        debugPrint('[ClipComponent] ✅ 프리로드된 컨트롤러 - 초기화 스킵: $cacheKey');
      }

      _isInitialized = true;

      // 🎯 전역 맵에 컨트롤러 저장 (드래그앤드롭 시 재사용)
      // 🎯 프리로드된 컨트롤러는 이미 맵에 있으므로 중복 저장 방지
      if (!isPreloaded) {
        if (widget.isEditing) {
          // 기존 컨트롤러가 있으면 dispose 후 교체
          final existing = editorVideoControllers[cacheKey];
          if (existing != null && existing != _controller) {
            try {
              if (existing.value.isInitialized) {
                existing.pause();
              }
              existing.dispose();
            } catch (e) {
              debugPrint('[ClipComponent] 기존 에디터 컨트롤러 정리 오류: $e');
            }
          }
          editorVideoControllers[cacheKey] = _controller!;
          debugPrint('[ClipComponent] 에디터 컨트롤러 등록: $cacheKey');
        } else {
          // Reader 모드: 프리로드되지 않은 경우에만 저장
          final existing = readerVideoControllers[cacheKey];
          if (existing != null && existing != _controller) {
            try {
              if (existing.value.isInitialized) {
                existing.pause();
              }
              existing.dispose();
            } catch (e) {
              debugPrint('[ClipComponent] 기존 reader 컨트롤러 정리 오류: $e');
            }
          }
          readerVideoControllers[cacheKey] = _controller!;
          debugPrint('[ClipComponent] reader 컨트롤러 등록: $cacheKey');
        }
      } else {
        debugPrint('[ClipComponent] 프리로드된 컨트롤러 - 맵 저장 스킵: $cacheKey');
      }

      // 음소거 설정
      if (mounted && _controller != null) {
        try {
          await _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);
        } catch (e) {
          debugPrint('[ClipComponent] 볼륨 설정 오류: $e');
        }
      }

      // 🎯 편집 모드에서 aspectRatio 메타데이터 저장 (SingleImageComponent와 동일)
      if (widget.isEditing && _controller != null && !isPreloaded) {
        final videoSize = _controller!.value.size;
        if (videoSize.width > 0 && videoSize.height > 0) {
          final aspectRatio = videoSize.width / videoSize.height;
          _saveAspectRatioToMetadata(aspectRatio);
        }
      }

      // 재생 완료 리스너
      if (mounted && _controller != null) {
        _controller!.addListener(_onVideoStatusChanged);
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        debugPrint('[ClipComponent] ✅ 초기화 완료: $cacheKey');
      }

      // 🎯 썸네일이 캐시에 없으면 생성 (비동기로 실행하여 초기화 지연 방지)
      // 로컬 비디오는 썸네일 생성 스킵 (이미 thumbnailPath가 있음)
      if (mounted &&
          widget.localPath.isEmpty &&
          !videoThumbnailCache.containsKey(cacheKey)) {
        _generateThumbnailForCache(cacheKey);
      }

      // 🎯 재생 준비 완료 설정
      // 프리로드된 컨트롤러는 이미 준비되어 있으므로 즉시 설정
      if (mounted && _controller != null) {
        try {
          // 컨트롤러가 여전히 유효한지 확인
          final _ = _controller!.value.isInitialized;
          setState(() {
            _isReadyToPlay = true;
          });

          if (isPreloaded) {
            debugPrint(
              '[ClipComponent] ✅ 프리로드된 컨트롤러 - 즉시 재생 준비 완료: ${widget.url}',
            );
          } else {
            debugPrint('[ClipComponent] ✅ 새 컨트롤러 - 재생 준비 완료: ${widget.url}');
          }

          // 🎯 뷰포트에 있으면 바로 재생
          if (widget.shouldAutoPlay) {
            _playVideo();
          }
        } catch (e) {
          debugPrint('[ClipComponent] 재생 준비 설정 오류: $e');
          // dispose된 컨트롤러 처리
          _controller = null;
          _isInitialized = false;
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[ClipComponent] 초기화 오류: ${widget.url} - $e');
      debugPrint('[ClipComponent] 스택 트레이스: $stackTrace');
      if (!mounted) return;

      // 오류 발생 시 컨트롤러 정리
      if (_controller != null) {
        try {
          _controller!.dispose();
        } catch (_) {}
        _controller = null;
      }

      setState(() {
        _hasError = true;
        _isInitialized = false;
        _isReadyToPlay = false;
      });
    }
  }

  /// 🎯 비디오 URL로 썸네일 생성하여 전역 캐시에 저장 (드래그 오버레이에서 재사용)
  Future<void> _generateThumbnailForCache(String videoUrl) async {
    // 이미 캐시에 있으면 스킵
    if (videoThumbnailCache.containsKey(videoUrl)) {
      debugPrint('[ClipComponent] 썸네일 이미 캐시에 있음: $videoUrl');
      return;
    }

    try {
      debugPrint('[ClipComponent] 썸네일 생성 시작 (캐시용): $videoUrl');

      final bytes = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        quality: 75, // 빠른 생성을 위해 품질 낮춤
        timeMs: 500, // 0.5초 지점
      );

      if (bytes != null) {
        videoThumbnailCache[videoUrl] = bytes;
        debugPrint(
          '[ClipComponent] 썸네일 생성 완료 및 캐시 저장: $videoUrl (${bytes.length} bytes)',
        );
      } else {
        debugPrint('[ClipComponent] 썸네일 생성 실패: bytes가 null');
      }
    } catch (e) {
      debugPrint('[ClipComponent] 썸네일 생성 실패: $e');
    }
  }

  void _onVideoStatusChanged() {
    // 🎯 dispose되었거나 mounted가 아니면 즉시 반환
    if (_isDisposed || _controller == null || !mounted) {
      // dispose된 경우 리스너 제거 시도
      if (_isDisposed && _controller != null) {
        try {
          _controller!.removeListener(_onVideoStatusChanged);
        } catch (_) {}
      }
      return;
    }

    try {
      final position = _controller!.value.position;
      final duration = _controller!.value.duration;
      final isAtEnd = duration > Duration.zero && position >= duration;

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
        // 🎯 setState 전에 다시 한 번 확인
        if (!_isDisposed && mounted) {
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
      }

      // 🎯 비디오가 끝났을 때 자동으로 처음부터 돌아가지 않고 일시정지
      if (isAtEnd && isPlaying) {
        // 비디오가 끝났는데 재생 중이면 일시정지하고 다시보기 버튼 표시
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed && mounted && _controller != null) {
            try {
              _controller!.pause();
              if (!_isDisposed && mounted) {
                setState(() {
                  _isPlaying = false;
                  _hasPlayedOnce = true;
                  _isPausedByUser = false;
                });
              }
            } catch (e) {
              debugPrint('[ClipComponent] _onVideoStatusChanged 콜백 오류: $e');
            }
          }
        });
        return;
      }

      // 🎯 비디오가 끝났거나 사용자가 일시정지한 경우 다시보기 버튼 표시
      if (duration > Duration.zero) {
        final shouldShowReplay =
            (isAtEnd && !isPlaying) ||
            (_isPausedByUser && !isPlaying && _hasPlayedOnce);

        if (_hasPlayedOnce != shouldShowReplay && !_isDisposed && mounted) {
          setState(() {
            _hasPlayedOnce = shouldShowReplay;
          });
        }
      }
    } catch (e) {
      // dispose된 컨트롤러 접근 시 오류 발생 가능
      debugPrint('[ClipComponent] _onVideoStatusChanged 오류: $e');
      if (_isDisposed && _controller != null) {
        try {
          _controller!.removeListener(_onVideoStatusChanged);
        } catch (_) {}
      }
    }
  }

  void _onMuteServiceChanged() {
    // 🎯 dispose되었거나 mounted가 아니면 리스너 제거
    if (_isDisposed || !mounted) {
      _muteService.removeListener(_onMuteServiceChanged);
      return;
    }

    // 리더 음소거 상태가 변경되면 비디오 볼륨 조정
    if (_controller != null && _isInitialized) {
      try {
        // 🎯 dispose 확인
        if (_isDisposed) {
          _muteService.removeListener(_onMuteServiceChanged);
          return;
        }
        _controller!.setVolume(_muteService.isReaderMuted ? 0.0 : 1.0);
        // 🎯 setState 전에 다시 한 번 확인
        if (!_isDisposed && mounted) {
          setState(() {});
        }
      } catch (e) {
        debugPrint('[ClipComponent] _onMuteServiceChanged 오류: $e');
        // dispose된 컨트롤러 접근 시 리스너 제거
        _muteService.removeListener(_onMuteServiceChanged);
      }
    }
  }

  // 외부에서 호출하기 위한 public 메서드들
  void toggleMute() {
    if (_controller == null) return;
    // 리더 음소거 상태 토글
    _muteService.toggleReaderMute();
  }

  void restartVideo() {
    if (_controller == null || !_isInitialized || !_isReadyToPlay) return;

    // 🎯 다시보기: VideoPlayer는 계속 표시하고, seekTo 후 재생
    setState(() {
      _hasPlayedOnce = false;
      _isPausedByUser = false;
    });

    _controller!.seekTo(Duration.zero).then((_) {
      if (mounted && _controller != null && _isInitialized) {
        _controller!.play();
      }
    });
  }

  void _playVideo() {
    if (_controller == null || !_isInitialized) {
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

  /// 🎯 metadata에서 비율 정보를 한 번만 가져오기 (캐싱)
  void _loadMetadataAspectRatio() {
    if (_metadataAspectRatio != null) return; // 이미 로드됨

    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      // ignore: invalid_use_of_visible_for_testing_member
      final doc = seState?.editContext.editor.document;
      final node = doc?.getNodeById(widget.nodeId);
      if (node is ClipNode) {
        final aspectRatioValue = node.metadata['aspectRatio'];
        if (aspectRatioValue != null) {
          _metadataAspectRatio =
              (aspectRatioValue is num)
                  ? aspectRatioValue.toDouble()
                  : double.tryParse(aspectRatioValue.toString());
          debugPrint(
            '[ClipComponent] metadata에서 비율 가져옴: $_metadataAspectRatio',
          );
        }
      }
    } catch (e) {
      debugPrint('[ClipComponent] metadata 비율 가져오기 실패: $e');
    }
  }

  /// 🎯 측정된 aspectRatio를 메타데이터에 저장 (편집 모드 전용)
  void _saveAspectRatioToMetadata(double aspectRatio) {
    if (!widget.isEditing) return;

    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final seState = context.findAncestorStateOfType<SuperEditorState>();
      // ignore: invalid_use_of_visible_for_testing_member
      final doc = seState?.editContext.editor.document;
      final node = doc?.getNodeById(widget.nodeId);

      if (node is! ClipNode) return;

      // 메타데이터에 aspectRatio 추가
      final meta = Map<String, dynamic>.from(node.metadata);
      meta['aspectRatio'] = aspectRatio;

      // 🎯 성능 최적화: 로컬 경로와 네트워크 URL 모두 키로 저장 (이미지와 동일한 패턴)
      // aspectRatio는 단일 값이므로 별도 키 저장은 불필요하지만,
      // uploadedUrls에 네트워크 URL도 키로 저장하여 일관성 유지
      final uploadedUrls = Map<String, String>.from(
        (meta['uploadedUrls'] as Map<String, dynamic>?)
                ?.cast<String, String>() ??
            {},
      );
      if (node.url.isNotEmpty && !uploadedUrls.containsKey(node.url)) {
        // 네트워크 URL이 있으면 자기 자신을 가리키도록 저장 (일관성 유지)
        uploadedUrls[node.url] = node.url;
        meta['uploadedUrls'] = uploadedUrls;
      }

      // 노드 업데이트 (EditorService를 통해)
      try {
        // 🎯 dragService를 통해 editorService 접근 (Provider context 문제 방지)
        EditorService? editorService;
        if (widget.dragService != null) {
          editorService =
              (widget.dragService as dynamic).editorService as EditorService?;
        }

        // 🎯 dragService가 없으면 Provider로 접근 시도 (fallback)
        if (editorService == null) {
          try {
            editorService = Provider.of<EditorService>(context, listen: false);
          } catch (e) {
            debugPrint('[ClipComponent] Provider로 EditorService 접근 실패: $e');
          }
        }

        if (editorService == null) {
          debugPrint('[ClipComponent] EditorService를 찾을 수 없음');
          return;
        }

        final updatedNode = ClipNode(
          id: node.id,
          label: node.label,
          colorHex: node.colorHex,
          url: node.url,
          localPath: node.localPath,
          thumbnailPath: node.thumbnailPath,
          metadata: meta,
        );
        editorService.document.replaceNodeById(widget.nodeId, updatedNode);
        _metadataAspectRatio = aspectRatio; // 캐싱
        debugPrint('[ClipComponent] 💾 메타데이터에 aspectRatio 저장: $aspectRatio');
      } catch (e) {
        debugPrint('[ClipComponent] EditorService 접근 실패: $e');
      }
    } catch (e) {
      debugPrint('[ClipComponent] 메타데이터 저장 실패: $e');
    }
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

    // 🎯 싱글 이미지와 동일: 부모 constraints를 따름 (스타일시트 패딩 자동 반영)

    // 🎯 초기화 전: 썸네일 또는 쉬머 표시
    if (!_isInitialized || _controller == null) {
      // 🎯 편집 모드에서만 metadata 조회 (성능 최적화)
      double? metadataAspectRatio;
      if (widget.isEditing) {
        try {
          // ignore: invalid_use_of_visible_for_testing_member
          final seState = context.findAncestorStateOfType<SuperEditorState>();
          // ignore: invalid_use_of_visible_for_testing_member
          final doc = seState?.editContext.editor.document;
          final node = doc?.getNodeById(widget.nodeId);
          if (node is ClipNode) {
            final aspectRatioValue = node.metadata['aspectRatio'];
            if (aspectRatioValue != null) {
              metadataAspectRatio =
                  (aspectRatioValue is num)
                      ? aspectRatioValue.toDouble()
                      : double.tryParse(aspectRatioValue.toString());
            }
          }
        } catch (e) {
          // 무시
        }
      }

      final aspectRatio = metadataAspectRatio ?? (16 / 9);

      // 🎯 싱글 이미지와 동일: AspectRatio만 사용 (부모 constraints를 따름)
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRRect(
          child: _buildThumbnailOrShimmer(
            thumbnailPath: widget.thumbnailPath,
            width: 0.0, // 부모 constraints 따름
            height: 0.0,
          ),
        ),
      );
    }

    // 원본 비율 계산
    final videoSize = _controller!.value.size;
    final originalAspectRatio =
        videoSize.height > 0 ? videoSize.width / videoSize.height : 16 / 9;

    // 🎯 싱글 이미지와 동일: AspectRatio만 사용 (부모 constraints를 따름)
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: originalAspectRatio,
          child: ClipRRect(child: VideoPlayer(_controller!)),
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
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
        // 🎯 업로드 중 오버레이 (로딩 스피너)
        if (widget.isUploading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          ),
        // 음소거 버튼 (업로드 중이 아닐 때만 표시)
        if (!widget.isUploading)
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
    );
  }
}
