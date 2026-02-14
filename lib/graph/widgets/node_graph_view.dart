import 'dart:async';
import 'dart:math' as math;
import 'package:doppy/graph/camera/graph_camera_controller.dart';
import 'package:doppy/graph/rendering/canvas.dart';
import 'package:doppy/graph/utils/node_count_utils.dart';
import 'package:doppy/graph/models/node.dart';
import 'package:doppy/graph/models/edge.dart';
import 'package:doppy/graph/layout/force_directed_layout.dart';
import 'package:doppy/utils/typograpy_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/providers/graph_provider.dart';

enum NodeGraphMode {
  /// 온보딩: 확대/탭 프레지 없이 “노드 드래그만” 허용
  onboarding,
  normal,
  searching,

  /// 발행 후 웹소켓 응답 대기 중 (검색과 동일한 파도 효과)
  publishing,
  searchResult,
}

/// 재사용 가능한 노드 그래프 시각화 위젯
///
/// 파라미터로 그래프 데이터와 설정을 주입받아 사용할 수 있습니다.
///
/// 예시:
/// ```dart
/// NodeGraphView(
///   graph: myGraphData,
///   onNodeTap: (nodeId) => print('Tapped: $nodeId'),
///   selectedNodeId: _selectedId,
///   onNodeSelected: (id) => setState(() => _selectedId = id),
/// )
/// ```
class NodeGraphView extends StatefulWidget {
  /// 그래프 데이터 (필수)
  final GraphData graph;

  /// 인터랙션/렌더링 모드
  final NodeGraphMode mode;

  /// 검색 결과 노드 ID (mode == searchResult일 때 강조, 비결과 노드 페이드)
  final Set<int>? resultNodeIds;

  /// 온보딩 전용: 검색결과 모드에서 비결과 노드를 약간 연하게만(0.35),
  /// 검색결과→일반 복귀 시 부드러운 애니메이션 지원을 위해 searchResultExitT 사용
  final bool onboardingSearchResult;

  /// 온보딩 전용: 검색결과→일반 복귀 전환 시 0→1 (0=검색결과 룩, 1=일반)
  final double? searchResultExitT;

  /// 노드 탭 콜백
  final Function(int nodeId)? onNodeTap;

  /// 글 보기 화면으로 이동 (프레지 진입 불가 줌 구간 또는 프레지 모드 내 재탭 시 호출)
  final Function(int nodeId)? onNavigateToPost;

  /// 현재 선택된 노드 ID
  final int? selectedNodeId;

  /// 선택 변경 콜백
  final ValueChanged<int?>? onNodeSelected;

  /// 최대 축소 모드 여부 변경 시 콜백 (zoom <= minScale * 1.1)
  final ValueChanged<bool>? onIsAtMinScale;

  /// 노드 드래그 시작/종료 시 콜백 (드래그 중인 노드 ID, 종료 시 null)
  final ValueChanged<int?>? onNodeDragChange;

  /// 뷰포트(변환) 변경 시 콜백 (미니맵 등에 사용)
  final void Function(Matrix4 matrix)? onViewportChanged;

  /// 테마 primary 색상 (null이면 Theme에서 자동 추출)
  final Color? primaryColor;

  /// 다크모드 여부 (null이면 Theme에서 자동 추출)
  final bool? isDark;

  /// 간선 색상 (null이면 Theme에 따라 자동 설정)
  final Color? lineColor;

  /// 노드 색상 스킴 (null이면 primaryColor + 회색 fallback). 직접 색상 지정 시 사용
  final GraphNodeColorScheme? nodeColorScheme;

  /// 최소 줌 스케일 (null이면 자동 계산)
  final double? minScale;

  /// 최대 줌 스케일 (기본값: 5.0)
  final double? maxScale;

  /// 노드 반지름 (null이면 노드 수에 따라 자동 계산)
  final double? nodeRadius;

  /// 라벨 표시 여부 (기본값: true)
  final bool showLabels;

  /// 라벨 표시 줌 임계값: minScale 대비 배율 (기본값: 1.4 = 최소축소의 1.4배에서 라벨 표시)
  final double labelZoomThreshold;

  /// 최대 간선 수 (null이면 자동 계산)
  final int? maxEdges;

  /// 최소 간선 유사도 (기본값: 0.55)
  final double? minEdgeSimilarity;

  /// 노드 드래그 활성화 여부 (기본값: true)
  final bool enableNodeDrag;

  /// 배경색 (null이면 Theme에 따라 자동 설정)
  final Color? backgroundColor;

  /// InteractiveViewer boundaryMargin
  /// - 값이 클수록 화면 밖으로 더 많이 드래그 가능
  /// - “점들이 화면에서 많이 벗어나지 못하게” 하려면 작은 값 추천
  final EdgeInsets boundaryMargin;

  /// 손을 뗐을 때 그래프가 화면 밖으로 너무 나가 있으면, 보이는 영역 안으로
  /// 부드럽게 되돌릴지 여부
  final bool keepGraphVisibleOnRelease;

  /// keepGraphVisibleOnRelease 시 화면 가장자리 여유(픽셀)
  final double keepVisibleMargin;

  /// 드래그/핀치 중 그래프가 “너무 극단적으로” 화면 밖으로 나가는 것을 막는 역치(px)
  /// - 그래프 전체 bounds가 화면 밖으로 이 값 이상 벗어나면 그 이상은 “벽처럼” 더 안 나가게 clamp
  /// - 값이 클수록 더 많이 벗어날 수 있음
  final double panOutOfBoundsThreshold;

  /// 외곽 노드와 휴대폰 프레임 사이의 여백 (fit 계산에 사용)
  final double outerPadding;

  /// 줌인할수록 노드 간 거리가 더 멀어져 보이게(풍선 표면처럼 “팽팽”) 하는 렌더링 효과
  /// - 레이아웃(기본 node.position)은 변하지 않고, 렌더링/히트테스트만 확장 좌표를 사용
  final bool enableZoomSpacing;

  /// enableZoomSpacing일 때, spreadFactor = pow(zoom / minScale, exponent)
  final double zoomSpacingExponent;

  /// enableZoomSpacing일 때 spreadFactor 최대값
  final double zoomSpacingMax;

  /// 노드 드래그 시 1-hop(직접 연결) 이웃이 따라오는 정도 (0~1)
  /// - 값이 클수록 “탱탱하게” 따라오지만 예민해질 수 있음
  final double dragHop1Weight;

  /// 노드 드래그 시 2-hop 이웃이 따라오는 정도 (0~1)
  final double dragHop2Weight;

  /// 노드 드래그 중, 드래그 노드가 화면 중앙에서 멀어지면 카메라가 “살짝” 따라갈지
  final bool enableDragCameraFollow;

  /// 카메라 follow 시작 임계 거리(px)
  final double dragCameraFollowThresholdPx;

  /// 카메라 follow 강도(비율)
  final double dragCameraFollowStrength;

  /// 한 프레임에서 카메라가 이동할 수 있는 최대치(px)
  final double dragCameraFollowMaxDeltaPx;

  /// 최소 스케일 근처에서의 “커스텀 pan” 최소 감도 (작은 드래그용)
  final double minScalePanMinFactor;

  /// 최소 스케일 근처에서의 “커스텀 pan” 최대 감도 (큰 드래그용)
  final double minScalePanMaxFactor;

  /// 이 거리(px) 이상으로 드래그하면 minScalePanFactor가 max 쪽으로 가까워짐
  final double minScalePanBoostDistancePx;

  /// 최소 스케일 근처에서, 손을 뗐을 때 “센터로 복귀”를 할지 여부
  /// - true: 작은 드래그는 자연스럽게 복귀
  /// - false: min 상태에서도 사용자가 이동한 뷰포트를 유지
  final bool enableMinScaleReturnOnRelease;

  /// min 상태에서 손을 뗐을 때, 이 값(px) 미만으로 움직였으면 “의도치 않은 흔들림”으로 보고 복귀
  /// - 이보다 크게 드래그했다면 탐색 의도로 보고 복귀하지 않음
  final double minScaleReturnSlopPx;

  /// 최대 축소(min 근처)에서만 적용되는 “soft wall” 오버스크롤 허용치(px)
  /// - 끝쪽 노드 방향으로 너무 멀리 벗어나지 못하게 제한
  final double minScaleSoftWallOverscrollPx;

  /// soft wall 강도 (0~1)
  /// - 1.0에 가까울수록 벽이 딱딱해짐
  final double minScaleSoftWallStrength;

  /// min(최대 축소) 모드에서의 pan 감도 (0~1)
  /// - 1.0이면 기본 감도에 가까움, 낮을수록 둔감
  final double minScalePanSensitivity;

  /// min(최대 축소) 모드에서의 pan 스무딩 (0~1)
  /// - 값이 작을수록 더 “부드럽고 고급스럽게” 늦게 따라옴
  final double minScalePanSmoothing;

  /// min 모드에서 한 이벤트당 입력 delta 클램프(px) - “툭 튐” 방지
  final double minScalePanMaxInputDeltaPx;

  /// 간선 렌더링 모드
  /// - all: 기존처럼 필터링된 엣지를 그대로
  /// - representativeStar: 클러스터 대표 1개에서만 바깥으로 뻗는 형태
  final EdgeRenderMode edgeRenderMode;

  /// representativeStar 모드에서 클러스터당 최대 간선 수
  final int representativeMaxEdgesPerCluster;

  /// true면 ForceDirectedLayout 스킵, node.position 그대로 사용 (온보딩 하드코딩 등)
  final bool useProvidedPositions;

  /// 레이아웃 후 위치 지터 (0이면 없음). 온보딩 등 불규칙성 추가용 (0.15~0.25 권장)
  final double? layoutIrregularity;

  /// min(최대 축소) 모드에서 “손가락 중심으로 당기는 듯한” 동적 팬 워프(국소 변형) 사용
  /// - 레이아웃(실제 node.position)은 건드리지 않고 렌더링 좌표에만 적용
  final bool enableMinScalePanWarp;

  /// 워프 강도 (scene delta에 곱해짐)
  final double minScalePanWarpStrength;

  /// 워프 반경(px) - 손가락 근처일수록 더 많이 따라오고, 멀수록 덜 움직임
  final double minScalePanWarpRadiusPx;

  /// 워프 최대 오프셋(px) - 과한 왜곡 방지
  final double minScalePanWarpMaxOffsetPx;

  /// 워프 중심(손가락)을 얼마나 부드럽게 따라갈지 (0~1)
  final double minScalePanWarpCenterSmoothing;

  /// 손을 떼면 워프가 제자리로 돌아오는 시간
  final Duration minScalePanWarpReturnDuration;

  /// 프레지(줌인) 상태에서의 pan 감도 (0~1)
  /// - 줌이 커질수록 “예민함”을 낮추기 위해 InteractiveViewer pan 대신 커스텀 pan 사용
  final double preziPanSensitivity;

  /// 프레지 pan 스무딩 (0~1)
  final double preziPanSmoothing;

  /// 선택된 노드가 있고 줌이 이 값 이상이면 프레지 pan 모드로 간주
  final double preziPanThresholdScale;

  /// 프레지 줌인 시 노드가 화면에 “안 잘리도록” 확보할 여백(px)
  final double preziKeepOnScreenMarginPx;

  /// 확대 1단계(middle1) 근처에서의 pan 감도 (0~1). 낮을수록 드래그가 둔감해짐.
  final double firstZoomStepPanSensitivity;

  const NodeGraphView({
    super.key,
    required this.graph,
    this.mode = NodeGraphMode.normal,
    this.resultNodeIds,
    this.onboardingSearchResult = false,
    this.searchResultExitT,
    this.onNodeTap,
    this.onNavigateToPost,
    this.selectedNodeId,
    this.onNodeSelected,
    this.onIsAtMinScale,
    this.onNodeDragChange,
    this.onViewportChanged,
    this.primaryColor,
    this.isDark,
    this.lineColor,
    this.nodeColorScheme,
    this.minScale,
    this.maxScale = 5.0,
    this.nodeRadius,
    this.showLabels = true,
    this.labelZoomThreshold = 1.4,
    this.maxEdges,
    this.minEdgeSimilarity = 0.55,
    this.enableNodeDrag = true,
    this.backgroundColor,
    this.boundaryMargin = const EdgeInsets.all(24),
    this.keepGraphVisibleOnRelease = true,
    this.keepVisibleMargin = 36,
    this.panOutOfBoundsThreshold = 140,
    this.outerPadding = 24,
    this.enableZoomSpacing = true,
    this.zoomSpacingExponent = 0.55, // 0.35 -> 0.55: 확대할수록 더 빠르게 거리 증가
    this.zoomSpacingMax = 2.8, // 2.0 -> 2.8: 최대 확대 시 더 멀어짐
    // 드래그 시 이웃이 “자유롭고 탱탱하게” 따라오도록 기본값 상향
    this.dragHop1Weight = 0.78,
    this.dragHop2Weight = 0.42,
    this.enableDragCameraFollow = false,
    this.dragCameraFollowThresholdPx = 140,
    this.dragCameraFollowStrength = 0.06,
    this.dragCameraFollowMaxDeltaPx = 10,
    this.minScalePanMinFactor = 0.22,
    this.minScalePanMaxFactor = 0.55,
    this.minScalePanBoostDistancePx = 140,
    this.enableMinScaleReturnOnRelease = true,
    this.minScaleReturnSlopPx = 70,
    // 기본값은 “좀 더 제한” 쪽으로: 끝쪽 노드 근처에서 과하게 멀리 못 나가게
    this.minScaleSoftWallOverscrollPx = 20,
    this.minScaleSoftWallStrength = 0.9,
    this.minScalePanSensitivity = 0.28,
    this.minScalePanSmoothing = 0.22,
    this.minScalePanMaxInputDeltaPx = 90,
    this.edgeRenderMode = EdgeRenderMode.representativeStar,
    this.representativeMaxEdgesPerCluster = 10,
    this.useProvidedPositions = false,
    this.layoutIrregularity,
    // min-scale pan warp(최대 축소에서 “딸려오는 베리에이션”): 화면 드래그 중에만 동작하고
    // release 시 즉시 리셋하므로(드리프트 없음) 기본값을 켬.
    this.enableMinScalePanWarp = true,
    this.minScalePanWarpStrength = 0.75,
    this.minScalePanWarpRadiusPx = 240,
    this.minScalePanWarpMaxOffsetPx = 90,
    this.minScalePanWarpCenterSmoothing = 0.35,
    this.minScalePanWarpReturnDuration = const Duration(milliseconds: 520),
    this.preziPanSensitivity = 0.28,
    this.preziPanSmoothing = 0.20,
    this.preziPanThresholdScale = 1.6,
    this.preziKeepOnScreenMarginPx = 28,
    this.firstZoomStepPanSensitivity = 1.2,
  });

  @override
  State<NodeGraphView> createState() => _NodeGraphViewState();
}

class _NodeGraphViewState extends State<NodeGraphView>
    with TickerProviderStateMixin {
  late final GraphCameraController _camera;
  bool _viewportCallbackScheduled = false;
  Matrix4? _pendingViewportMatrix;
  int? _internalSelectedNodeId;
  int _graphRevision = 0;
  Size? _lastWorldSize;
  Size? _lastScreenSizeForFit;
  double _maxScreenHeight = 0;
  bool _layoutInitialized = false;
  double? _minScale;
  double? _maxPinchScale; // 양자화: 핀치로 도달 가능한 최대 (라벨 보이는 단계)
  Matrix4? _homeTransform; // “그래프 로드 직후” 홈(초기) 카메라 위치
  Offset? _structureCenter; // 줌 스프레드 기준 “고정 중심”(벡터/비율 유지)

  // 렌더링/히트테스트용 “확장된” 좌표 캐시 (줌에 따라 변경, 레이아웃 자체는 유지)
  final Map<int, Offset> _displayPos = <int, Offset>{};
  double _displaySpread = 1.0;
  double _lastDisplaySpread = -1.0;
  int _lastDisplayRevision = -1;
  double _lastZoom = -1.0;

  // “가드 노드(대표/선택)” 캐시: 화면에 최소 1개는 보이게 만드는 기준 노드 집합
  List<int>? _cachedGuardNodeIds;
  int _lastGuardRevision = -1;
  EdgeRenderMode? _lastGuardEdgeMode;

  bool? _lastReportedIsAtMinScale;

  // (removed) onInteraction* 기반 보정은 “툭 튐”을 만들 수 있어 사용하지 않음
  bool _lastGestureWasPinch = false;
  int _pinchDirection = 0; // -1: zoom out, +1: zoom in (핀치 중 마지막 방향)
  bool _isViewerInteracting = false; // InteractiveViewer 제스처 진행 중
  int _skipMinReturnUntilMs = 0; // 핀치 스냅 직후 onPointerUp "home 복귀" 충돌 방지
  double? _gestureStartZoom; // 핀치 방향 안정 판별용
  int? _gestureStartZoomLevelIdx; // 핀치 시작 시 “양자화 단계” (min/m1/m2)
  Offset? _lastPinchFocalLocal; // 핀치 종료 시 스냅 기준점(로컬 좌표)
  bool _preziDragConsumed = false; // 프레지에서 “드래그=한단계 축소” 1회만 발동
  Matrix4? _preziReturnTransform; // 프레지(줌인) 진입 직전 카메라(복귀용)
  bool _preziPinchExitActive = false; // 프레지 핀치아웃 제스처 진행 중(pan 드리프트 억제용)

  /// 핀치(줌) 감지 역치: 낮을수록 민감. 값을 올려 “의도된 핀치”만 인정 → 2단계 한번에 넘어가는 현상 완화.
  static const double _pinchDetectThreshold = 0.22;

  late final AnimationController _nodeReturnController;
  Animation<double>? _nodeReturnAnim;
  bool _isNodeReturning = false;
  final Map<int, Offset> _nodeReturnFrom = <int, Offset>{};
  final Map<int, Offset> _nodeReturnTo = <int, Offset>{};

  // === Node drag (Obsidian-style) ===
  bool _isNodeDragging = false;
  int? _dragRootNodeId;
  Offset _dragStartScene = Offset.zero;
  final Map<int, Offset> _dragStartPositions = <int, Offset>{};
  final Map<int, double> _dragWeights = <int, double>{};
  Matrix4? _dragStartCamera; // 노드 드래그 시작 시 뷰포트(카메라) 저장

  // manual long-press (gesture arena 회피)
  Timer? _nodeDragTimer;
  int? _primaryPointer;
  Offset? _primaryDownLocal;

  /// 2개 이상이면 핀치 모드 → pan/드래그 완전 차단
  final Set<int> _activePointers = {};
  // === Pinch (trigger-only) ===
  // 유저 핀치는 “트리거(방향/시점)만”으로 사용하고, 실제 줌은 자동 애니메이션으로만 처리
  final Map<int, Offset> _pointerLocalPos = <int, Offset>{};
  bool _pinchGestureActive = false;
  double? _pinchStartDistance;
  bool _pinchTriggered = false;
  Offset? _pinchFocalLocal;
  static const double _pinchTriggerRatioThreshold =
      0.06; // 거리 6% 변화부터 트리거 (너무 크면 작은 축소가 감지 안 됨)
  /// Listener(onPointerUp)에서 이미 양자화 스냅을 실행했으면 onInteractionEnd에서 중복 스냅 방지
  bool _pinchSnapHandledInPointerUp = false;
  bool _primaryMoved = false;
  static const double _dragSlop = 8.0;
  bool _selectionClearedByDrag = false;
  Offset? _lastPanLocal; // min 모드 커스텀 pan용
  Offset? _minPanTargetTranslation; // min 모드 “부드러운” 카메라 follow 타겟

  // === Min-scale pan warp (finger-centric dynamic feel) ===
  // - layout(node.position)은 그대로 두고, 렌더링/히트테스트 좌표만 국소 변형
  Offset? _minPanWarpCenterScene;
  Offset _minPanWarpOffsetScene = Offset.zero; // scene units
  late final AnimationController _minPanWarpReturnController;
  Offset _minPanWarpReturnFrom = Offset.zero;

  late final AnimationController _dragFadeController;
  late final Animation<double> _dragFade;

  /// 페이드 역재생 중 드래그 그룹 유지 (끝날 때까지 연해짐 방지)
  Set<int>? _lastDragGroupForFade;

  late final AnimationController _searchWaveController;
  late final AnimationController _searchResultIntroController;

  late final AnimationController _compressionAnimController;
  double _displayedCompressionFactor = 1.0;
  double _compressionAnimFrom = 1.0;
  double _compressionAnimTo = 1.0;

  /// 처음 등장 시 노드들이 중앙에서 제자리로 흩어지는 인트로 애니메이션 (~1초)
  late final AnimationController _layoutIntroController;

  /// setState during build 방지: 애니메이션 리스너에서 사용
  void _scheduleRebuild() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _camera = GraphCameraController(vsync: this);
    _camera.addListener(_onCameraChanged);

    _nodeReturnController =
        AnimationController(
            vsync: this,
            // “고무줄 복귀” 더 느리고 고무줄처럼: 노드 위치 복귀
            duration: const Duration(milliseconds: 1000),
          )
          ..addListener(() {
            final a = _nodeReturnAnim;
            if (a == null) return;
            final t = a.value;
            // 노드 좌표를 lerp로 원래 위치로 복귀
            for (final entry in _nodeReturnTo.entries) {
              final id = entry.key;
              final to = entry.value;
              final from = _nodeReturnFrom[id];
              if (from == null) continue;
              final node = widget.graph.getNodeById(id);
              if (node == null) continue;
              node.position = Offset.lerp(from, to, t)!;
            }
            _graphRevision++;
            _scheduleRebuild();
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed) {
              // 최종 위치로 정확히 스냅 (부동소수점 누적 오차 방지)
              for (final entry in _nodeReturnTo.entries) {
                final node = widget.graph.getNodeById(entry.key);
                if (node != null) node.position = entry.value;
              }
              _isNodeReturning = false;
              _nodeReturnFrom.clear();
              _nodeReturnTo.clear();
              _nodeReturnAnim = null;
              _graphRevision++;
              _scheduleRebuild();
            }
          });

    _dragFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _dragFade = CurvedAnimation(
      parent: _dragFadeController,
      curve: Curves.easeOutCubic,
    );
    _dragFadeController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        _lastDragGroupForFade = null;
      }
    });

    _minPanWarpReturnController =
        AnimationController(
            vsync: this,
            duration: widget.minScalePanWarpReturnDuration,
          )
          ..addListener(() {
            if (!_minPanWarpReturnController.isAnimating) return;
            final t = Curves.easeOutCubic.transform(
              _minPanWarpReturnController.value,
            );
            _minPanWarpOffsetScene =
                Offset.lerp(_minPanWarpReturnFrom, Offset.zero, t)!;
            _scheduleRebuild();
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed) {
              // 워프 종료 후 좌표계 정리 (다음 제스처에서 ‘툭’ 튐 방지)
              _minPanWarpOffsetScene = Offset.zero;
              _minPanWarpCenterScene = null;
            }
          });

    _searchWaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.mode == NodeGraphMode.searching ||
        widget.mode == NodeGraphMode.publishing) {
      _searchWaveController.repeat();
    }

    _searchResultIntroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.mode == NodeGraphMode.searchResult) {
      _searchResultIntroController.forward(from: 0);
    }

    _compressionAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..addListener(_scheduleRebuild);
    _compressionAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _displayedCompressionFactor = _compressionAnimTo;
      }
    });

    _layoutIntroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_scheduleRebuild);
  }

  void _onCameraChanged() {
    final cb = widget.onViewportChanged;
    if (cb == null) return;
    _pendingViewportMatrix = _camera.value.clone();
    if (_viewportCallbackScheduled) return;
    _viewportCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportCallbackScheduled = false;
      if (!mounted) return;
      final m = _pendingViewportMatrix;
      if (m != null) cb(m);
    });
  }

  @override
  void didUpdateWidget(NodeGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.graph != widget.graph) {
      // 상위에서 GraphData를 매 build마다 새로 만들면, 여기서 레이아웃을 계속 리셋해서 “뷰 튐”이 발생함.
      // 노드 집합(id)이 동일하면 기존 position을 새 그래프에 이식하고 레이아웃은 유지.
      final oldNodes = oldWidget.graph.nodes;
      final newNodes = widget.graph.nodes;
      if (oldNodes.length == newNodes.length && oldNodes.isNotEmpty) {
        final oldById = {for (final n in oldNodes) n.id: n};
        var sameIds = true;
        for (final n in newNodes) {
          final oldN = oldById[n.id];
          if (oldN == null) {
            sameIds = false;
            break;
          }
          n.position = oldN.position;
        }
        if (sameIds) {
          _structureCenter = _computeStructureCenter();
          _graphRevision++;
        } else {
          _layoutInitialized = false;
          _lastWorldSize = null;
          _lastScreenSizeForFit = null;
          _structureCenter = null;
          _homeTransform = null;
          _graphRevision++;
        }
      } else {
        _layoutInitialized = false;
        _lastWorldSize = null;
        _lastScreenSizeForFit = null;
        _structureCenter = null;
        _homeTransform = null;
        _graphRevision++;
      }
    }
    if (oldWidget.selectedNodeId != widget.selectedNodeId) {
      _internalSelectedNodeId = widget.selectedNodeId;
    }
    if (oldWidget.mode != widget.mode) {
      if (widget.mode == NodeGraphMode.searching ||
          widget.mode == NodeGraphMode.publishing) {
        _searchWaveController.repeat();
      } else {
        _searchWaveController.stop();
        _searchWaveController.reset();
      }

      if (widget.mode == NodeGraphMode.searchResult) {
        _searchResultIntroController.forward(from: 0);
      } else {
        _searchResultIntroController.stop();
        _searchResultIntroController.reset();
      }
    }

    // searchResult에서 결과가 바뀌면 인트로 다시 재생
    if (widget.mode == NodeGraphMode.searchResult &&
        oldWidget.resultNodeIds != widget.resultNodeIds) {
      _searchResultIntroController.forward(from: 0);
    }
  }

  Offset _computeStructureCenter() {
    final nodes = widget.graph.nodes;
    if (nodes.isEmpty) return Offset.zero;
    double sx = 0, sy = 0;
    for (final n in nodes) {
      sx += n.position.dx;
      sy += n.position.dy;
    }
    return Offset(sx / nodes.length, sy / nodes.length);
  }

  @override
  void dispose() {
    _camera.removeListener(_onCameraChanged);
    _camera.disposeAnim();
    _nodeDragTimer?.cancel();
    _nodeReturnController.dispose();
    _dragFadeController.dispose();
    _searchWaveController.dispose();
    _searchResultIntroController.dispose();
    _compressionAnimController.dispose();
    _minPanWarpReturnController.dispose();
    _layoutIntroController.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _stopMinPanWarpReturn() {
    if (_minPanWarpReturnController.isAnimating) {
      _minPanWarpReturnController.stop();
    }
  }

  void _animateMinPanWarpToZero({Duration? duration}) {
    if (!widget.enableMinScalePanWarp) return;
    if (_minPanWarpOffsetScene.distanceSquared <= 0.000001) {
      _minPanWarpOffsetScene = Offset.zero;
      _minPanWarpCenterScene = null;
      return;
    }
    if (duration != null) {
      _minPanWarpReturnController.duration = duration;
    }
    _minPanWarpReturnFrom = _minPanWarpOffsetScene;
    _minPanWarpReturnController
      ..stop()
      ..reset()
      ..forward();
  }

  Offset _minPanWarpOffsetForScenePos({
    required Offset scenePos,
    required double zoom,
  }) {
    if (!widget.enableMinScalePanWarp) return Offset.zero;
    final c = _minPanWarpCenterScene;
    if (c == null) return Offset.zero;
    if (_minPanWarpOffsetScene.distanceSquared <= 0.000001 &&
        !_minPanWarpReturnController.isAnimating) {
      return Offset.zero;
    }

    // 반경은 px 기준으로 받되, scene 단위로 변환해서 zoom에 따라 “느낌”이 유지되게
    final radiusScene = widget.minScalePanWarpRadiusPx / zoom;
    if (radiusScene <= 1e-3) return Offset.zero;
    final d = (scenePos - c).distance;
    final x = d / radiusScene;
    // Gaussian falloff: 손가락 근처는 많이, 멀면 빠르게 감소
    final falloff = math.exp(-0.5 * x * x);
    return _minPanWarpOffsetScene * falloff;
  }

  int? get _effectiveSelectedNodeId {
    return widget.selectedNodeId ?? _internalSelectedNodeId;
  }

  void _cancelNodeReturnAndSnapToEnd() {
    if (!_isNodeReturning && !_nodeReturnController.isAnimating) return;

    // Snap nodes to the intended final positions so the next drag starts from a stable state.
    for (final entry in _nodeReturnTo.entries) {
      final id = entry.key;
      final to = entry.value;
      final node = widget.graph.getNodeById(id);
      if (node == null) continue;
      node.position = to;
    }

    _nodeReturnController
      ..stop()
      ..reset();
    _isNodeReturning = false;
    _nodeReturnAnim = null;
    _nodeReturnFrom.clear();
    _nodeReturnTo.clear();
    _graphRevision++;
    if (mounted) setState(() {});
  }

  double _getNodeRadius(int nodeCount) {
    if (widget.nodeRadius != null) return widget.nodeRadius!;
    return NodeCountUtils.nodeRadius(nodeCount);
  }

  // ignore: unused_element - LOD fit에서 시드 대신 전체 사용으로 미사용, 추후 선택 등용 보존
  Rect _boundsForNodeIds(Set<int> ids, {double padding = 0}) {
    if (ids.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    double minX = double.infinity,
        minY = double.infinity,
        maxX = double.negativeInfinity,
        maxY = double.negativeInfinity;
    final r = _getNodeRadius(
      NodeCountUtils.effectiveCountForRendering(widget.graph.nodes.length),
    );
    for (final id in ids) {
      final n = widget.graph.getNodeById(id);
      if (n == null) continue;
      minX = math.min(minX, n.position.dx - r);
      minY = math.min(minY, n.position.dy - r);
      maxX = math.max(maxX, n.position.dx + r);
      maxY = math.max(maxY, n.position.dy + r);
    }
    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// LOD: 확대 단계별 보여줄 노드 ID (GraphProvider에서 계산)
  Set<int>? _allowedNodeIdsForZoom(double zoom) {
    final base = GraphProvider.getVisibleNodeIdsForZoom(
      graph: widget.graph,
      zoom: zoom,
      minScale: _minScale ?? 0.1,
      selectedNodeId: _effectiveSelectedNodeId,
    );
    // 검색결과: 70개 제한(LOD)과 무관하게 “결과 노드”는 반드시 보이게 포함
    final results = widget.resultNodeIds;
    if (widget.mode == NodeGraphMode.searchResult &&
        results != null &&
        results.isNotEmpty) {
      if (base == null) return null;
      return <int>{...base, ...results};
    }
    return base;
  }

  /// 라벨을 그릴 노드 목록 (LOD 시 허용 노드만 → 300개 전체 순회 방지)
  List<GraphNode> _labelsNodeList(double zoom) {
    final allowed = _allowedNodeIdsForZoom(zoom);
    final list =
        allowed != null
            ? allowed
                .map((id) => widget.graph.getNodeById(id))
                .whereType<GraphNode>()
                .toList()
            : widget.graph.nodes;
    if (widget.mode == NodeGraphMode.searchResult &&
        widget.resultNodeIds != null &&
        widget.resultNodeIds!.isNotEmpty) {
      return list.where((n) => widget.resultNodeIds!.contains(n.id)).toList();
    }
    return list;
  }

  void _maybeFitToSearchResults(Size screenSize) {
    if (widget.mode != NodeGraphMode.searchResult) return;
    // 검색 결과 시 카메라 확대/이동 없이 노드 강조만 (온보딩·일반 공통)
  }

  Offset _toScene(Offset localPosition) {
    return _camera.toScene(localPosition);
  }

  double _spreadForZoom(double zoom) {
    if (!widget.enableZoomSpacing) return 1.0;
    final minS = _minScale ?? 1.0;
    final ratio = (zoom / minS).clamp(0.1, 10.0);
    final spread = math.pow(ratio, widget.zoomSpacingExponent).toDouble();
    return spread.clamp(1.0, widget.zoomSpacingMax);
  }

  List<double> _quantizedZoomLevels() {
    final minS = _minScale ?? 0.1;
    final n = widget.graph.nodes.length;
    final z0 = minS;
    final z1 = minS * NodeCountUtils.zoom1Multiplier(n);
    final z2 = _maxPinchScale ?? (minS * NodeCountUtils.zoom2Multiplier(n));
    final useZoom1 = NodeCountUtils.hasZoom1Step(n);
    final levels = useZoom1 ? <double>[z0, z1, z2] : <double>[z0, z2];
    final sorted = List<double>.from(levels)..sort();
    final out = <double>[];
    for (final z in sorted) {
      if (out.isEmpty || (z - out.last).abs() > 1e-6) out.add(z);
    }
    return out;
  }

  int _nearestQuantizedZoomLevelIndex(double zoom) {
    final levels = _quantizedZoomLevels();
    if (levels.isEmpty) return 0;
    // “비율” 기준으로 가까운 단계 선택 (절대값보다 안정적)
    double best = double.infinity;
    var bestIdx = 0;
    for (var i = 0; i < levels.length; i++) {
      final z = levels[i];
      if (z <= 1e-6 || zoom <= 1e-6) continue;
      final d = (math.log(zoom / z)).abs();
      if (d < best) {
        best = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _triggerQuantizedZoomStep({
    required int dir,
    required Offset focalLocal,
    required Size screenSize,
  }) {
    if (_camera.isAnimating) return;
    final minS = _minScale ?? 0.1;
    final startZoom =
        _gestureStartZoom ??
        _camera.value.getMaxScaleOnAxis();
    final levels = _quantizedZoomLevels();
    final maxIdx = levels.isEmpty ? 0 : (levels.length - 1);
    final startIdx =
        _gestureStartZoomLevelIdx ?? _nearestQuantizedZoomLevelIndex(startZoom);
    final targetIdx = (startIdx + dir).clamp(0, maxIdx).toInt();
    final targetScale = levels.isEmpty ? minS : levels[targetIdx];

    // min 단계는 home 복귀
    if ((targetScale - minS).abs() < 0.0001) {
      final home =
          _homeTransform ??
          _homeTransformAtMinScale(
            screenSize: screenSize,
            sceneBounds: _graphBoundsInScene(padding: widget.outerPadding),
            minScale: minS,
          );
      _animateCameraTo(
        home,
        curve: Curves.easeInOutCubic,
        duration: const Duration(milliseconds: 560),
      );
    } else {
      _snapToScaleKeepingFocalPoint(
        targetScale: targetScale,
        screenSize: screenSize,
        focalLocal: focalLocal,
        enforceGraphBounds: false,
        curve: Curves.easeInOutCubic,
        duration: const Duration(milliseconds: 500),
      );
    }

    _skipMinReturnUntilMs = DateTime.now().millisecondsSinceEpoch + 650;
  }

  double _clampDoubleSafe(double v, double min, double max) {
    if (min.isNaN || max.isNaN || v.isNaN) return v;
    if (min > max) {
      // bounds가 화면보다 작아 range가 뒤집힐 때: 중앙으로 고정
      return (min + max) / 2.0;
    }
    return v.clamp(min, max).toDouble();
  }

  /// 어떤 줌에서도 “화면에 노드가 하나도 안 보이게” 바깥으로 빼는 것을 방지하는 클램프.
  /// - “사각형(bounds) 교차”는 노드가 모서리에만 있을 때 허점이 있어,
  ///   클러스터 대표/선택 노드(guard) 중 최소 1개가 화면 안에 들어오도록 보정한다.
  Offset _clampTranslationToKeepAnyNodeVisible({
    required Offset translation,
    required double scale,
    required Size screenSize,
  }) {
    final s = scale <= 0 ? 1.0 : scale;
    // 카메라 계산은 layout 전용. spread 사용 금지.
    final m = widget.keepVisibleMargin.clamp(0.0, 2000.0);
    final usable = Rect.fromLTWH(
      m,
      m,
      math.max(0, screenSize.width - 2 * m),
      math.max(0, screenSize.height - 2 * m),
    );
    if (usable.isEmpty) return translation;

    // 1) guard 노드들 중 하나라도 화면에 보이면 OK (layout 좌표 기준)
    final guardIds = _guardNodeIds();
    if (guardIds.isNotEmpty) {
      for (final id in guardIds) {
        final node = widget.graph.getNodeById(id);
        if (node == null) continue;
        final p = node.position;
        final screen = Offset(
          p.dx * s + translation.dx,
          p.dy * s + translation.dy,
        );
        if (usable.contains(screen)) {
          return translation;
        }
      }

      // 2) 아무 guard도 안 보이면: “가장 적게 움직여서” guard 하나를 화면 안으로 넣기
      Offset? bestDelta;
      double bestScore = double.infinity;
      for (final id in guardIds) {
        final node = widget.graph.getNodeById(id);
        if (node == null) continue;
        final p = node.position;
        final screen = Offset(
          p.dx * s + translation.dx,
          p.dy * s + translation.dy,
        );
        final dx =
            screen.dx < usable.left
                ? (usable.left - screen.dx)
                : (screen.dx > usable.right ? (usable.right - screen.dx) : 0.0);
        final dy =
            screen.dy < usable.top
                ? (usable.top - screen.dy)
                : (screen.dy > usable.bottom
                    ? (usable.bottom - screen.dy)
                    : 0.0);
        final d = Offset(dx, dy);
        final score = d.distanceSquared;
        if (score < bestScore) {
          bestScore = score;
          bestDelta = d;
        }
      }
      if (bestDelta != null && bestScore.isFinite) {
        return translation + bestDelta;
      }
    }

    // 3) fallback: bounds 교차 클램프 (layout bounds)
    final bounds = _graphBoundsInScene(padding: widget.outerPadding);
    if (bounds.isEmpty) return translation;

    // screen = scene * s + translation
    // viewportScene for “usable screen” [m..w-m]:
    // left = (m - tx)/s, right = (w-m - tx)/s
    // overlap constraint:
    // right >= bounds.left  -> tx <= (w-m) - bounds.left*s
    // left  <= bounds.right -> tx >= m - bounds.right*s
    final minTx = m - bounds.right * s;
    final maxTx = (screenSize.width - m) - bounds.left * s;
    final minTy = m - bounds.bottom * s;
    final maxTy = (screenSize.height - m) - bounds.top * s;

    return Offset(
      _clampDoubleSafe(translation.dx, minTx, maxTx),
      _clampDoubleSafe(translation.dy, minTy, maxTy),
    );
  }

  List<int> _guardNodeIds() {
    if (_cachedGuardNodeIds != null &&
        _lastGuardRevision == _graphRevision &&
        _lastGuardEdgeMode == widget.edgeRenderMode) {
      return _cachedGuardNodeIds!;
    }

    final out = <int>[];
    // 1) 선택 노드는 항상 guard에 포함
    final sel = _effectiveSelectedNodeId;
    if (sel != null) out.add(sel);

    // 2) representativeStar 모드: 클러스터 대표들을 guard로 사용 (클러스터 수가 작아 효율/일관성 좋음)
    if (widget.edgeRenderMode == EdgeRenderMode.representativeStar) {
      final byCluster = <int, List<GraphNode>>{};
      for (final n in widget.graph.nodes) {
        final cid = n.isAnchor ? n.id : 0;
        (byCluster[cid] ??= <GraphNode>[]).add(n);
      }
      for (final entry in byCluster.entries) {
        final nodes = entry.value;
        if (nodes.isEmpty) continue;
        // 중앙성(있으면) 우선, 없으면 id 정렬로 안정 선택
        nodes.sort((a, b) {
          final da = a.isAnchor ? 1 : 0;
          final db = b.isAnchor ? 1 : 0;
          final d = db.compareTo(da);
          return d != 0 ? d : a.id.compareTo(b.id);
        });
        out.add(nodes.first.id);
      }
    } else {
      final nodes = [...widget.graph.nodes];
      nodes.sort((a, b) {
        final da = (a.isAnchor) ? 1 : 0;
        final db = (b.isAnchor) ? 1 : 0;
        final d = db.compareTo(da);
        return d != 0 ? d : (a.id).compareTo(b.id);
      });
      for (final n in nodes.take(8)) {
        out.add(n.id);
      }
    }

    final uniq = <int>[];
    final seen = <int>{};
    for (final id in out) {
      if (seen.add(id)) uniq.add(id);
      if (uniq.length >= 12) break;
    }

    _cachedGuardNodeIds = uniq;
    _lastGuardRevision = _graphRevision;
    _lastGuardEdgeMode = widget.edgeRenderMode;
    return uniq;
  }

  /// 엣지 목록에서 root의 직통 이웃 (양방향)
  Set<int> _directNeighborsFromEdges(int root, Iterable<GraphEdge> edges) {
    final out = <int>{};
    for (final e in edges) {
      if (e.fromNodeId == root) out.add(e.toNodeId);
      if (e.toNodeId == root) out.add(e.fromNodeId);
    }
    return out;
  }

  /// 드래그 2-hop 계산용: 렌더링과 동일한 엣지 세트 사용 (fromNode가 anchor인 것만)
  /// → 화면에 보이는 연결만 따라오게, "연결 안 된" 노드가 따라오는 현상 방지
  Iterable<GraphEdge> _edgesForDragGroup(double zoom) {
    final graph = widget.graph;
    return graph.edges.where((e) {
      if (e.similarity < _minSimilarityForZoom(zoom)) return false;
      final from = graph.getNodeById(e.fromNodeId);
      final to = graph.getNodeById(e.toNodeId);
      return from != null && to != null && from.isAnchor;
    });
  }

  /// 그래프에 실제 존재하는 노드 ID만 남김
  Set<int> _onlyInGraph(Set<int> ids) {
    return ids.where((id) => widget.graph.getNodeById(id) != null).toSet();
  }

  void _startNodeDrag({required int rootNodeId, required Offset startScene}) {
    // 드래그 시작 시: 복귀 애니메이션이 있으면 “끝까지” 스냅 후 초기화
    _cancelNodeReturnAndSnapToEnd();
    // min 모드에서 warp를 “즉시 리셋”하면 시작 프레임에 노드가 툭 튀는 경우가 있어,
    // 드래그 중에는 워프를 고정(정지)만 하고 좌표는 유지한다.
    // (드래그 중에는 warp 업데이트 자체가 비활성화되어 안정적으로 유지됨)
    if (widget.enableMinScalePanWarp) {
      _stopMinPanWarpReturn();
    }
    _isNodeDragging = true;
    _dragFadeController.forward();
    _dragRootNodeId = rootNodeId;
    widget.onNodeDragChange?.call(rootNodeId);
    _dragStartScene = startScene;
    _dragStartPositions.clear();
    _dragWeights.clear();
    _dragStartCamera = _camera.value.clone();

    final zoom = _camera.value.getMaxScaleOnAxis();
    final edges = _edgesForDragGroup(zoom);
    final hop1 = _onlyInGraph(_directNeighborsFromEdges(rootNodeId, edges));
    final hop2 = <int>{};
    for (final id in hop1) {
      for (final n in _directNeighborsFromEdges(id, edges)) {
        if (n != rootNodeId && !hop1.contains(n)) hop2.add(n);
      }
    }
    final hop2InGraph = _onlyInGraph(hop2);

    // 2-hop이 항상 일부 포함되도록 슬롯 예약 (take(120)만 쓰면 hop1이 많을 때 2-hop 0명)
    const int maxHop1 = 85;
    const int maxHop2 = 34; // 1 + 85 + 34 = 120
    final follow = <int>[
      rootNodeId,
      ...hop1.take(maxHop1),
      ...hop2InGraph.take(maxHop2),
    ];
    for (final id in follow) {
      final node = widget.graph.getNodeById(id);
      if (node == null) continue;
      _dragStartPositions[id] = node.position;
    }

    _dragWeights[rootNodeId] = 1.0;
    for (final id in hop1) {
      _dragWeights[id] = widget.dragHop1Weight;
    }
    for (final id in hop2InGraph) {
      _dragWeights[id] = widget.dragHop2Weight;
    }
  }

  void _updateNodeDrag({
    required Offset currentScene,
    required Size worldSize,
    required Size screenSize,
  }) {
    final root = _dragRootNodeId;
    if (!_isNodeDragging || root == null) return;

    final deltaDisplay = currentScene - _dragStartScene;
    final spread = _displaySpread <= 0 ? 1.0 : _displaySpread;
    final nodeCount = widget.graph.nodes.length;
    final minDist = ForceDirectedLayout.minNodeDistance(nodeCount);
    final margin = minDist;

    for (final entry in _dragStartPositions.entries) {
      final id = entry.key;
      final startPos = entry.value;
      final w = _dragWeights[id] ?? 0.0;
      final node = widget.graph.getNodeById(id);
      if (node == null) continue;
      // display(delta)를 base 좌표로 환산해 적용 (풍선 스프레드가 있어도 손가락과 일치)
      final p = startPos + (deltaDisplay * w) / spread;

      final target = Offset(
        p.dx.clamp(margin, worldSize.width - margin),
        p.dy.clamp(margin, worldSize.height - margin),
      );

      // “자유롭고 탱탱” 느낌:
      // 루트는 바로 따라오고, 이웃은 target을 약간 늦게 따라오게(스프링처럼)
      if (id == root) {
        node.position = target;
      } else {
        final cur = node.position;
        // w가 클수록 더 빠르게 따라오게 (0.25~0.75)
        final alpha = (0.22 + 0.72 * w).clamp(0.22, 0.75);
        node.position = Offset.lerp(cur, target, alpha)!;
      }
    }
    _graphRevision++;

    // 드래그 중인 노드를 기준으로 뷰포트가 약간 이동하도록 (옵션)
    if (!widget.enableDragCameraFollow) return;
    final rootNode = widget.graph.getNodeById(root);
    if (rootNode != null) {
      // 드래그 중인 노드의 현재 scene 위치 (display spread 반영)
      final center = _structureCenter ?? _graphBoundsInScene().center;
      final spread = _displaySpread <= 0 ? 1.0 : _displaySpread;
      final nodeScenePos = center + (rootNode.position - center) * spread;

      // scene 좌표를 화면 좌표로 변환
      final matrix = _camera.value;
      final nodeScreenPos = MatrixUtils.transformPoint(matrix, nodeScenePos);

      // 화면 중앙에서의 거리
      final screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
      final offsetFromCenter = nodeScreenPos - screenCenter;
      final distanceFromCenter = offsetFromCenter.distance;

      // 화면 중앙에서 일정 거리 이상 벗어나면 카메라를 조금씩 이동
      final threshold = widget.dragCameraFollowThresholdPx;
      if (distanceFromCenter > threshold) {
        // NOTE: screen = scale * scene + translation
        // 노드가 중앙에서 오른쪽(+dx)이면 tx를 줄여야(node를 왼쪽으로) 중앙으로 옴 → 부호는 “-”
        final direction = offsetFromCenter / distanceFromCenter;
        final rawMove =
            (distanceFromCenter - threshold) * widget.dragCameraFollowStrength;
        final moveAmount = rawMove.clamp(
          0.0,
          widget.dragCameraFollowMaxDeltaPx,
        );
        final moveDelta = direction * moveAmount;

        // 현재 translation에 이동량 추가
        final currentTrans = Offset(matrix.storage[12], matrix.storage[13]);
        final newTrans = currentTrans - moveDelta;
        final zoom = matrix.getMaxScaleOnAxis();
        final clamped = _clampTranslationToKeepAnyNodeVisible(
          translation: newTrans,
          scale: zoom,
          screenSize: screenSize,
        );

        _camera.setTransform(
            Matrix4.identity()
              ..translate(clamped.dx, clamped.dy)
              ..scale(zoom));
      }
    }
  }

  void _endNodeDrag() {
    final toPositions = Map<int, Offset>.from(_dragStartPositions);
    final cameraHome = _dragStartCamera?.clone();

    _lastDragGroupForFade = _dragStartPositions.keys.toSet();
    widget.onNodeDragChange?.call(null);
    _isNodeDragging = false;
    _dragRootNodeId = null;
    _dragWeights.clear();
    _dragFadeController.reverse();

    // 선택 해제
    _internalSelectedNodeId = null;
    if (widget.onNodeSelected != null) {
      widget.onNodeSelected!(null);
    }

    // 노드 위치 “고무줄” 복귀 애니메이션
    // (이전 복귀 상태가 남아있으면 다음 번부터 안 보일 수 있으니 항상 하드 리셋)
    _nodeReturnController
      ..stop()
      ..reset();
    _nodeReturnAnim = null;
    _nodeReturnFrom.clear();
    _nodeReturnTo.clear();
    _isNodeReturning = false;

    if (toPositions.isEmpty) {
      _dragStartPositions.clear();
      _dragStartCamera = null;
      _graphRevision++;
      return;
    }

    _isNodeReturning = true;
    _nodeReturnFrom
      ..clear()
      ..addEntries(
        toPositions.keys.map((id) {
          final n = widget.graph.getNodeById(id);
          return MapEntry(id, n?.position ?? Offset.zero);
        }),
      );
    _nodeReturnTo
      ..clear()
      ..addAll(toPositions);

    _nodeReturnAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _nodeReturnController,
        curve: Curves.easeInOutCubicEmphasized,
      ),
    );
    _nodeReturnController.forward();

    // 뷰포트도 드래그 시작 위치로 부드럽게 복귀 (고무줄 느낌: 느리게)
    if (cameraHome != null) {
      _animateCameraTo(
        cameraHome,
        curve: Curves.easeInOutCubicEmphasized,
        duration: const Duration(milliseconds: 1100),
      );
    }

    _dragStartPositions.clear();
    _dragStartCamera = null;
    _graphRevision++;
  }

  void _clearSelection() {
    if (_effectiveSelectedNodeId == null && _internalSelectedNodeId == null) {
      return;
    }
    _internalSelectedNodeId = null;
    if (widget.onNodeSelected != null) {
      widget.onNodeSelected!(null);
    }
  }

  void _cancelPendingNodeDrag() {
    _nodeDragTimer?.cancel();
    _nodeDragTimer = null;
  }

  void _stopCameraAnimation() {
    _camera.stopAnimation();
  }

  Offset _clampTranslationToKeepGraphBoundsWithinScreen({
    required Offset translation,
    required double scale,
    required Size screenSize,
    required double marginPx,
  }) {
    final s = scale <= 0 ? 1.0 : scale;
    final bounds = _graphBoundsInScene(padding: widget.outerPadding);
    if (bounds.isEmpty) return translation;

    final m = marginPx.clamp(0.0, 2000.0);
    // viewportScene must stay within bounds (with margin in screen px):
    // leftScene  = -tx/s  >= bounds.left  - (m/s)  -> tx <=  m - bounds.left*s
    // rightScene = (w-tx)/s <= bounds.right + (m/s) -> tx >= (w-m) - bounds.right*s
    final minTx = (screenSize.width - m) - bounds.right * s;
    final maxTx = m - bounds.left * s;
    final minTy = (screenSize.height - m) - bounds.bottom * s;
    final maxTy = m - bounds.top * s;

    return Offset(
      _clampDoubleSafe(translation.dx, minTx, maxTx),
      _clampDoubleSafe(translation.dy, minTy, maxTy),
    );
  }

  /// 양자화: 지정 scale로 스냅 (핀치/포인터 중심 유지)
  ///
  /// - InteractiveViewer의 제스처는 focalPoint를 기준으로 스케일이 걸리는데,
  ///   스냅 시 화면 중심으로 재정렬하면 “뷰가 튄다”로 체감될 수 있어 focal을 유지한다.
  void _snapToScaleKeepingFocalPoint({
    required double targetScale,
    required Size screenSize,
    required Offset focalLocal,
    bool enforceGraphBounds = false,
    Curve? curve,
    Duration? duration,
  }) {
    if (_camera.isAnimating) return;
    final m = _camera.value;
    final zoom = m.getMaxScaleOnAxis();
    final tx = m.storage[12];
    final ty = m.storage[13];

    if ((zoom - targetScale).abs() < 0.02) return;
    final safeZoom = math.max(zoom, 0.05);

    final sceneX = (focalLocal.dx - tx) / safeZoom;
    final sceneY = (focalLocal.dy - ty) / safeZoom;
    var newTx = focalLocal.dx - sceneX * targetScale;
    var newTy = focalLocal.dy - sceneY * targetScale;

    if (enforceGraphBounds) {
      final clamped = _clampTranslationToKeepGraphBoundsWithinScreen(
        translation: Offset(newTx, newTy),
        scale: targetScale,
        screenSize: screenSize,
        marginPx: 10,
      );
      newTx = clamped.dx;
      newTy = clamped.dy;
    }

    final target =
        Matrix4.identity()
          ..translate(newTx, newTy)
          ..scale(targetScale);
    _animateCameraTo(
      target,
      curve: curve ?? Curves.easeOutCubic,
      duration: duration ?? const Duration(milliseconds: 280),
    );
  }

  void _animateCameraTo(Matrix4 target, {Curve? curve, Duration? duration}) {
    _camera.animateTo(
      target,
      curve: curve ?? Curves.easeOutCubic,
      duration: duration,
    );
  }

  Matrix4 _homeTransformAtMinScale({
    required Size screenSize,
    required Rect sceneBounds,
    required double minScale,
  }) {
    final bw = sceneBounds.width.clamp(1.0, double.infinity);
    final bh = sceneBounds.height.clamp(1.0, double.infinity);
    final tx =
        (screenSize.width - bw * minScale) / 2 - sceneBounds.left * minScale;
    final ty =
        (screenSize.height - bh * minScale) / 2 - sceneBounds.top * minScale;
    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(minScale);
  }

  EdgeInsets _maxInsets(EdgeInsets a, EdgeInsets b) {
    return EdgeInsets.fromLTRB(
      math.max(a.left, b.left),
      math.max(a.top, b.top),
      math.max(a.right, b.right),
      math.max(a.bottom, b.bottom),
    );
  }

  Offset _softWallTranslation({
    required Offset translation,
    required double scale,
    required Size screenSize,
    required Rect sceneBounds,
    required double overscrollPx,
    required double strength,
  }) {
    // screen-space bounds
    final left = translation.dx + sceneBounds.left * scale;
    final right = translation.dx + sceneBounds.right * scale;
    final top = translation.dy + sceneBounds.top * scale;
    final bottom = translation.dy + sceneBounds.bottom * scale;

    double tx = translation.dx;
    double ty = translation.dy;

    // allow bounds to extend slightly outside screen by overscrollPx,
    // but prevent it from going too far.
    final minX = -overscrollPx;
    final maxX = screenSize.width + overscrollPx;
    final minY = -overscrollPx;
    final maxY = screenSize.height + overscrollPx;

    // If graph is too far left (right edge is beyond minX), nudge right (increase tx)
    if (right < minX) {
      tx += (minX - right) * strength;
    }
    // If graph is too far right (left edge is beyond maxX), nudge left (decrease tx)
    if (left > maxX) {
      tx -= (left - maxX) * strength;
    }
    // If graph is too far up (bottom edge is beyond minY), nudge down (increase ty)
    if (bottom < minY) {
      ty += (minY - bottom) * strength;
    }
    // If graph is too far down (top edge is beyond maxY), nudge up (decrease ty)
    if (top > maxY) {
      ty -= (top - maxY) * strength;
    }

    return Offset(tx, ty);
  }

  void _scheduleNodeDragFromPointer({
    required Offset localDown,
    required Size worldSize,
    required Size screenSize,
  }) {
    if (!widget.enableNodeDrag) return;
    _cancelPendingNodeDrag();
    _nodeDragTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      if (_primaryMoved) return;
      if (_primaryDownLocal == null) return;

      final scene = _toScene(localDown);
      final tapped = _getNodeAtPosition(scene);
      if (tapped == null) return;
      // 검색 결과 모드: 결과 노드가 아닌 경우 드래그 불가
      if (widget.mode == NodeGraphMode.searchResult &&
          widget.resultNodeIds != null &&
          widget.resultNodeIds!.isNotEmpty &&
          !widget.resultNodeIds!.contains(tapped.id)) {
        return;
      }

      setState(() {
        _internalSelectedNodeId = tapped.id;
        if (widget.onNodeSelected != null) {
          widget.onNodeSelected!(tapped.id);
        }
        _startNodeDrag(rootNodeId: tapped.id, startScene: scene);
      });
    });
  }

  double _getScaleFromMatrix(Matrix4 m) => m.getMaxScaleOnAxis();

  Rect _graphBoundsInScene({double padding = 0}) {
    if (widget.graph.nodes.isEmpty) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    double minX = double.infinity,
        minY = double.infinity,
        maxX = double.negativeInfinity,
        maxY = double.negativeInfinity;

    final r = _getNodeRadius(
      NodeCountUtils.effectiveCountForRendering(widget.graph.nodes.length),
    );
    for (final n in widget.graph.nodes) {
      minX = math.min(minX, n.position.dx - r);
      minY = math.min(minY, n.position.dy - r);
      maxX = math.max(maxX, n.position.dx + r);
      maxY = math.max(maxY, n.position.dy + r);
    }
    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// 노드 0~1개일 때 fit이 과하게 줌인되지 않도록 최소 씬 크기 (줌아웃으로 시작, 동일 확대 정책)
  static const double _minSceneSizeForSingleNode = 280.0;

  Matrix4 _fitTransform({
    required Size screenSize,
    required Rect sceneBounds,
    required int nodeCount,
  }) {
    final margin = NodeCountUtils.fitMargin(nodeCount);
    final availW = (screenSize.width - margin * 2).clamp(50.0, double.infinity);
    final availH = (screenSize.height - margin * 2).clamp(
      50.0,
      double.infinity,
    );
    var bw = sceneBounds.width.clamp(1.0, double.infinity);
    var bh = sceneBounds.height.clamp(1.0, double.infinity);
    if (nodeCount <= 1) {
      bw = math.max(bw, _minSceneSizeForSingleNode);
      bh = math.max(bh, _minSceneSizeForSingleNode);
    }
    final scale = math.min(availW / bw, availH / bh).clamp(0.1, 5.0);

    final tx = (screenSize.width - bw * scale) / 2 - sceneBounds.left * scale;
    final ty = (screenSize.height - bh * scale) / 2 - sceneBounds.top * scale;
    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  void _ensureInitialLayout({
    required Size screenSize,
    required Size worldSize,
  }) {
    if (_layoutInitialized && _lastWorldSize == worldSize) return;

    _layoutInitialized = true;
    _lastWorldSize = worldSize;

    final n = widget.graph.nodes.length;
    if (!widget.useProvidedPositions) {
      ForceDirectedLayout.initialize(widget.graph, worldSize: worldSize);
      ForceDirectedLayout.relax(
        widget.graph,
        worldSize: worldSize,
        zoom: 1.0,
        iterations: n >= 150 ? null : 100, // 150개 이상이면 _getIterations(n)으로 감소
      );
      ForceDirectedLayout.applyAestheticDistribution(
        widget.graph,
        worldSize: worldSize,
      );
    }
    if (n < 200 &&
        widget.layoutIrregularity != null &&
        widget.layoutIrregularity! > 0) {
      ForceDirectedLayout.addPositionJitter(
        widget.graph,
        worldSize,
        amount: widget.layoutIrregularity!,
      );
    }
    _graphRevision++;
    _structureCenter = _computeStructureCenter();

    final useLod = n >= NodeCountUtils.lodThreshold;
    final bounds =
        useLod
            ? _boundsForNodeIds(
              GraphProvider.getSeedNodeIdsForFit(
                graph: widget.graph,
                maxNodes: NodeCountUtils.lodThreshold,
                selectedNodeId: _effectiveSelectedNodeId,
              ),
              padding: widget.outerPadding,
            )
            : _graphBoundsInScene(padding: widget.outerPadding);

    final fit = _fitTransform(
      screenSize: screenSize,
      sceneBounds: bounds,
      nodeCount: n,
    );
    _camera.setTransform(fit);
    _minScale = widget.minScale ?? _getScaleFromMatrix(fit);
    _maxPinchScale = _computeMaxPinchScale(n);
    _homeTransform = fit.clone();
    _lastScreenSizeForFit = screenSize;

    // 노드 많을 때는 인트로 스킵 (1초 동안 매 프레임 재계산 방지)
    if (n <= 120) {
      _layoutIntroController.forward(from: 0);
    } else {
      _layoutIntroController.value = 1.0;
    }
  }

  /// 확대 1단계(middle1) 근처인지. 노드 수에 따른 배율 사용.
  bool _isInFirstZoomStep() {
    final z = _camera.value.getMaxScaleOnAxis();
    final m = _minScale ?? 0.1;
    final n = widget.graph.nodes.length;
    final m1 = m * NodeCountUtils.zoom1Multiplier(n);
    return z >= m1 * 0.9 && z <= m1 * 1.15;
  }

  double _computeMaxPinchScale(int nodeCount) {
    final minS = _minScale ?? 0.1;
    return minS * NodeCountUtils.zoom2Multiplier(nodeCount);
  }

  /// 확대 핀치 시 스냅: 한 단계씩만 진행 (건너뛰지 않음)
  // (removed) _snapTargetForPinchIn: 핀치 스냅은 _quantizedZoomLevels 기반으로 완전 양자화 처리

  /// 화면 크기만 바뀌었을 때(키보드 등): 노드 재배치 없이 fit만 다시 계산
  void _refitToViewport(Size screenSize) {
    if (!_layoutInitialized || widget.graph.nodes.isEmpty) return;
    if (_lastScreenSizeForFit == screenSize) return;
    _lastScreenSizeForFit = screenSize;
    final n = widget.graph.nodes.length;
    final useLod = n >= NodeCountUtils.lodThreshold;
    final bounds =
        useLod
            ? _boundsForNodeIds(
              GraphProvider.getSeedNodeIdsForFit(
                graph: widget.graph,
                maxNodes: NodeCountUtils.lodThreshold,
                selectedNodeId: _effectiveSelectedNodeId,
              ),
              padding: widget.outerPadding,
            )
            : _graphBoundsInScene(padding: widget.outerPadding);
    final fit = _fitTransform(
      screenSize: screenSize,
      sceneBounds: bounds,
      nodeCount: n,
    );
    _camera.setTransform(fit);
    _minScale = widget.minScale ?? _getScaleFromMatrix(fit);
    _maxPinchScale = _computeMaxPinchScale(n);
    // 화면 크기가 바뀌었는데 home(초기) 뷰가 옛 스크린 기준이면,
    // 축소/복귀 시 “이상한 위치로 튐”이 발생할 수 있어 함께 갱신한다.
    _homeTransform = fit.clone();
  }

  /// 키보드 등으로 화면이 축소되었을 때 0~1 (1=정상)
  double _keyboardCompressionFactor(Size screenSize) {
    if (_maxScreenHeight <= 0) return 1.0;
    if (screenSize.height >= _maxScreenHeight - 10) return 1.0;
    return (screenSize.height / _maxScreenHeight).clamp(0.5, 1.0);
  }

  int _edgeCapForZoom(double zoom, int totalEdges) {
    if (widget.maxEdges != null) return widget.maxEdges!;
    if (totalEdges <= 0) return 0;
    return math.min(totalEdges, 2500);
  }

  double _minSimilarityForZoom(double zoom) {
    return widget.minEdgeSimilarity ?? 0.55;
  }

  void _onNodeTap(int nodeId, {required Size screenSize}) {
    final n = widget.graph.nodes.length;
    final zoomNow = _camera.value.getMaxScaleOnAxis();
    final minS = _minScale ?? 0.1;
    final maxPinch = _maxPinchScale ?? minS * NodeCountUtils.zoom2Multiplier(n);

    final atMinScale = zoomNow <= minS * 1.15;
    final atZoom2OrMore = zoomNow >= maxPinch * 0.9;

    // 이미 확대 2 이상이면 탭 → 글 보기
    if (atZoom2OrMore) {
      setState(() => _internalSelectedNodeId = nodeId);
      if (widget.onNodeSelected != null) widget.onNodeSelected!(nodeId);
      if (widget.onNavigateToPost != null) {
        widget.onNavigateToPost!(nodeId);
      } else if (widget.onNodeTap != null) {
        widget.onNodeTap!(nodeId);
      }
      return;
    }

    // 최대 축소에서만 노드 탭 → 확대 2로 진입 (해당 노드 중심)
    if (atMinScale) {
      setState(() => _internalSelectedNodeId = nodeId);
      if (widget.onNodeSelected != null) widget.onNodeSelected!(nodeId);
      if (widget.onNodeTap != null) widget.onNodeTap!(nodeId);
      if (widget.enableMinScalePanWarp) {
        _animateMinPanWarpToZero(duration: const Duration(milliseconds: 180));
      }
      _animateToZoom2(nodeId, screenSize: screenSize);
      return;
    }

    // 그 외 줌 구간: 탭 → 선택 + 글 보기
    setState(() => _internalSelectedNodeId = nodeId);
    if (widget.onNodeSelected != null) widget.onNodeSelected!(nodeId);
    if (widget.onNavigateToPost != null) {
      widget.onNavigateToPost!(nodeId);
    } else if (widget.onNodeTap != null) {
      widget.onNodeTap!(nodeId);
    }
  }

  /// 최대 축소에서 노드 탭 시 확대 2(zoom2)로 부드럽게 이동
  void _animateToZoom2(int nodeId, {required Size screenSize}) {
    final node = widget.graph.getNodeById(nodeId);
    if (node == null) return;

    final minS = _minScale ?? 0.1;
    final n = widget.graph.nodes.length;
    final finalScale =
        _maxPinchScale ?? minS * NodeCountUtils.zoom2Multiplier(n);

    // 카메라 계산은 layout 전용. spread는 렌더링 전용이므로 여기서 사용하지 않음.
    // → scale + translate만으로 안정적으로 “노드(layout) 중심” 맞춤.
    final nodeLayoutPos = node.position;

    // 노드 layout 위치를 화면 중앙에 오도록 translation 계산
    var targetTx = screenSize.width / 2 - nodeLayoutPos.dx * finalScale;
    var targetTy = screenSize.height / 2 - nodeLayoutPos.dy * finalScale;

    // 끝쪽 노드를 프레지했을 때 화면 밖으로 “잘리는” 문제 방지:
    // - 무조건 중앙 정렬을 고집하지 않고, 노드 원이 화면 안에 들어오도록 screen-space로 보정
    final nodeRadius = _getNodeRadius(
      NodeCountUtils.effectiveCountForRendering(widget.graph.nodes.length),
    );
    final keepMargin =
        widget.preziKeepOnScreenMarginPx + nodeRadius * 1.2; // 라벨/스트로크 여유
    final nodeScreenX = nodeLayoutPos.dx * finalScale + targetTx;
    final nodeScreenY = nodeLayoutPos.dy * finalScale + targetTy;
    if (nodeScreenX < keepMargin) {
      targetTx += (keepMargin - nodeScreenX);
    } else if (nodeScreenX > screenSize.width - keepMargin) {
      targetTx -= (nodeScreenX - (screenSize.width - keepMargin));
    }
    if (nodeScreenY < keepMargin) {
      targetTy += (keepMargin - nodeScreenY);
    } else if (nodeScreenY > screenSize.height - keepMargin) {
      targetTy -= (nodeScreenY - (screenSize.height - keepMargin));
    }

    final targetMatrix =
        Matrix4.identity()
          ..translate(targetTx, targetTy)
          ..scale(finalScale);

    // 프레지 스타일: 매우 부드러운 커스텀 커브 (빨려들어가는 느낌), 진입 더 느리게
    _animateCameraTo(
      targetMatrix,
      curve: _preziCurve,
      duration: const Duration(milliseconds: 1200),
    );
  }

  /// 프레지 스타일 커스텀 커브: 매우 부드러운 가속/감속 (빨려들어가는 느낌)
  /// Cubic 베지어 곡선으로 자연스러운 움직임 구현
  static final Curve _preziCurve = Cubic(
    0.16,
    1.0,
    0.3,
    1.0,
  ); // 매우 부드러운 ease-out (빨려들어가는 느낌)

  GraphNode? _getNodeAtPosition(Offset position) {
    final nodeRadius = _getNodeRadius(
      NodeCountUtils.effectiveCountForRendering(widget.graph.nodes.length),
    );
    final nodesToTest =
        (widget.mode == NodeGraphMode.searchResult &&
                widget.resultNodeIds != null &&
                widget.resultNodeIds!.isNotEmpty)
            ? widget.graph.nodes
                .where((n) => widget.resultNodeIds!.contains(n.id))
                .toList()
            : widget.graph.nodes;
    for (final node in nodesToTest) {
      final p = _displayPos[node.id] ?? node.position;
      final distance = (position - p).distance;
      if (distance <= nodeRadius * 2) {
        return node;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.isDark ?? Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        widget.primaryColor ?? Theme.of(context).colorScheme.primary;

    final lineColor =
        widget.lineColor ??
        (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);

    return ColoredBox(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
          final isOnboarding = widget.mode == NodeGraphMode.onboarding;
          _maybeFitToSearchResults(screenSize);
          // panning boundary:
          // - 제스처 중 boundaryMargin을 동적으로 바꾸면 InteractiveViewer 내부 클램프가 갑자기 달라져
          //   “확대/축소 중 뷰가 튄다”가 발생할 수 있음.
          // - 따라서 boundaryMargin은 **줌과 무관하게** 고정하고,
          //   빈 공간 억제/가시성 보정은 스냅/릴리즈 시점에 별도 클램프로 처리한다.
          final effectiveBoundaryMargin = _maxInsets(
            widget.boundaryMargin,
            // zoomSpacing(spread)로 노드가 시각적으로 더 퍼질 수 있으므로,
            // 확대 상태에서도 끝까지 패닝 가능하도록 여유를 크게 잡는다. (줌 중 동적 변경 금지)
            EdgeInsets.all(math.max(screenSize.width, screenSize.height) * 3.0),
          );

          final baseWorldSize = ForceDirectedLayout.suggestWorldSize(
            screenSize: screenSize,
            nodeCount: widget.graph.nodes.length,
          );
          // 이미 레이아웃 완료 시: worldSize 유지, 화면 크기 변경(키보드 등)은 fit만 갱신
          final worldSize =
              _layoutInitialized
                  ? _lastWorldSize ?? baseWorldSize
                  : baseWorldSize;

          if (screenSize.width > 0 && screenSize.height > 0) {
            if (screenSize.height > _maxScreenHeight) {
              _maxScreenHeight = screenSize.height;
            }
            if (!_layoutInitialized) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _ensureInitialLayout(
                    screenSize: screenSize,
                    worldSize: worldSize,
                  );
                });
              });
            } else if (_lastScreenSizeForFit != null) {
              // 아주 미세한 흔들림(소수점/인셋)로 인해 refit이 “매 프레임” 돌면 카메라가 튐.
              // 제스처/드래그 중에는 refit을 미루고, 변화량이 의미 있을 때만 수행.
              final last = _lastScreenSizeForFit!;
              final dw = (last.width - screenSize.width).abs();
              final dh = (last.height - screenSize.height).abs();
              final significant = dw > 0.5 || dh > 0.5;
              if (significant && !_isViewerInteracting && !_isNodeDragging) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _refitToViewport(screenSize));
                });
              }
            }
          }

          final targetCompression = _keyboardCompressionFactor(screenSize);
          final isDecompress = targetCompression > _displayedCompressionFactor;
          if (!_compressionAnimController.isAnimating) {
            if ((targetCompression - _displayedCompressionFactor).abs() >
                0.01) {
              _compressionAnimFrom = _displayedCompressionFactor;
              _compressionAnimTo = targetCompression;
              _compressionAnimController.duration =
                  isDecompress
                      ? const Duration(milliseconds: 550)
                      : const Duration(milliseconds: 180);
              _compressionAnimController.forward(from: 0);
            }
          }
          double keyboardCompression;
          if (_compressionAnimController.isAnimating) {
            keyboardCompression =
                _compressionAnimFrom +
                (_compressionAnimTo - _compressionAnimFrom) *
                    Curves.easeOutCubic.transform(
                      _compressionAnimController.value,
                    );
          } else {
            _displayedCompressionFactor = targetCompression;
            keyboardCompression = targetCompression;
          }

          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              _activePointers.add(e.pointer);
              _pointerLocalPos[e.pointer] = e.localPosition;

              // 2손가락 핀치 시작: “트리거만” 감지 (실제 스케일링은 금지)
              if (_activePointers.length == 2) {
                _pinchSnapHandledInPointerUp = false;
                final ids = _activePointers.toList();
                final p0 = _pointerLocalPos[ids[0]];
                final p1 = _pointerLocalPos[ids[1]];
                if (p0 != null && p1 != null) {
                  _pinchGestureActive = true;
                  _pinchStartDistance = (p0 - p1).distance;
                  _pinchTriggered = false;
                  _pinchDirection = 0;
                  _pinchFocalLocal = (p0 + p1) / 2;
                  _lastGestureWasPinch = true; // 다른 release 로직과 충돌 방지
                  _gestureStartZoom =
                      _camera.value.getMaxScaleOnAxis();
                  _gestureStartZoomLevelIdx = _nearestQuantizedZoomLevelIndex(
                    _gestureStartZoom ?? (_minScale ?? 0.1),
                  );
                }
              }

              if (_activePointers.length >= 2) {
                _stopCameraAnimation();
                _cancelNodeReturnAndSnapToEnd();
                _cancelPendingNodeDrag();
                _primaryPointer = null;
                _primaryDownLocal = null;
                _primaryMoved = false;
                _lastPanLocal = null;
                _minPanTargetTranslation = null;
                // 드래그 후 핀치 시 warp 즉시 리셋하면 노드가 튐 → 부드럽게 애니메이션으로 0으로
                if (widget.enableMinScalePanWarp &&
                    _minPanWarpOffsetScene.distanceSquared > 0.000001) {
                  _animateMinPanWarpToZero(
                    duration: const Duration(milliseconds: 200),
                  );
                } else {
                  _minPanWarpCenterScene = null;
                  _minPanWarpOffsetScene = Offset.zero;
                }
                // pinch trigger-only: 스케일링은 금지, 핀치 상태만 유지
                setState(() {});
                return;
              }

              _stopCameraAnimation();
              _cancelNodeReturnAndSnapToEnd();
              _selectionClearedByDrag = false;
              _lastGestureWasPinch = false;
              _gestureStartZoom =
                  _camera.value.getMaxScaleOnAxis();
              _preziDragConsumed = false;
              if (!isOnboarding) {
                _stopMinPanWarpReturn();
                _lastPanLocal = e.localPosition;
                final m = _camera.value;
                _minPanTargetTranslation = Offset(m.storage[12], m.storage[13]);
                _minPanWarpCenterScene = _toScene(e.localPosition);
              } else {
                _lastPanLocal = null;
                _minPanTargetTranslation = null;
                _minPanWarpCenterScene = null;
                _minPanWarpOffsetScene = Offset.zero;
              }

              _primaryPointer = e.pointer;
              _primaryDownLocal = e.localPosition;
              _primaryMoved = false;

              _scheduleNodeDragFromPointer(
                localDown: e.localPosition,
                worldSize: worldSize,
                screenSize: screenSize,
              );
            },
            onPointerMove: (e) {
              if (_activePointers.length >= 2) {
                // pinch trigger-only: 두 손가락 거리 변화로 “줌인/줌아웃” 방향만 감지
                _pointerLocalPos[e.pointer] = e.localPosition;
                if (_pinchGestureActive && _activePointers.length == 2) {
                  final ids = _activePointers.toList();
                  final p0 = _pointerLocalPos[ids[0]];
                  final p1 = _pointerLocalPos[ids[1]];
                  final d0 = _pinchStartDistance;
                  if (p0 != null && p1 != null && d0 != null && d0 > 0) {
                    final d = (p0 - p1).distance;
                    final ratio = d / d0;
                    _pinchFocalLocal = (p0 + p1) / 2;
                    if (!_pinchTriggered &&
                        (ratio - 1.0).abs() >= _pinchTriggerRatioThreshold) {
                      _pinchTriggered = true;
                      _pinchDirection = ratio < 1.0 ? -1 : 1;
                    }
                  }
                }
                return;
              }
              if (_primaryPointer != e.pointer) return;
              var down = _primaryDownLocal;
              if (down == null) {
                _primaryDownLocal = e.localPosition;
                return;
              }

              if ((e.localPosition - down).distance > _dragSlop) {
                _primaryMoved = true;
                _cancelPendingNodeDrag();

                // 조금이라도 드래그가 “확정”되면 선택 해제
                if (!isOnboarding && !_selectionClearedByDrag) {
                  // 프레지 영역에서는 selection을 지우면 panEnabled가 다시 켜져 화면이 움직일 수 있음.
                  // 프레지 드래그는 “축소만 하고 패닝 금지”가 목표라 여기서는 선택을 유지.
                  final zoom =
                      _camera.value.getMaxScaleOnAxis();
                  final minS = _minScale ?? 0.1;
                  final maxPinch =
                      _maxPinchScale ??
                      minS *
                          NodeCountUtils.zoom2Multiplier(
                            widget.graph.nodes.length,
                          );
                  final inPreziZone =
                      zoom > maxPinch * 1.05 ||
                      (_effectiveSelectedNodeId != null &&
                          zoom >= widget.preziPanThresholdScale);
                  if (inPreziZone) {
                    // no-op
                  } else {
                    _selectionClearedByDrag = true;
                    setState(_clearSelection);
                  }
                }
              }

              // min 모드에서 “부드럽고 고급스러운” pan:
              // - 타겟 translation 누적
              // - 현재 translation이 타겟을 low-pass로 따라감
              // - soft wall로 끝쪽에서 자연스러운 저항
              if (!isOnboarding && !_isNodeDragging) {
                final minS = _minScale ?? 0.1;
                final zoom =
                    _camera.value.getMaxScaleOnAxis();
                final isNearMin = zoom <= minS * 1.15;
                final middle1 =
                    minS *
                    NodeCountUtils.zoom1Multiplier(widget.graph.nodes.length);
                final isFirstZoomStep =
                    zoom >= middle1 * 0.9 && zoom <= middle1 * 1.15;
                if (isNearMin) {
                  final last = _lastPanLocal;
                  if (last != null && _primaryMoved) {
                    var delta = e.localPosition - last; // screen px
                    final dist = delta.distance;
                    if (dist > widget.minScalePanMaxInputDeltaPx && dist > 0) {
                      delta = delta / dist * widget.minScalePanMaxInputDeltaPx;
                    }

                    final m = _camera.value;
                    final trans = Offset(m.storage[12], m.storage[13]);

                    // 0) finger-centric “warp” (min 모드에서만)
                    if (widget.enableMinScalePanWarp) {
                      _stopMinPanWarpReturn();
                      final fingerScene = _toScene(e.localPosition);
                      final smooth = widget.minScalePanWarpCenterSmoothing
                          .clamp(0.0, 1.0);
                      _minPanWarpCenterScene = Offset.lerp(
                        _minPanWarpCenterScene ?? fingerScene,
                        fingerScene,
                        smooth,
                      );

                      final zoomSafe = zoom <= 0 ? 1.0 : zoom;
                      final deltaScene = delta / zoomSafe;
                      final maxScene =
                          widget.minScalePanWarpMaxOffsetPx / zoomSafe;
                      var targetWarp =
                          _minPanWarpOffsetScene +
                          deltaScene * widget.minScalePanWarpStrength;
                      final mag = targetWarp.distance;
                      if (mag > maxScene && mag > 0) {
                        targetWarp = targetWarp / mag * maxScene;
                      }
                      // 살짝 low-pass로 “탱탱”하게
                      _minPanWarpOffsetScene =
                          Offset.lerp(
                            _minPanWarpOffsetScene,
                            targetWarp,
                            0.45,
                          )!;
                    }

                    // 1) target 누적
                    final target =
                        (_minPanTargetTranslation ?? trans) +
                        delta * widget.minScalePanSensitivity;
                    _minPanTargetTranslation = target;

                    // 2) low-pass follow
                    final smoothed =
                        Offset.lerp(
                          trans,
                          target,
                          widget.minScalePanSmoothing.clamp(0.0, 1.0),
                        )!;

                    // 3) soft wall
                    final bounds = _graphBoundsInScene(
                      padding: widget.outerPadding,
                    );
                    final limited = _softWallTranslation(
                      translation: smoothed,
                      scale: zoom,
                      screenSize: screenSize,
                      sceneBounds: bounds,
                      overscrollPx: widget.minScaleSoftWallOverscrollPx,
                      strength: widget.minScaleSoftWallStrength.clamp(0.0, 1.0),
                    );
                    // 드래그 중 강제 클램프(특히 guard-node 기반)는 “툭툭” 점프를 만들 수 있어 금지.
                    // 끝쪽 제어는 soft wall(연속 보정)만 사용하고, 필요하면 release 시점에만 보정한다.
                    _minPanTargetTranslation = limited;

                    _camera.setTransform(
                        Matrix4.identity()
                          ..translate(limited.dx, limited.dy)
                          ..scale(zoom));
                  }
                  _lastPanLocal = e.localPosition;
                } else if (isFirstZoomStep) {
                  // 확대 1단계: 파도 없이 드래그 감도만 (firstZoomStepPanSensitivity)
                  final last = _lastPanLocal;
                  if (last != null && _primaryMoved) {
                    final delta = e.localPosition - last;
                    final m = _camera.value;
                    final trans = Offset(m.storage[12], m.storage[13]);
                    final target =
                        (_minPanTargetTranslation ?? trans) +
                        delta * widget.firstZoomStepPanSensitivity;
                    _minPanTargetTranslation = target;
                    final smoothed =
                        Offset.lerp(trans, target, 0.28.clamp(0.0, 1.0))!;
                    _camera.setTransform(
                        Matrix4.identity()
                          ..translate(smoothed.dx, smoothed.dy)
                          ..scale(zoom));
                  }
                  _lastPanLocal = e.localPosition;
                } else {
                  _lastPanLocal = e.localPosition;
                  _minPanTargetTranslation = null;
                }
              }

              if (_isNodeDragging) {
                final scene = _toScene(e.localPosition);
                setState(() {
                  _updateNodeDrag(
                    currentScene: scene,
                    worldSize: worldSize,
                    screenSize: screenSize,
                  );
                });
              }
            },
            onPointerUp: (e) {
              final wasMulti = _activePointers.length >= 2;
              _activePointers.remove(e.pointer);
              _pointerLocalPos.remove(e.pointer);

              // pinch 종료: 트리거가 있었다면 여기서만 자동 줌 실행
              if (wasMulti &&
                  _pinchGestureActive &&
                  _activePointers.length < 2) {
                final dir = _pinchDirection;
                final focal = _pinchFocalLocal ?? e.localPosition;
                if (_pinchTriggered && dir != 0) {
                  _triggerQuantizedZoomStep(
                    dir: dir,
                    focalLocal: focal,
                    screenSize: screenSize,
                  );
                  _pinchSnapHandledInPointerUp = true;
                }
                _pinchGestureActive = false;
                _pinchStartDistance = null;
                _pinchTriggered = false;
                _pinchDirection = 0;
                _pinchFocalLocal = null;
                _lastGestureWasPinch = false;
                _gestureStartZoom = null;
                _gestureStartZoomLevelIdx = null;
              }

              if (wasMulti && _activePointers.length == 1) {
                _primaryPointer = _activePointers.single;
                _primaryDownLocal = null;
                _primaryMoved = false;
                setState(() {});
                return;
              }
              if (_primaryPointer != e.pointer) return;
              _cancelPendingNodeDrag();

              if (_isNodeDragging) {
                setState(() {
                  _endNodeDrag();
                });
              } else {
                final down = _primaryDownLocal;
                // 핀치(2손가락) 중이었으면 노드 클릭으로 처리하지 않음
                if (!isOnboarding &&
                    down != null &&
                    !_primaryMoved &&
                    !wasMulti) {
                  final scene = _toScene(down);
                  final tapped = _getNodeAtPosition(scene);
                  if (tapped != null) {
                    _onNodeTap(tapped.id, screenSize: screenSize);
                  }
                }
              }

              // min(최대 축소) 모드에서는 손을 떼면 부드럽게 중앙(home)으로 복귀
              if (!isOnboarding &&
                  !_isNodeDragging &&
                  !_isNodeReturning &&
                  widget.enableMinScaleReturnOnRelease) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now < _skipMinReturnUntilMs || _lastGestureWasPinch) {
                  // 핀치 스냅/축소 직후 충돌 방지
                } else {
                  final m = _camera.value;
                  final zoom = m.getMaxScaleOnAxis();
                  final minS = _minScale ?? 0.1;
                  final isNearMin = zoom <= minS * 1.15;
                  if (isNearMin && _primaryMoved) {
                    // 초기 fit과 동일한 기준으로 복귀 (_homeTransform 우선 → LOD 시 중앙 보정 일치)
                    final home =
                        _homeTransform ??
                        _homeTransformAtMinScale(
                          screenSize: screenSize,
                          sceneBounds: _graphBoundsInScene(
                            padding: widget.outerPadding,
                          ),
                          minScale: minS,
                        );
                    _animateCameraTo(
                      home,
                      curve: Curves.easeInOutCubicEmphasized,
                      duration: const Duration(milliseconds: 1200),
                    );
                  }
                }
              }

              // min 모드에서 pan-warp는 손을 떼면 풀림 (즉시 리셋은 “덜컥” 유발 → 짧은 애니메이션)
              if (!isOnboarding &&
                  !_isNodeDragging &&
                  widget.enableMinScalePanWarp) {
                _animateMinPanWarpToZero(
                  duration: const Duration(milliseconds: 180),
                );
              }

              _primaryPointer = null;
              _primaryDownLocal = null;
              _primaryMoved = false;
              _lastPanLocal = null;
              _minPanTargetTranslation = null;
              _gestureStartZoom = null;
              _preziDragConsumed = false;
            },
            onPointerCancel: (e) {
              final wasMulti = _activePointers.length >= 2;
              _activePointers.remove(e.pointer);
              _pointerLocalPos.remove(e.pointer);

              if (wasMulti &&
                  _pinchGestureActive &&
                  _activePointers.length < 2) {
                // cancel도 pinch 종료로 취급 (트리거 시 자동 줌)
                final dir = _pinchDirection;
                final focal = _pinchFocalLocal ?? e.localPosition;
                if (_pinchTriggered && dir != 0) {
                  _triggerQuantizedZoomStep(
                    dir: dir,
                    focalLocal: focal,
                    screenSize: screenSize,
                  );
                  _pinchSnapHandledInPointerUp = true;
                }
                _pinchGestureActive = false;
                _pinchStartDistance = null;
                _pinchTriggered = false;
                _pinchDirection = 0;
                _pinchFocalLocal = null;
                _lastGestureWasPinch = false;
                _gestureStartZoom = null;
                _gestureStartZoomLevelIdx = null;
              }

              if (wasMulti && _activePointers.length == 1) {
                _primaryPointer = _activePointers.single;
                _primaryDownLocal = null;
                _primaryMoved = false;
                setState(() {});
                return;
              }
              if (_primaryPointer != e.pointer) return;
              _cancelPendingNodeDrag();
              if (_isNodeDragging) {
                setState(() {
                  _endNodeDrag();
                });
              }
              if (!isOnboarding && widget.enableMinScalePanWarp) {
                _animateMinPanWarpToZero(
                  duration: const Duration(milliseconds: 180),
                );
              }
              _primaryPointer = null;
              _primaryDownLocal = null;
              _primaryMoved = false;
              _lastPanLocal = null;
              _minPanTargetTranslation = null;
              _gestureStartZoom = null;
              _preziDragConsumed = false;
            },
            child: ListenableBuilder(
              listenable: _camera,
              builder: (context, _) {
                final zoom = _camera.scale;
                final matrix = _camera.value;
                    // 라벨: 초기 레이아웃 완료 후 + 임계값 넘으면 "켜짐" 판단 → AnimatedOpacity로 고정 시간 내 페이드 인 (확대 속도 무관)
                    // - labelZoomThreshold >= 1: minScale 대비 배율 (1.4 = 최소축소의 1.4배에서 라벨 표시)
                    // - labelZoomThreshold < 1: 절대 zoom 값 (하위 호환)
                    final minSForLabel = _minScale ?? 0.1;
                    final labelThreshold =
                        widget.labelZoomThreshold >= 1
                            ? (minSForLabel * widget.labelZoomThreshold).clamp(
                              0.12,
                              0.95,
                            )
                            : widget.labelZoomThreshold;
                    // 노드 1개일 때는 라벨 항상 표시
                    final labelOn =
                        _layoutInitialized &&
                        widget.showLabels &&
                        (widget.graph.nodes.length == 1 ||
                            zoom > labelThreshold);

                    // zoom에 따른 “풍선 팽창” 렌더링 좌표 계산 (레이아웃 자체는 변하지 않음)
                    // spread는 항상 현재 zoom 기반. 고정 시 focal translation 보정과 이중 보정되어 튐 발생
                    final spread = _spreadForZoom(zoom);
                    final center =
                        _structureCenter ?? _graphBoundsInScene().center;
                    _displaySpread = spread;
                    final minS = _minScale ?? 0.1;
                    final isAtMinScale = zoom <= minS * 1.1;
                    if (widget.onIsAtMinScale != null &&
                        _lastReportedIsAtMinScale != isAtMinScale) {
                      _lastReportedIsAtMinScale = isAtMinScale;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.onIsAtMinScale?.call(isAtMinScale);
                      });
                    }
                    final isNearMin = zoom <= minS * 1.15;
                    final warpActive =
                        widget.enableMinScalePanWarp &&
                        isNearMin &&
                        (_minPanWarpOffsetScene.distanceSquared > 0.000001 ||
                            _minPanWarpReturnController.isAnimating);
                    // 드래그/팬 중 버벅임 줄이기: spread/revision이 변할 때만 재계산
                    final layoutIntroActive =
                        _layoutIntroController.value < 1.0;
                    final shouldRecompute =
                        _camera.isAnimating ||
                        layoutIntroActive ||
                        (spread - _lastDisplaySpread).abs() > 0.002 ||
                        _lastDisplayRevision != _graphRevision ||
                        warpActive ||
                        (_lastZoom - zoom).abs() > 0.001;
                    if (shouldRecompute) {
                      _lastDisplaySpread = spread;
                      _lastDisplayRevision = _graphRevision;
                      _lastZoom = zoom;
                      final introT = _layoutIntroController.value.clamp(
                        0.0,
                        1.0,
                      );
                      final nodes = widget.graph.nodes;
                      // LOD: 노드 수 많을 때는 보이는 노드만 좌표 계산 (버벅임 방지)
                      final allowedIds =
                          nodes.length >= NodeCountUtils.lodThreshold
                              ? _allowedNodeIdsForZoom(zoom)
                              : null;
                      final nodesToCompute =
                          allowedIds != null
                              ? nodes
                                  .where((n) => allowedIds.contains(n.id))
                                  .toList()
                              : nodes;
                      final maxDist =
                          nodesToCompute.isEmpty
                              ? 1.0
                              : nodesToCompute
                                  .map((n) => (n.position - center).distance)
                                  .reduce(math.max);
                      _displayPos
                        ..clear()
                        ..addEntries(
                          nodesToCompute.map((n) {
                            final toCenter = n.position - center;
                            final distNorm =
                                maxDist > 1e-6
                                    ? toCenter.distance / maxDist
                                    : 0.0;
                            final waveDelay = 0.22 * distNorm;
                            final phaseOffset =
                                0.08 * (2 * ((n.id * 0.618033) % 1) - 1);
                            final effectiveT = (introT -
                                    waveDelay +
                                    phaseOffset)
                                .clamp(0.0, 1.0);
                            var p =
                                center +
                                toCenter *
                                    spread *
                                    Curves.easeOutCubic.transform(effectiveT);
                            if (warpActive) {
                              p =
                                  p +
                                  _minPanWarpOffsetForScenePos(
                                    scenePos: p,
                                    zoom: zoom <= 0 ? 1.0 : zoom,
                                  );
                            }
                            return MapEntry(n.id, p);
                          }),
                        );
                    }

                    // scene 좌표계에서 화면에 보이는 영역 (컬링용)
                    final tx = matrix.storage[12];
                    final ty = matrix.storage[13];
                    final viewportRect = Rect.fromLTRB(
                      -tx / zoom,
                      -ty / zoom,
                      (screenSize.width - tx) / zoom,
                      (screenSize.height - ty) / zoom,
                    );

                    // 중앙 영역만 라벨을 보이게: viewport 기준으로 inner rect를 만들고,
                    // inner 밖에서는 edge 쪽으로 갈수록 부드럽게 페이드 아웃.
                    // 확대1(middle1)에서는 진짜 가운데 몇 개만 (0.38), 확대될수록 넓게 (0.35)
                    final minSForCenter = _minScale ?? 0.1;
                    final middle1 =
                        minSForCenter *
                        NodeCountUtils.zoom1Multiplier(
                          widget.graph.nodes.length,
                        );
                    final centerInnerFrac =
                        zoom < middle1 * 1.1
                            ? 0.38
                            : 0.35; // 확대1: 가운데만 타이트, 확대2+: 넓게
                    final innerRect = Rect.fromLTRB(
                      viewportRect.left + viewportRect.width * centerInnerFrac,
                      viewportRect.top + viewportRect.height * centerInnerFrac,
                      viewportRect.right - viewportRect.width * centerInnerFrac,
                      viewportRect.bottom -
                          viewportRect.height * centerInnerFrac,
                    );
                    final fadeBand = math
                        .min(
                          viewportRect.width * centerInnerFrac,
                          viewportRect.height * centerInnerFrac,
                        )
                        .clamp(1.0, double.infinity);
                    double centerAlpha(Offset p) {
                      if (innerRect.contains(p)) return 1.0;
                      if (!viewportRect.contains(p)) return 0.0;
                      final dx =
                          p.dx < innerRect.left
                              ? innerRect.left - p.dx
                              : (p.dx > innerRect.right
                                  ? p.dx - innerRect.right
                                  : 0.0);
                      final dy =
                          p.dy < innerRect.top
                              ? innerRect.top - p.dy
                              : (p.dy > innerRect.bottom
                                  ? p.dy - innerRect.bottom
                                  : 0.0);
                      final d = math.max(dx, dy);
                      return (1.0 - (d / fadeBand)).clamp(0.0, 1.0);
                    }

                    return Transform(
                      transform: _camera.value,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: worldSize.width,
                        height: worldSize.height,
                        child: ColoredBox(
                          color: Colors.transparent,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: GraphPainter(
                              graph: widget.graph,
                              revision: _graphRevision,
                              overridePositions: _displayPos,
                              viewport: viewportRect,
                              allowedNodeIds: _allowedNodeIdsForZoom(zoom),
                              resultNodeIds:
                                  widget.mode == NodeGraphMode.searchResult
                                      ? widget.resultNodeIds
                                      : null,
                              onboardingSearchResult:
                                  widget.onboardingSearchResult,
                              searchResultExitT: widget.searchResultExitT,
                              searchWaveAnimation:
                                  (widget.mode == NodeGraphMode.searching ||
                                          widget.mode ==
                                              NodeGraphMode.publishing)
                                      ? _searchWaveController
                                      : null,
                              searchResultIntroAnimation:
                                  widget.mode == NodeGraphMode.searchResult &&
                                          widget.resultNodeIds != null &&
                                          widget.resultNodeIds!.isNotEmpty
                                      ? _searchResultIntroController
                                      : null,
                              nodeRadius: _getNodeRadius(
                                NodeCountUtils.effectiveCountForRendering(
                                  widget.graph.nodes.length,
                                ),
                              ),
                              minNodeRadiusPx:
                                  widget.nodeRadius != null ? 8.0 : null,
                              lineColor: lineColor,
                              primaryColor: primaryColor,
                              nodeColors: widget.nodeColorScheme,
                              selectedNodeId: _effectiveSelectedNodeId,
                              draggingNodeId:
                                  _isNodeDragging ? _dragRootNodeId : null,
                              dragGroupNodeIds:
                                  _isNodeDragging
                                      ? _dragStartPositions.keys.toSet()
                                      : _lastDragGroupForFade,
                              dragFadeAnimation: _dragFade,
                              screenSize: screenSize,
                              zoom: zoom,
                              maxEdges: _edgeCapForZoom(
                                zoom,
                                widget.graph.edges.length,
                              ),
                              minEdgeSimilarity: _minSimilarityForZoom(zoom),
                              nodeCount:
                                  NodeCountUtils.effectiveCountForRendering(
                                    widget.graph.nodes.length,
                                  ),
                              edgeRenderMode: widget.edgeRenderMode,
                              representativeMaxEdgesPerCluster:
                                  widget.representativeMaxEdgesPerCluster,
                              keyboardCompressionFactor: keyboardCompression,
                              cameraRepaint: _camera,
                              ),
                              size: worldSize,
                            ),
                          ),
                          if (widget.showLabels)
                            ...(widget.graph.nodes.isEmpty
                                ? [
                                  Positioned(
                                    left: worldSize.width / 2 - 30,
                                    top:
                                        worldSize.height / 2 +
                                        _getNodeRadius(
                                          NodeCountUtils.effectiveCountForRendering(
                                            0,
                                          ),
                                        ) +
                                        5,
                                    child: IgnorePointer(
                                      ignoring: true,
                                      child: Text(
                                        '기록하기',
                                        style: TypographyUtil.style(
                                          context: context,
                                          fontSize:
                                              NodeCountUtils.labelFontSize(0),
                                          color:
                                              isDark
                                                  ? AppColors.darkTextPrimary
                                                  : AppColors.lightTextPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ]
                                : _labelsNodeList(zoom).map((node) {
                                  // 드래그 중: 연결된 노드만 라벨 표시, 나머지는 위젯 생략(뮤트)
                                  final dragGroupIds =
                                      _isNodeDragging
                                          ? _dragStartPositions.keys.toSet()
                                          : null;
                                  if (dragGroupIds != null &&
                                      !dragGroupIds.contains(node.id)) {
                                    return const SizedBox.shrink();
                                  }
                                  final isImportant =
                                      _effectiveSelectedNodeId == node.id;
                                  final p =
                                      _displayPos[node.id] ?? node.position;
                                  final centerA = centerAlpha(p);
                                  final targetAlpha =
                                      isImportant
                                          ? 1.0
                                          : (labelOn ? centerA : 0.0);
                                  // 가장자리 노드(labelOn인데 center 거의 0)만 빌드 생략
                                  if (labelOn &&
                                      !isImportant &&
                                      centerA <= 0.01) {
                                    return const SizedBox.shrink();
                                  }
                                  return Positioned(
                                    left: p.dx - 30,
                                    top:
                                        p.dy +
                                        _getNodeRadius(
                                          NodeCountUtils.effectiveCountForRendering(
                                            widget.graph.nodes.length,
                                          ),
                                        ) +
                                        5,
                                    child: IgnorePointer(
                                      ignoring: true,
                                      child: AnimatedOpacity(
                                        opacity: targetAlpha,
                                        duration: const Duration(
                                          milliseconds: 280,
                                        ),
                                        child: Text(
                                          node.label,
                                          style: TypographyUtil.style(
                                            context: context,
                                            fontSize:
                                                NodeCountUtils.labelFontSize(
                                                  widget.graph.nodes.length,
                                                ),
                                            color:
                                                isDark
                                                    ? AppColors.darkTextPrimary
                                                    : AppColors
                                                        .lightTextPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList()),
                            ],
                          ),
                        ),
                      ),
                  );
                },
              ),
        );
      },
    ),
  );
  }
}
