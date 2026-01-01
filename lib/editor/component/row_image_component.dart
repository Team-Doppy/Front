import 'package:doppy/common/widgets/image_error_placeholder.dart';
import 'package:doppy/utils/image_size_utils.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/editor_service.dart';
import 'package:doppy/editor/utils/config.dart';
import 'package:doppy/editor/utils/node_type_checker.dart';
import 'package:doppy/editor/utils/drop_line_config.dart';
import 'package:doppy/editor/utils/animated_drop_line.dart';
import 'package:doppy/image/utils/editor_image_provider.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:super_editor/super_editor.dart';
import 'dart:math' as math;

/// 여러 이미지를 가로로 배치하는 커스텀 노드 (최대 3개)
class ImageRowNode extends BlockNode {
  ImageRowNode({
    required this.id,
    required List<String> imageUrls,
    this.spacing = 0.0,
    Map<String, dynamic>? metadata,
  }) : imageUrls = imageUrls.take(3).toList(), // 최대 3개로 제한
       _metadata = metadata ?? <String, dynamic>{};

  @override
  bool get isDeletable => true;

  @override
  final String id;
  final List<String> imageUrls;
  final double spacing;
  final Map<String, dynamic> _metadata;

  @override
  Map<String, dynamic> get metadata => _metadata;

  String get nodeType => 'imageRow';

  bool get hasContent => imageUrls.isNotEmpty;

  ImageRowNode copyWith({
    String? id,
    List<String>? imageUrls,
    double? spacing,
    Map<String, dynamic>? metadata,
  }) {
    return ImageRowNode(
      id: id ?? this.id,
      imageUrls: imageUrls?.take(3).toList() ?? this.imageUrls,
      spacing: spacing ?? this.spacing,
      metadata: metadata ?? _metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeType': nodeType,
      'imageUrls': imageUrls,
      'spacing': spacing,
      if (_metadata.isNotEmpty) 'metadata': _metadata,
    };
  }

  static ImageRowNode fromJson(Map<String, dynamic> json) {
    return ImageRowNode(
      id: json['id'] as String,
      imageUrls: List<String>.from(json['imageUrls'] as List),
      spacing: (json['spacing'] as num?)?.toDouble() ?? 0.0,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  bool containsPosition(Object position) {
    // 블록 노드는 Upstream/Downstream 포지션만 가진다고 가정
    return position is UpstreamDownstreamNodePosition;
  }

  Rect getRectForPosition(NodePosition nodePosition) {
    // 기본 구현 - 실제로는 컴포넌트에서 계산됨
    return const Rect.fromLTWH(0, 0, 0, 0);
  }

  NodeSelection getSelectionOfEverything() {
    return UpstreamDownstreamNodeSelection(
      base: const UpstreamDownstreamNodePosition.upstream(),
      extent: const UpstreamDownstreamNodePosition.downstream(),
    );
  }

  bool isVisualSelectionSupported() {
    // 이미지 행은 드래그 선택 불필요
    return false;
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return ImageRowNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
      spacing: spacing,
      metadata: newMetadata,
    );
  }

  @override
  String? copyContent(NodeSelection selection) {
    // 이미지 행은 텍스트 복사 없음
    return null;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    final updatedMetadata = Map<String, dynamic>.from(_metadata);
    updatedMetadata.addAll(newProperties);
    return ImageRowNode(
      id: id,
      imageUrls: List<String>.from(imageUrls),
      spacing: spacing,
      metadata: updatedMetadata,
    );
  }

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
  ) => UpstreamDownstreamNodePosition.downstream();

  @override
  UpstreamDownstreamNodePosition selectUpstreamPosition(
    NodePosition base,
    NodePosition extent,
  ) => UpstreamDownstreamNodePosition.upstream();
}

class RowImageComponentBuilder implements ComponentBuilder {
  const RowImageComponentBuilder({
    required this.screenWidth,
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
  });

  final double screenWidth; // 🚀 최고 효율: 외부에서 전달받음
  final dynamic dragService; // DragService 타입을 나중에 import해서 수정
  final bool isEditing;
  final bool isDarkMode;

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is ImageRowComponentViewModel) {
      // ✅ 중요: nodeId 기반 GlobalObjectKey로 컴포넌트 Key를 안정화해서
      // 문서 구조 변경(삽입/삭제/이동/드래그)에도 이미지 State가 불필요하게 리셋되지 않게 한다.
      // ✅ 중요: SuperEditor의 componentKey 추적을 깨면 드래그&드롭/삽입이 망가질 수 있으므로 유지한다.
      return ImageRowComponent(
        nodeId: componentViewModel.nodeId,
        imageUrls: componentViewModel.imageUrls,
        spacing: componentViewModel.spacing,
        screenWidth: screenWidth, // 🚀 최고 효율: 전달
        unifiedHeight: null, // 🎯 metadata 의존 제거
        isDarkMode: isDarkMode,
        componentKey: componentContext.componentKey,
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
    if (node is ImageRowNode) {
      // 🎯 metadata 의존 제거 - 항상 null
      return ImageRowComponentViewModel(
        nodeId: node.id,
        imageUrls: node.imageUrls,
        spacing: node.spacing,
        unifiedHeight: null, // 항상 새로 측정
      );
    }
    return null;
  }
}

/// 실제로 문서에 올라가는 컴포넌트. 반드시 DocumentComponent를 구현해야 함.
class ImageRowComponent extends StatefulWidget {
  const ImageRowComponent({
    required this.nodeId,
    required this.imageUrls,
    required this.spacing,
    required this.screenWidth, // 🎯 외부에서 전달받음
    required GlobalKey componentKey,
    this.unifiedHeight, // 🎯 사용하지 않음 (항상 null)
    this.dragService,
    this.isEditing = true,
    this.isDarkMode = false,
    Key? key,
  }) : _componentKey = componentKey,
       super(key: componentKey);

  final String nodeId;
  final List<String> imageUrls;
  final double spacing;
  final double screenWidth; // 🚀 한 번만 계산된 화면 너비
  final double? unifiedHeight; // 🎯 metadata 의존 제거 (deprecated)
  final dynamic dragService;
  final bool isEditing;
  final bool isDarkMode;

  final GlobalKey _componentKey;

  GlobalKey get componentKey => _componentKey;

  @override
  State<ImageRowComponent> createState() => _ImageRowComponentState();
}

class _ImageRowComponentState extends State<ImageRowComponent>
    with DocumentComponent, TickerProviderStateMixin {
  // 요청: [ImgLife][Row] 로그는 잠시 숨김
  static const bool _kImgLifeRowLogs = false;

  // ✅ 같은 URL 이미지가 리빌드/재해결 과정에서 잠깐 frame=null이 되어도
  // 마지막으로 성공적으로 렌더된 child를 유지해서 "사라졌다가 다시 뜨는" 깜빡임을 줄인다.
  final Map<String, Widget> _lastRenderedByUrl = <String, Widget>{};
  double? _unifiedHeight;
  final Map<String, Size> _imageSizes = {};
  late final AnimationController _controller;

  // Scatter 애니메이션용
  late final AnimationController _scatterCtrl;
  bool _scatterActive = false;
  bool _wasSpoilerVisible = false;

  // 🎯 성능 최적화: EditorService 캐싱 (에디터 모드에서만)
  EditorService? _cachedEditorService;
  bool _editorServiceInitialized = false;

  // 🎯 성능 최적화: 이미지 측정 중복 방지
  final Set<String> _measuringUrls = {}; // 측정 중인 URL 추적

  // ✅ CachedNetworkImage 로딩 중에도 이전 이미지를 유지(깜빡임 방지)
  final Map<String, ImageProvider> _lastNetworkProviders = {};

  // 로컬 경로 -> 업로드 URL 변환 과정에서도 "같은 이미지"로 취급할 수 있도록
  // 업로드 매핑(uploadedUrls: {localPath: networkUrl})을 역으로 조회해서 canonical seed를 만든다.
  // - localPath인 경우: 그대로 localPath
  // - networkUrl인 경우: 매칭되는 localPath가 있으면 localPath를 반환
  // - 없으면: imageUrl 그대로
  String _canonicalSeedForImageUrl(String imageUrl) {
    try {
      final editorService = _getEditorService();
      if (editorService == null) return imageUrl;
      final node = editorService.document.getNodeById(widget.nodeId);
      if (node is! ImageRowNode) return imageUrl;
      final meta = node.metadata;
      final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
      if (uploadedUrls == null || uploadedUrls.isEmpty) return imageUrl;

      // localPath인 경우
      if (uploadedUrls.containsKey(imageUrl)) return imageUrl;

      // networkUrl인 경우: value==imageUrl인 localPath 찾기
      for (final entry in uploadedUrls.entries) {
        final v = entry.value?.toString() ?? '';
        if (v == imageUrl) {
          final k = entry.key.toString();
          if (k.isNotEmpty) return k;
        }
      }
    } catch (_) {}
    return imageUrl;
  }

  // ✅ Row에서 이미지가 분리/병합되면 index가 변하면서 key가 바뀌어 "재로드"가 발생할 수 있음.
  // 가능한 한 URL 기반으로 key를 안정화해서 기존 Element/State를 재사용하게 한다.
  Key _rowImageKey(int index, String imageUrl) {
    // 로컬→네트워크 URL 치환에도 동일 키가 유지되도록 canonical seed를 사용한다.
    final seed = _canonicalSeedForImageUrl(imageUrl);
    // 동일 seed가 한 row에 중복될 수 있으므로, 중복일 땐 index를 섞어서 충돌만 피한다.
    final dupCount =
        widget.imageUrls
            .where((u) => _canonicalSeedForImageUrl(u) == seed)
            .length;
    if (dupCount <= 1) {
      return ValueKey('row_${widget.nodeId}_$seed');
    }
    return ValueKey('row_${widget.nodeId}_$seed#$index');
  }

  // DocumentComponent 필수 메서드들
  @override
  NodePosition getBeginningPosition() =>
      UpstreamDownstreamNodePosition.upstream();

  @override
  NodePosition getEndPosition() => UpstreamDownstreamNodePosition.downstream();

  @override
  NodePosition? getPositionAtOffset(Offset localOffset) =>
      UpstreamDownstreamNodePosition.upstream();

  @override
  Offset getOffsetForPosition(NodePosition nodePosition) => Offset.zero;

  @override
  Rect getRectForPosition(NodePosition nodePosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return Rect.zero;
    }
    return Offset.zero & renderBox.size;
  }

  @override
  Rect getRectForSelection(
    NodePosition baseNodePosition,
    NodePosition extentNodePosition,
  ) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return Rect.zero;
    }
    return Offset.zero & renderBox.size;
  }

  @override
  NodeSelection getCollapsedSelectionAt(NodePosition nodePosition) =>
      UpstreamDownstreamNodeSelection(
        base: UpstreamDownstreamNodePosition.upstream(),
        extent: UpstreamDownstreamNodePosition.upstream(),
      );

  @override
  NodeSelection getSelectionBetween({
    required NodePosition basePosition,
    required NodePosition extentPosition,
  }) => UpstreamDownstreamNodeSelection(
    base: UpstreamDownstreamNodePosition.upstream(),
    extent: UpstreamDownstreamNodePosition.downstream(),
  );

  @override
  NodeSelection? getSelectionInRange(
    Offset localBaseOffset,
    Offset localExtentOffset,
  ) => null;

  @override
  NodeSelection getSelectionOfEverything() => UpstreamDownstreamNodeSelection(
    base: UpstreamDownstreamNodePosition.upstream(),
    extent: UpstreamDownstreamNodePosition.downstream(),
  );

  @override
  Rect getEdgeForPosition(NodePosition nodePosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return Rect.zero;
    }

    // upstream/downstream 위치일 때는 커서를 표시하지 않음 (사용자 요청)
    // selection 효과만 표시
    if (nodePosition is UpstreamDownstreamNodePosition) {
      return Offset.zero & renderBox.size;
    }

    return Offset.zero & renderBox.size;
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
      UpstreamDownstreamNodePosition.downstream();

  @override
  MouseCursor? getDesiredCursorAtOffset(Offset localOffset) => null;

  static const double marginTop = 2;
  static const double marginBottom = 2;

  // 🎯 특수 노드 사이/마지막 노드 아래 빈 문단 추가 처리
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
        if (NodeTypeChecker.isSpecialNode(prevNode)) {
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
        if (NodeTypeChecker.isSpecialNode(nextNode)) {
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

  @override
  void initState() {
    super.initState();
    assert(() {
      if (_kImgLifeRowLogs) {
        debugPrint(
          '[ImgLife][Row] init: nodeId=${widget.nodeId}, keyHash=${identityHashCode(widget.key)}, componentKeyHash=${identityHashCode(widget._componentKey)}, urls=${widget.imageUrls.length}',
        );
      }
      return true;
    }());

    // ✅ 첫 프레임 전에 메타데이터에서 크기를 즉시 로드해, 쉬머/점프를 최소화한다.
    _loadImageSizesFromMetadata();
    _applyUnifiedHeight(widget.screenWidth, setStateIfChanged: false);

    // 메타데이터에 없는 것만 다음 프레임부터 측정 시작 (IO/디코드로 첫 프레임을 막지 않음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final screenWidth = widget.screenWidth;
      for (final imageUrl in widget.imageUrls) {
        if (!_imageSizes.containsKey(imageUrl) &&
            !_measuringUrls.contains(imageUrl)) {
          _measureImageRealtime(imageUrl, screenWidth);
        }
      }
    });

    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 900));

    // Scatter 애니메이션 초기화
    _scatterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _scatterActive = false);
      }
    });
  }

  @override
  void didUpdateWidget(ImageRowComponent oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 🎯 이미지 URL이 변경되면 무조건 재측정 (병합 포함)
    final urlsChanged = !_areUrlsEqual(oldWidget.imageUrls, widget.imageUrls);
    assert(() {
      if (_kImgLifeRowLogs) {
        debugPrint(
          '[ImgLife][Row] didUpdateWidget: nodeId=${widget.nodeId}, urlsChanged=$urlsChanged, oldCount=${oldWidget.imageUrls.length}, newCount=${widget.imageUrls.length}',
        );
        if (urlsChanged) {
          debugPrint(
            '[ImgLife][Row] urls(old)=${oldWidget.imageUrls}\n[ImgLife][Row] urls(new)=${widget.imageUrls}',
          );
        }
      }
      return true;
    }());

    if (urlsChanged) {
      _lastRenderedByUrl.clear();
      _measuringUrls.clear();

      // ✅ 먼저 메타데이터로 가능한 만큼 즉시 복원해서 UI 변화 최소화
      _imageSizes.clear();
      _unifiedHeight = null;
      _loadImageSizesFromMetadata();
      _applyUnifiedHeight(widget.screenWidth, setStateIfChanged: false);

      setState(() {});

      // 메타데이터에 없는 이미지만 다음 프레임부터 측정
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final screenWidth = widget.screenWidth;
        for (final imageUrl in widget.imageUrls) {
          if (!_imageSizes.containsKey(imageUrl) &&
              !_measuringUrls.contains(imageUrl)) {
            _measureImageRealtime(imageUrl, screenWidth);
          }
        }
      });
    } else {
      // 🎯 URL이 같아도 메타데이터가 업데이트되었을 수 있음 (병합 후)
      // 메타데이터를 다시 확인하여 누락된 크기 정보가 있으면 로드
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // 현재 메타데이터에서 누락된 이미지 크기 정보 확인
        final dimensions = _getImageDimensionsFromMetadata();
        if (dimensions != null && dimensions.isNotEmpty) {
          bool hasNewSizes = false;
          for (final imageUrl in widget.imageUrls) {
            if (!_imageSizes.containsKey(imageUrl)) {
              final size = _parseSizeFromDimensions(dimensions, imageUrl);
              if (size != null) {
                _imageSizes[imageUrl] = size;
                hasNewSizes = true;
              }
            }
          }

          // 새로운 크기 정보가 로드되었으면 높이 재계산
          if (hasNewSizes && _imageSizes.length == widget.imageUrls.length) {
            _applyUnifiedHeight(widget.screenWidth, setStateIfChanged: true);
          }
        }
      });
    }
  }

  bool _areUrlsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    assert(() {
      if (_kImgLifeRowLogs) {
        debugPrint(
          '[ImgLife][Row] dispose: nodeId=${widget.nodeId}, keyHash=${identityHashCode(widget.key)}, componentKeyHash=${identityHashCode(widget._componentKey)}',
        );
      }
      return true;
    }());
    _controller.dispose();
    _scatterCtrl.dispose();

    // 🎯 성능 최적화: 측정 중인 URL 정리
    _measuringUrls.clear();

    super.dispose();
  }

  // 🎯 이미지 사이 경계 탭 감지를 위한 상태 관리
  bool _imageRowBoundaryTapped = false;
  // 🎯 특수 노드 사이 클릭 감지 플래그
  bool _isSpecialNodeGapTap = false;

  // 🎯 이미지행 내부 경계(이미지 사이) 클릭 감지
  int? _detectImageRowBoundaryGap(ImageRowNode rowNode, Offset globalPos) {
    if (widget.dragService == null) return null;
    const double threshold = 6.0;
    final rect = widget.dragService!.getNodeGlobalRect(rowNode.id);
    if (rect == null) return null;

    // 수직으로 행 안쪽에 위치해야 함 (약간 오차 허용)
    if (globalPos.dy < rect.top - 8 || globalPos.dy > rect.bottom + 8) {
      return null;
    }

    final localX = globalPos.dx - rect.left;
    final int count = rowNode.imageUrls.length;
    if (count <= 1) return null;
    final double slot = rect.width / count;

    // 경계는 k*slot (k=1..count-1). 경계에 가까우면 감지
    for (int k = 1; k < count; k++) {
      final double boundaryX = slot * k;
      if ((localX - boundaryX).abs() <= threshold) {
        return k; // k번째 경계 = 앞 이미지 인덱스와 뒤 이미지 인덱스 사이
      }
    }
    return null;
  }

  // 🎯 클릭한 위치에서 가장 근접한 이미지 인덱스 찾기
  int? _findClickedImageIndex(ImageRowNode rowNode, Offset globalPosition) {
    if (widget.dragService == null) return null;
    try {
      final imageCount = rowNode.imageUrls.length;
      final rect = widget.dragService!.getNodeGlobalRect(rowNode.id);
      if (rect == null) return null;
      final imageWidth = rect.width / imageCount;

      // 클릭한 X 좌표에 따라 이미지 인덱스 계산
      final localX = globalPosition.dx - rect.left;
      final clickedIndex = (localX / imageWidth).floor();

      // 유효한 인덱스 범위 확인
      if (clickedIndex >= 0 && clickedIndex < imageCount) {
        return clickedIndex;
      }

      return 0;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 성능 최적화: Selector로 필요한 부분만 watch
    final isSelected = context.select<NodeComponentService, bool>(
      (service) => service.selectedImageId == widget.nodeId,
    );

    // 🎯 편집 모드에서만 selection 체크 (성능 최적화)
    // 🎯 읽기 모드에서도 doc에 접근하여 특수 노드 간격 확인 (포스트 라이트와 동일하게)
    DocumentSelection? composerSelection;
    Document? doc;
    // ignore: invalid_use_of_visible_for_testing_member
    final seState = context.findAncestorStateOfType<SuperEditorState>();
    // ignore: invalid_use_of_visible_for_testing_member
    doc = seState?.editContext.editor.document;
    if (widget.isEditing) {
      // ignore: invalid_use_of_visible_for_testing_member
      composerSelection = seState?.editContext.composer.selection;
    }

    // 🎯 downstream 위치에 커서가 있을 때도 selection 효과 표시
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

    // 위/아래가 이미지인지 판정하여 SingleImage와 동일한 여백 정책 적용
    final bool hasImageAbove = _hasNeighborImage(doc, widget.nodeId, -1);
    final bool hasImageBelow = _hasNeighborImage(doc, widget.nodeId, 1);

    // 🎯 RepaintBoundary로 감싸서 키보드 애니메이션 시 불필요한 repaint 방지
    return RepaintBoundary(
      child: Column(
        children: [
          if (!hasImageAbove)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
          Stack(
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

                          // 이미지 사이 경계 감지
                          setState(() {
                            _imageRowBoundaryTapped = false;
                            _isSpecialNodeGapTap = isGapTap;
                          });
                          final node = doc?.getNodeById(widget.nodeId);
                          if (node is ImageRowNode) {
                            final betweenIndex = _detectImageRowBoundaryGap(
                              node,
                              details.globalPosition,
                            );
                            if (betweenIndex != null) {
                              // 경계 감지: 빈 문단 삽입
                              setState(() {
                                _imageRowBoundaryTapped = true;
                              });
                              final rowIndex = doc?.getNodeIndexById(
                                widget.nodeId,
                              );
                              if (rowIndex != null && rowIndex != -1) {
                                // EditorService를 통해 빈 문단 삽입
                                final editorService =
                                    widget.dragService?.editorService;
                                if (editorService != null) {
                                  editorService.insertEmptyParagraphAtIndex(
                                    rowIndex + 1,
                                  );
                                  context
                                      .read<NodeComponentService>()
                                      .selectNode(null);
                                  widget.dragService?.invalidateNodeRectCache();
                                }
                              }
                            }
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

                          // 이미지 사이 경계가 탭되었으면 노드 선택 처리 안 함
                          if (_imageRowBoundaryTapped) {
                            setState(() {
                              _imageRowBoundaryTapped = false;
                            });
                            return;
                          }
                          // 일반 영역: 노드 선택
                          final imageService =
                              context.read<NodeComponentService>();
                          final currentSelected = imageService.selectedImageId;
                          if (currentSelected == widget.nodeId) {
                            // 같은 노드 재탭: 선택 해제
                            imageService.selectNode(null);
                            widget.dragService?.invalidateNodeRectCache();
                          } else {
                            // 다른 노드 선택
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
                          // 🎯 키보드 내리기 + 포커스 해제 (드래그 시작 시)
                          FocusManager.instance.primaryFocus?.unfocus();
                          FocusScope.of(context).unfocus();
                          // 이미지 인덱스 찾기
                          final node = doc?.getNodeById(widget.nodeId);
                          if (node is ImageRowNode) {
                            final imageIndex = _findClickedImageIndex(
                              node,
                              details.globalPosition,
                            );
                            final imageService =
                                context.read<NodeComponentService>();
                            final isRowSelected =
                                imageService.selectedImageId == widget.nodeId;
                            if (isRowSelected) {
                              // 선택되어 있으면 바로 드래그
                              widget.dragService?.startDrag(
                                widget.nodeId,
                                context,
                                details.globalPosition,
                              );
                            } else {
                              // 선택 안 되어 있으면 분리 정보 설정 후 드래그
                              if (imageIndex != null) {
                                widget.dragService?.startDrag(
                                  widget.nodeId,
                                  context,
                                  details.globalPosition,
                                );
                                widget.dragService?.setSplitImageInfo(
                                  widget.nodeId,
                                  imageIndex,
                                );
                              }
                            }
                          }
                        }
                        : null,
                onLongPressMoveUpdate:
                    widget.isEditing && widget.dragService != null
                        ? (details) {
                          // 드래그 업데이트 (auto-scroll은 DragService 내부에서 처리)
                          widget.dragService?.updateDrag(
                            details.globalPosition,
                            context,
                          );
                        }
                        : null,
                onLongPressEnd:
                    widget.isEditing && widget.dragService != null
                        ? (_) {
                          widget.dragService?.endDrag();
                        }
                        : null,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: marginTop,
                    bottom: marginBottom,
                  ),
                  child: ClipRect(
                    child: Stack(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // 행 전체 스포일러 여부 계산 (per-image 블러를 위해 선계산)
                            bool isRowSpoiler = false;
                            try {
                              final node = doc?.getNodeById(widget.nodeId);
                              Map<String, dynamic>? meta;
                              if (node is ImageRowNode) {
                                meta = node.metadata;
                              }
                              // 🎯 context.select로 변경하여 스포일러 변경사항 즉시 감지
                              isRowSpoiler = context
                                  .select<NodeComponentService, bool>(
                                    (service) => service.shouldShowImageSpoiler(
                                      widget.nodeId,
                                      meta,
                                    ),
                                  );
                            } catch (_) {}

                            // 🎯 업로드 중 상태 확인 (편집 모드에서만, 읽기 전용 모드에서는 항상 false)
                            // 🎯 성능 최적화: context.watch → context.select로 변경
                            bool isUploading = false;
                            if (widget.isEditing) {
                              try {
                                isUploading = context
                                    .select<UploadService, bool>(
                                      (service) => service
                                          .hasActiveUploadForRef(widget.nodeId),
                                    );
                              } catch (e) {
                                debugPrint(
                                  '[RowImage] UploadService 확인 실패: $e',
                                );
                              }
                            }

                            // 🎯 노드 레벨 댓글 정보 확인 (이미지 로우 전체)
                            bool hasComments = false;
                            try {
                              final node = doc?.getNodeById(widget.nodeId);
                              if (node is ImageRowNode) {
                                final meta = node.metadata;
                                // 노드 레벨 hasComments 확인
                                hasComments = meta['hasComments'] == true;

                                // 노드 레벨 정보가 없으면 각 이미지별 정보 확인
                                if (!hasComments) {
                                  final commentInfo =
                                      meta['imageCommentInfo']
                                          as Map<String, dynamic>?;
                                  if (commentInfo != null) {
                                    // 하나라도 댓글이 있으면 표시
                                    hasComments = commentInfo.values.any((
                                      imgInfo,
                                    ) {
                                      if (imgInfo is Map) {
                                        return imgInfo['hasComments'] == true;
                                      }
                                      return false;
                                    });
                                  }
                                }
                              }
                            } catch (_) {}

                            return Stack(
                              children: [
                                Row(
                                  children: [
                                    // 이미지들
                                    ...widget.imageUrls.asMap().entries.map((
                                      entry,
                                    ) {
                                      final imageUrl = entry.value;

                                      return Expanded(
                                        child: RepaintBoundary(
                                          child: Container(
                                            margin:
                                                imageUrl ==
                                                        widget.imageUrls.last
                                                    ? EdgeInsets.zero
                                                    : const EdgeInsets.only(
                                                      right: 2,
                                                    ),
                                            child: Stack(
                                              children: [
                                                // _unifiedHeight가 있으면 LayoutBuilder 없이 직접 사용 (성능 최적화)
                                                _unifiedHeight != null
                                                    ? ConstrainedBox(
                                                      constraints:
                                                          BoxConstraints.expand(
                                                            height:
                                                                _unifiedHeight!,
                                                          ),
                                                      child: TweenAnimationBuilder<
                                                        double
                                                      >(
                                                        tween: Tween<double>(
                                                          begin: 0.0,
                                                          end:
                                                              isRowSpoiler
                                                                  ? 12.0
                                                                  : 0.0,
                                                        ),
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 180,
                                                            ),
                                                        curve:
                                                            Curves.easeOutCubic,
                                                        builder: (
                                                          context,
                                                          sigma,
                                                          child,
                                                        ) {
                                                          return ImageFiltered(
                                                            imageFilter: ui
                                                                .ImageFilter.blur(
                                                              sigmaX: sigma,
                                                              sigmaY: sigma,
                                                            ),
                                                            child: child,
                                                          );
                                                        },
                                                        child:
                                                            _buildRowImageWidget(
                                                              entry.key,
                                                              imageUrl,
                                                              constraints
                                                                  .maxWidth,
                                                            ),
                                                      ),
                                                    )
                                                    : LayoutBuilder(
                                                      builder: (
                                                        context,
                                                        imageConstraints,
                                                      ) {
                                                        // 기본 3:4 비율로 높이 계산
                                                        final defaultHeight =
                                                            _calculateDefaultShimmerHeight(
                                                              imageConstraints
                                                                  .maxWidth,
                                                            );
                                                        return ConstrainedBox(
                                                          constraints:
                                                              BoxConstraints.expand(
                                                                height:
                                                                    defaultHeight,
                                                              ),
                                                          child: TweenAnimationBuilder<
                                                            double
                                                          >(
                                                            tween: Tween<
                                                              double
                                                            >(
                                                              begin: 0.0,
                                                              end:
                                                                  isRowSpoiler
                                                                      ? 12.0
                                                                      : 0.0,
                                                            ),
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      180,
                                                                ),
                                                            curve:
                                                                Curves
                                                                    .easeOutCubic,
                                                            builder: (
                                                              context,
                                                              sigma,
                                                              child,
                                                            ) {
                                                              return ImageFiltered(
                                                                imageFilter: ui
                                                                    .ImageFilter.blur(
                                                                  sigmaX: sigma,
                                                                  sigmaY: sigma,
                                                                ),
                                                                child: child,
                                                              );
                                                            },
                                                            child:
                                                                _buildRowImageWidget(
                                                                  entry.key,
                                                                  imageUrl,
                                                                  imageConstraints
                                                                      .maxWidth,
                                                                ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                // ✅ 블러 위 어둡게(0.2) 오버레이
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    child: AnimatedOpacity(
                                                      opacity:
                                                          isRowSpoiler ? 1 : 0,
                                                      duration: const Duration(
                                                        milliseconds: 160,
                                                      ),
                                                      curve:
                                                          Curves.easeOutCubic,
                                                      child: Container(
                                                        color: Colors.black
                                                            .withOpacity(0.15),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                                // 🎯 이미지 로우 전체 상단 끝에 댓글 배지 하나만 표시
                                if (hasComments)
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(1),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withOpacity(0.1),
                                            width: 1,
                                          ),
                                        ),
                                        child: SvgPicture.asset(
                                          'assets/icons/comment.svg',
                                          width: 12,
                                          height: 12,
                                          colorFilter: ColorFilter.mode(
                                            Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // 🎯 업로드 중 로딩 스피너
                                if (isUploading)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Center(
                                        child: const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 4,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        if (isSelectionHighlighted)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: AppColors.primary.withOpacity(0.4),
                              ),
                            ),
                          ),

                        // 스포일러 마스킹 (metadata + 세션 캐시)
                        Builder(
                          builder: (context) {
                            bool isSpoilerFlag = false;
                            try {
                              final node = doc?.getNodeById(widget.nodeId);
                              Map<String, dynamic>? meta;
                              if (node is ImageRowNode) {
                                meta = node.metadata;
                              }
                              // 🎯 context.select로 변경하여 스포일러 변경사항 감지
                              isSpoilerFlag = context
                                  .select<NodeComponentService, bool>(
                                    (service) => service.shouldShowImageSpoiler(
                                      widget.nodeId,
                                      meta,
                                    ),
                                  );
                            } catch (_) {}

                            // 스포일러 해제 시 scatter 애니메이션 트리거
                            if (_wasSpoilerVisible &&
                                !isSpoilerFlag &&
                                _scatterCtrl.status !=
                                    AnimationStatus.forward) {
                              _scatterActive = true;
                              _scatterCtrl
                                ..reset()
                                ..forward();
                            }
                            _wasSpoilerVisible = isSpoilerFlag;

                            if (!isSpoilerFlag && !_scatterActive) {
                              return const SizedBox.shrink();
                            }

                            return Builder(
                              builder: (context) {
                                final brightness = Theme.of(context).brightness;
                                final isLightTheme =
                                    brightness == Brightness.light;

                                return Positioned.fill(
                                  child: IgnorePointer(
                                    child: AnimatedBuilder(
                                      animation:
                                          _scatterActive
                                              ? _scatterCtrl
                                              : _controller,
                                      builder: (context, _) {
                                        if (_scatterActive) {
                                          return CustomPaint(
                                            painter:
                                                _RowImageSpoilerScatterPainter(
                                                  progress: _scatterCtrl.value,
                                                  backgroundColor: Colors.white,
                                                  dotColor: Colors.white,
                                                  isLightTheme: isLightTheme,
                                                ),
                                          );
                                        } else {
                                          return CustomPaint(
                                            painter: _RowImageSpoilerPainter(
                                              phase: _controller.value,
                                              isEditing: widget.isEditing,
                                              backgroundColor:
                                                  Colors.transparent,
                                              dotColor: Colors.white,
                                              isLightTheme: isLightTheme,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),

                        // 선택 보더
                        if (isSelected || isDownstreamSelected)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedSelectionBorder(
                                isVisible: true,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.primary,
                                      width: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 드래그 라인 오버레이
              if (widget.dragService != null)
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: widget.dragService!,
                    builder: (context, _) {
                      return Stack(
                        children: [
                          // 위쪽 가로 라인
                          if (_shouldShowTopDropLine())
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: AnimatedDropLine(
                                child: Container(
                                  height: 5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),

                          // 아래쪽 가로 라인
                          if (_shouldShowBottomDropLine())
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: AnimatedDropLine(
                                child: Container(
                                  height: 5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),

                          // 왼쪽 세로 라인 (가로배치 모드일 때)
                          if (_shouldShowLeftVerticalLine())
                            Positioned(
                              left: 0,
                              top: marginTop,
                              bottom: marginBottom,
                              child: AnimatedDropLine(
                                child: Container(
                                  width: 5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),

                          // 오른쪽 세로 라인 (가로배치 모드일 때)
                          if (_shouldShowRightVerticalLine())
                            Positioned(
                              right: 0,
                              top: marginTop,
                              bottom: marginBottom,
                              child: AnimatedDropLine(
                                child: Container(
                                  width: 5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
          if (!hasImageBelow)
            SizedBox(height: EditorConfig.specialNodePaddingWithText),
        ],
      ),
    );
  }

  /// 메타데이터에서 이미지 크기 미리 로드
  void _loadImageSizesFromMetadata() {
    if (!mounted) return;

    final dimensions = _getImageDimensionsFromMetadata();
    if (dimensions == null || dimensions.isEmpty) return;

    for (final imageUrl in widget.imageUrls) {
      final size = _parseSizeFromDimensions(dimensions, imageUrl);
      if (size != null) {
        _imageSizes[imageUrl] = size;
      }
    }

    // unifiedHeight 계산/적용은 호출부에서 결정 (initState에서는 setState 없이 즉시 적용하기 위함)
  }

  /// 개별 이미지 높이 측정
  void _measureAndUnifyHeight(String imageUrl, double availableWidth) {
    // 🎯 성능 최적화: 이미 측정 완료했거나 측정 중이면 스킵
    if (!mounted ||
        _imageSizes.containsKey(imageUrl) ||
        _measuringUrls.contains(imageUrl)) {
      return;
    }
    // 🎯 읽기/편집 모드 모두: 메타데이터에 크기가 없으면 측정 (읽기 모드에서는 저장 안 함)
    _measureImageRealtime(imageUrl, availableWidth);
  }

  /// 메타데이터에서 imageDimensions 추출
  Map<String, dynamic>? _getImageDimensionsFromMetadata() {
    try {
      Document? doc;

      if (widget.isEditing) {
        // 편집 모드: EditorService에서 document 가져오기
        final editorService = _getEditorService();
        if (editorService != null) {
          doc = editorService.document;
        }
      } else {
        // 보기 모드: SuperEditor에서 직접 document 가져오기
        // ignore: invalid_use_of_visible_for_testing_member
        final seState = context.findAncestorStateOfType<SuperEditorState>();
        // ignore: invalid_use_of_visible_for_testing_member
        doc = seState?.editContext.editor.document;
      }

      if (doc == null) return null;

      final node = doc.getNodeById(widget.nodeId);
      if (node is ImageRowNode) {
        return node.metadata['imageDimensions'] as Map<String, dynamic>?;
      }
    } catch (e) {
      // 메타데이터 접근 실패 시 무시
    }
    return null;
  }

  /// dimensions에서 특정 URL의 Size 파싱
  /// 🎯 성능 최적화: 여러 URL 패턴 시도 (로컬 경로 -> 네트워크 URL 변환 대응)
  Size? _parseSizeFromDimensions(
    Map<String, dynamic> dimensions,
    String imageUrl,
  ) {
    // 🎯 1차: 정확한 키 매칭
    if (dimensions.containsKey(imageUrl)) {
      final sizeData = dimensions[imageUrl] as Map<String, dynamic>?;
      if (sizeData != null &&
          sizeData['width'] != null &&
          sizeData['height'] != null) {
        return Size(
          (sizeData['width'] as num).toDouble(),
          (sizeData['height'] as num).toDouble(),
        );
      }
    }

    // 🎯 2차: 파일명으로 매칭 (URL 변환 대응)
    final fileName = imageUrl.split('/').last;
    for (final entry in dimensions.entries) {
      final key = entry.key.toString();
      if (key.endsWith(fileName) || fileName.endsWith(key.split('/').last)) {
        final sizeData = entry.value as Map<String, dynamic>?;
        if (sizeData != null &&
            sizeData['width'] != null &&
            sizeData['height'] != null) {
          return Size(
            (sizeData['width'] as num).toDouble(),
            (sizeData['height'] as num).toDouble(),
          );
        }
      }
    }

    return null;
  }

  /// 실시간 이미지 측정 (메타데이터가 없을 때)
  /// 🎯 공통 유틸리티 사용: 전체 이미지 다운로드 후 크기 추출
  void _measureImageRealtime(String imageUrl, double availableWidth) async {
    // 🎯 성능 최적화: 중복 측정 방지
    if (_measuringUrls.contains(imageUrl) ||
        _imageSizes.containsKey(imageUrl)) {
      return;
    }

    _measuringUrls.add(imageUrl);

    try {
      // 🎯 HEIC 파일은 measureImageSize를 건너뛰고 바로 ImageProvider로 처리
      // (불필요한 다운로드 및 경고 로그 방지)
      if (ImageSizeUtils.isHeicFile(imageUrl)) {
        debugPrint('[RowImage] 🔄 HEIC 파일: ImageProvider로 직접 처리');
        final providerSize = await ImageSizeUtils.extractSizeFromImageProvider(
          imageUrl,
        );
        if (providerSize != null && mounted) {
          _imageSizes[imageUrl] = providerSize;
          _measuringUrls.remove(imageUrl);

          assert(() {
            debugPrint(
              '[RowImage] ✅ ImageProvider에서 크기 추출: $imageUrl -> ${providerSize.width.toInt()}x${providerSize.height.toInt()}',
            );
            return true;
          }());

          if (widget.isEditing) {
            _saveImageSizeToMetadata(imageUrl, providerSize);
          }

          if (_imageSizes.length == widget.imageUrls.length) {
            _applyUnifiedHeight(availableWidth, setStateIfChanged: true);
          }
        } else {
          _measuringUrls.remove(imageUrl);
          _useDefaultSize(imageUrl, availableWidth);
        }
        return;
      }

      // 🎯 일반 이미지: 공통 유틸리티 사용
      final size = await ImageSizeUtils.measureImageSize(imageUrl);

      if (!mounted) {
        _measuringUrls.remove(imageUrl);
        return;
      }

      if (size != null) {
        _imageSizes[imageUrl] = size;
        _measuringUrls.remove(imageUrl);

        assert(() {
          debugPrint(
            '[RowImage] ✅ 이미지 크기 측정 완료: $imageUrl -> ${size.width.toInt()}x${size.height.toInt()}',
          );
          return true;
        }());

        if (widget.isEditing) {
          _saveImageSizeToMetadata(imageUrl, size);
        }

        if (_imageSizes.length == widget.imageUrls.length) {
          _applyUnifiedHeight(availableWidth, setStateIfChanged: true);
        }
      } else {
        _measuringUrls.remove(imageUrl);
        _useDefaultSize(imageUrl, availableWidth);
      }
    } catch (e) {
      _measuringUrls.remove(imageUrl);
      debugPrint('[RowImage] ⚠️ 측정 실패: $imageUrl - $e');
      _useDefaultSize(imageUrl, availableWidth);
    }
  }

  /// 기본 크기 사용 (3:4 비율)
  void _useDefaultSize(String imageUrl, double availableWidth) {
    if (_imageSizes.containsKey(imageUrl)) return;

    final count = widget.imageUrls.length;
    final spacingWidth = widget.spacing * (count - 1);
    final eachWidth = (availableWidth - spacingWidth) / count;
    final defaultHeight = eachWidth / (3 / 4); // 3:4 비율

    _imageSizes[imageUrl] = Size(eachWidth, defaultHeight);
    debugPrint(
      '[RowImage] 📏 기본 크기 사용: $imageUrl -> ${eachWidth.toInt()}x${defaultHeight.toInt()}',
    );

    // 모든 이미지 크기가 결정되면 높이 재계산
    if (_imageSizes.length == widget.imageUrls.length) {
      _applyUnifiedHeight(availableWidth, setStateIfChanged: true);
    }
  }

  /// Image 위젯에서 실제 크기 추출 (이미 로드된 이미지)
  /// 🎯 공통 유틸리티 사용: ImageProvider의 ImageStreamListener를 사용하여 ImageInfo에서 크기 추출
  void _extractSizeFromImageWidget(
    String imageUrl,
    double availableWidth,
    Widget? imageWidget,
  ) async {
    if (!mounted ||
        _imageSizes.containsKey(imageUrl) ||
        _measuringUrls.contains(imageUrl)) {
      return;
    }

    _measuringUrls.add(imageUrl);

    try {
      // 🎯 공통 유틸리티 사용
      final size = await ImageSizeUtils.extractSizeFromImageProvider(imageUrl);

      if (!mounted) {
        _measuringUrls.remove(imageUrl);
        return;
      }

      if (size != null) {
        _imageSizes[imageUrl] = size;
        _measuringUrls.remove(imageUrl);

        assert(() {
          debugPrint(
            '[RowImage] ✅ ImageInfo에서 크기 추출: $imageUrl -> ${size.width.toInt()}x${size.height.toInt()}',
          );
          return true;
        }());

        if (widget.isEditing) {
          _saveImageSizeToMetadata(imageUrl, size);
        }

        if (_imageSizes.length == widget.imageUrls.length) {
          _applyUnifiedHeight(availableWidth, setStateIfChanged: true);
        }
      } else {
        _measuringUrls.remove(imageUrl);
        _useDefaultSize(imageUrl, availableWidth);
      }
    } catch (e) {
      _measuringUrls.remove(imageUrl);
      debugPrint('[RowImage] ⚠️ Image 위젯에서 크기 추출 실패: $imageUrl - $e');
      _useDefaultSize(imageUrl, availableWidth);
    }
  }

  /// 🎯 성능 최적화: EditorService 캐싱 조회
  EditorService? _getEditorService() {
    // 🎯 dragService를 통해 editorService 접근 (Provider context 문제 방지)
    if (widget.dragService != null) {
      try {
        final editorService =
            (widget.dragService as dynamic).editorService as EditorService?;
        if (editorService != null) {
          _cachedEditorService = editorService;
          _editorServiceInitialized = true;
          return editorService;
        }
      } catch (e) {
        debugPrint('[RowImage] dragService를 통한 EditorService 접근 실패: $e');
      }
    }

    // 🎯 dragService가 없으면 Provider로 접근 시도 (fallback)
    if (!_editorServiceInitialized) {
      try {
        _cachedEditorService = Provider.of<EditorService>(
          context,
          listen: false,
        );
      } catch (e) {
        debugPrint('[RowImage] Provider로 EditorService 접근 실패: $e');
        _cachedEditorService = null;
      }
      _editorServiceInitialized = true;
    }
    return _cachedEditorService;
  }

  /// 측정된 이미지 크기를 노드 메타데이터에 저장
  /// 🎯 성능 최적화: 로컬 경로와 네트워크 URL 모두 키로 저장 (나중에 매칭 용이)
  void _saveImageSizeToMetadata(String imageUrl, Size size) {
    try {
      assert(() {
        debugPrint(
          '[RowImage] 💾 이미지 크기 저장 시작: nodeId=${widget.nodeId}, url=$imageUrl, size=${size.width.toInt()}x${size.height.toInt()}',
        );
        return true;
      }());

      final editorService = _getEditorService();
      if (editorService == null) {
        assert(() {
          debugPrint('[RowImage] ⚠️ EditorService를 찾을 수 없어서 저장 실패');
          return true;
        }());
        return;
      }

      final doc = editorService.document;
      final node = doc.getNodeById(widget.nodeId);

      if (node is ImageRowNode) {
        final meta = node.metadata;
        final imageDimensions = Map<String, dynamic>.from(
          (meta['imageDimensions'] as Map<String, dynamic>?) ?? {},
        );

        final sizeData = {
          'width': size.width.toInt(),
          'height': size.height.toInt(),
        };

        // 🎯 성능 최적화: 이미 같은 크기가 저장되어 있으면 스킵
        final existingSize = imageDimensions[imageUrl] as Map<String, dynamic>?;
        if (existingSize != null &&
            existingSize['width'] == size.width.toInt() &&
            existingSize['height'] == size.height.toInt()) {
          return; // 동일한 크기는 재저장하지 않음
        }

        // 🎯 로컬 경로를 키로 저장
        imageDimensions[imageUrl] = sizeData;

        // 🎯 성능 최적화: 업로드된 네트워크 URL도 키로 저장 (나중에 매칭 용이)
        final uploadedUrls = meta['uploadedUrls'] as Map<String, dynamic>?;
        if (uploadedUrls != null && uploadedUrls.containsKey(imageUrl)) {
          final networkUrl = uploadedUrls[imageUrl].toString();
          if (networkUrl.isNotEmpty) {
            imageDimensions[networkUrl] = sizeData;
          }
        }

        final updatedNode = node.copyWith(
          metadata: {...meta, 'imageDimensions': imageDimensions},
        );

        editorService.document.replaceNodeById(widget.nodeId, updatedNode);

        assert(() {
          assert(() {
            debugPrint(
              '[RowImage] ✅ 이미지 크기 저장 완료: nodeId=${widget.nodeId}, url=$imageUrl, size=${size.width.toInt()}x${size.height.toInt()}',
            );
            return true;
          }());
          return true;
        }());
      } else {
        assert(() {
          debugPrint(
            '[RowImage] ⚠️ ImageRowNode를 찾을 수 없음: nodeId=${widget.nodeId}',
          );
          return true;
        }());
      }
    } catch (e, stackTrace) {
      assert(() {
        debugPrint('[RowImage] ❌ 메타데이터 저장 실패: $e');
        debugPrint('[RowImage] 스택: $stackTrace');
        return true;
      }());
    }
  }

  /// 기본 쉬머 높이 계산 (3:4 비율 - 기본 폰 카메라 비율)
  double _calculateDefaultShimmerHeight(double maxWidth) {
    final count = widget.imageUrls.length;
    final spacingWidth = widget.spacing * (count - 1);
    final eachWidth = (maxWidth - spacingWidth) / count;
    return eachWidth / (3 / 4); // 3:4 비율
  }

  double? _computeUnifiedHeightValue(double availableWidth) {
    if (!mounted || widget.imageUrls.isEmpty) return null;

    final count = widget.imageUrls.length;
    final spacingWidth = widget.spacing * (count - 1);
    final eachWidth = (availableWidth - spacingWidth) / count;

    double totalHeight = 0;
    int validCount = 0;

    for (final url in widget.imageUrls) {
      final size = _imageSizes[url];
      if (size != null && size.width > 0) {
        final aspectRatio = size.height / size.width;
        totalHeight += eachWidth * aspectRatio;
        validCount++;
      }
    }

    if (validCount == 0) return null;

    final avg = totalHeight / validCount;
    final unified = avg.clamp(150.0, 400.0);

    return unified;
  }

  /// 통일된 높이 계산/적용 (모든 이미지 측정 완료 후)
  void _applyUnifiedHeight(
    double availableWidth, {
    required bool setStateIfChanged,
  }) {
    final unified = _computeUnifiedHeightValue(availableWidth);
    if (unified == null) return;

    if (_unifiedHeight == unified) return;

    if (setStateIfChanged) {
      setState(() => _unifiedHeight = unified);
    } else {
      _unifiedHeight = unified;
    }
  }

  bool _shouldShowTopDropLine() {
    return DropLineConfig.shouldShowTopDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
      isRowImage: true, // 🎯 RowImageComponent
    );
  }

  bool _shouldShowBottomDropLine() {
    return DropLineConfig.shouldShowBottomDropLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
      isRowImage: true, // 🎯 RowImageComponent
    );
  }

  bool _shouldShowLeftVerticalLine() {
    // 🎯 DropLineConfig 사용 (3개 가득 찬 로우 이미지 체크 포함)
    return DropLineConfig.shouldShowLeftVerticalLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _shouldShowRightVerticalLine() {
    // 🎯 DropLineConfig 사용 (3개 가득 찬 로우 이미지 체크 포함)
    return DropLineConfig.shouldShowRightVerticalLine(
      nodeId: widget.nodeId,
      dragService: widget.dragService,
    );
  }

  bool _hasNeighborImage(Document? doc, String nodeId, int direction) {
    if (doc == null) return false;
    final myIndex = doc.getNodeIndexById(nodeId);
    if (myIndex == -1) return false;

    // 🎯 바로 인접한 노드 확인
    final immediateIndex = myIndex + direction;
    if (immediateIndex >= 0 && immediateIndex < doc.nodeCount) {
      final immediateNeighbor = doc.getNodeAt(immediateIndex);
      if (immediateNeighbor != null) {
        // 바로 인접한 노드가 특수 노드인 경우 (정책은 NodeTypeChecker/config에서 단일 관리)
        if (NodeTypeChecker.isSpecialNode(immediateNeighbor)) {
          return true;
        }

        // 바로 인접한 노드가 빈 ParagraphNode인 경우
        if (immediateNeighbor is ParagraphNode) {
          final isEmpty = immediateNeighbor.text.text.trim().isEmpty;

          // 빈 ParagraphNode면 그 다음 노드를 확인
          if (isEmpty) {
            // 빈 ParagraphNode 다음 노드 확인
            final nextIndex = immediateIndex + direction;
            if (nextIndex >= 0 && nextIndex < doc.nodeCount) {
              final nextNeighbor = doc.getNodeAt(nextIndex);
              if (NodeTypeChecker.isSpecialNode(nextNeighbor)) {
                // 빈 ParagraphNode를 사이에 둔 특수 노드 → 패딩 필요 (false 반환)
                return false;
              }
            }
            // 빈 ParagraphNode 다음에 특수 노드가 없으면 계속 검색
          } else if (!isEmpty) {
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
      if (NodeTypeChecker.isSpecialNode(neighbor)) {
        return true;
      }

      // 빈 ParagraphNode가 아니면 (텍스트가 있는 경우) 패딩 필요
      if (neighbor is ParagraphNode) {
        final isEmpty = neighbor.text.text.trim().isEmpty;
        // 비어있지 않으면 텍스트 노드이므로 패딩 필요
        if (!isEmpty) {
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

    if (myIndex == start) {
      final boundary = baseIndex == start ? selection.base : selection.extent;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        // ✅ start 경계는 upstream일 때 포함 (아래→위 드래그 대칭 보장)
        return pos.affinity == TextAffinity.upstream;
      }
    }
    if (myIndex == end) {
      final boundary = extentIndex == end ? selection.extent : selection.base;
      final pos = boundary.nodePosition;
      if (pos is UpstreamDownstreamNodePosition) {
        return pos.affinity == TextAffinity.downstream;
      }
    }
    return true;
  }

  /// 🎯 Row 이미지 위젯 빌드 (로컬/네트워크 자동 판단)
  Widget _buildRowImageWidget(int index, String imageUrl, double maxWidth) {
    // ✅ 읽기 모드에서도 decodeWidth를 줘야 PostReaderService.preloadTopMedia(precacheImage)와
    // 동일한 ResizeImage(width) 캐시 키로 hit가 난다.
    final decodeWidth = EditorImageProvider.editingDecodeWidth(
      context,
      widget.screenWidth,
    );

    final built = EditorImageProvider.build(
      url: imageUrl,
      isEditing: widget.isEditing,
      decodeWidth: decodeWidth,
    );
    if (!built.isLocal) {
      _lastNetworkProviders[imageUrl] = built.baseProvider;
    }

    return Image(
      key: _rowImageKey(index, imageUrl),
      image: built.effectiveProvider,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true, // ✅ provider가 바뀌어도 기존 프레임 유지
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        final ready = wasSyncLoaded || frame != null;
        if (ready) {
          _lastRenderedByUrl[imageUrl] = child;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_imageSizes.containsKey(imageUrl) &&
                !_measuringUrls.contains(imageUrl)) {
              if (built.isLocal) {
                _measureAndUnifyHeight(imageUrl, maxWidth);
              } else {
                _extractSizeFromImageWidget(imageUrl, maxWidth, child);
              }
            }
          });
          return child;
        }

        // 로딩 중: 이전 프레임이 있으면 유지해서 "사라짐"을 방지한다.
        final last = _lastRenderedByUrl[imageUrl];
        if (last != null) return last;

        // 첫 로딩: unifiedHeight 있으면 그 높이로, 없으면 기본 비율
        return Container(
          width: double.infinity,
          height: _unifiedHeight ?? _calculateDefaultShimmerHeight(maxWidth),
          color:
              widget.isDarkMode
                  ? Colors.grey[900]?.withOpacity(0.1)
                  : Colors.grey[200]?.withOpacity(0.3),
        );
      },
      errorBuilder: (context, error, stack) {
        debugPrint('[RowImage] 이미지 로드 실패: $imageUrl, $error');
        return ImageErrorPlaceholder(width: 200);
      },
    );
  }
}

class _RowImageSpoilerPainter extends CustomPainter {
  final double phase;
  final bool isEditing;
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;
  _RowImageSpoilerPainter({
    required this.phase,
    required this.isEditing,
    required this.backgroundColor,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 초기 프레임 등에서 Size가 0인 경우 NaN이 발생하지 않도록 보호
    if (size.width <= 0 || size.height <= 0) return;
    final rect = Offset.zero & size;
    final mask = Paint()..style = PaintingStyle.fill;
    // 배경 칠하기는 명시적으로 투명색이 아닌 경우에만 수행
    if (backgroundColor.alpha != 0) {
      final double alpha = isEditing ? 0.4 : 1.0;
      if (alpha > 0) {
        mask.color = backgroundColor.withOpacity(alpha);
        canvas.drawRect(rect, mask);
      }
    }
    // 점을 더 선명하게 (높은 불투명도)
    final dotOpacity = isLightTheme ? 0.9 : 0.95;
    final dot =
        Paint()
          ..style = PaintingStyle.fill
          ..color = dotColor.withOpacity(dotOpacity);

    final area = rect.width * rect.height;
    // 밀도 상향: 행에서도 충분한 알갱이 수 유지
    final count =
        isEditing
            ? math.max(300, (area / 1200).floor())
            : math.max(400, (area / 900).floor());
    // 속도 더 낮춤 (row 전용)
    final double t = phase * (2 * math.pi) * 0.9;

    // 기본 점들 그리기 (크기 2.2, 움직임/깜빡임 강화)
    for (int i = 0; i < count; i++) {
      final seed = rect.hashCode ^ (i * 486187739);
      final r = math.Random(seed);
      final baseX = r.nextDouble() * rect.width;
      final baseY = r.nextDouble() * rect.height;
      // 진폭 더 낮춤 (움직임 강도 추가 감소)
      final amp = 0.6 + r.nextDouble() * 3.0; // 0.6~3.6px
      final ox = math.sin(t + i * 0.21) * amp;
      final oy = math.cos(t * 0.9 + i * 0.13) * amp;
      double x = baseX + ox;
      double y = baseY + oy;
      // width/height가 0일 경우 나눗셈으로 NaN이 발생하지 않도록 방어
      if (rect.width > 0)
        x = x % rect.width;
      else
        x = 0;
      if (rect.height > 0)
        y = y % rect.height;
      else
        y = 0;
      if (x < 0) x += rect.width;
      if (y < 0) y += rect.height;
      // 별 깜빡임 효과: 점마다 약간 다른 투명도 변조
      final twinkle = 0.7 + 0.3 * math.sin(t * 1.0 + i * 0.45);
      final p = dot..color = dot.color.withOpacity(dotOpacity * twinkle);
      // 알갱이 크기 축소
      final sizePx = 1.0 + r.nextDouble() * 1.4; // 1.0~2.4px 원형
      canvas.drawCircle(Offset(x, y), sizePx / 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RowImageSpoilerPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.isEditing != isEditing;
  }
}

/// 이미지 행 스포일러 scatter 애니메이션 페인터
class _RowImageSpoilerScatterPainter extends CustomPainter {
  final double progress; // 0..1 진행도
  final Color backgroundColor;
  final Color dotColor;
  final bool isLightTheme;

  _RowImageSpoilerScatterPainter({
    required this.progress,
    required this.backgroundColor,
    required this.dotColor,
    required this.isLightTheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseOpacity = isLightTheme ? 0.4 : 0.6;
    final fade = (1.0 - Curves.easeOut.transform(progress)).clamp(0.0, 1.0);
    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = backgroundColor.withOpacity(baseOpacity * fade);

    final area = rect.width * rect.height;
    final count = math.max(80, (area / 220).floor());
    final cx = rect.center.dx;
    final cy = rect.center.dy;

    for (int i = 0; i < count; i++) {
      final seed = rect.hashCode ^ (i * 1009);
      final r = math.Random(seed);
      final rx = r.nextDouble() * rect.width;
      final ry = r.nextDouble() * rect.height;
      final startX = rect.left + rx;
      final startY = rect.top + ry;

      // 중심에서 방사형 퍼짐
      final dirX = (startX - cx);
      final dirY = (startY - cy);
      final dirLen = math.sqrt(dirX * dirX + dirY * dirY) + 0.001;
      final nx = dirX / dirLen;
      final ny = dirY / dirLen;
      final speed = 30 + r.nextDouble() * 44; // px
      final move = Curves.easeOutQuad.transform(progress) * speed;
      final x = startX + nx * move;
      final y = startY + ny * move;
      final sz = 1.2 + (1.8 * (1.0 - progress));
      canvas.drawRect(Rect.fromLTWH(x, y, sz, sz), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RowImageSpoilerScatterPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// ImageRowNode의 뷰모델
class ImageRowComponentViewModel extends SingleColumnLayoutComponentViewModel {
  ImageRowComponentViewModel({
    required super.nodeId,
    required this.imageUrls,
    required this.spacing,
    this.unifiedHeight, // 🎯 사용하지 않음 (deprecated)
  }) : super(createdAt: DateTime.now(), padding: EdgeInsets.zero);

  final List<String> imageUrls;
  final double spacing;
  final double? unifiedHeight; // 🎯 metadata 의존 제거 (deprecated)

  @override
  SingleColumnLayoutComponentViewModel copy() {
    return ImageRowComponentViewModel(
      nodeId: nodeId,
      imageUrls: imageUrls,
      spacing: spacing,
      unifiedHeight: null, // 항상 null
    );
  }
}
