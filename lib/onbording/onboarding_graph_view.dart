import 'dart:math' show Random;
import 'package:doppy/graph/models/edge.dart';
import 'package:doppy/graph/models/node.dart';
import 'package:doppy/onbording/onboarding_canvas.dart';
import 'package:flutter/material.dart';

// 0..1 정규화 후 720 스케일, 여백 30
Offset _p(double x, double y) => Offset(x * 720 + 30, y * 720 + 30);

/// 씬(월드) 크기 — createOnboardingGraphData 좌표계와 동일
const double kOnboardingWorldSize = 780.0;

/// 북두칠성 + 주변 별. 노드 0~6: 북두칠성, 7~11: 주변 별
GraphData createOnboardingGraphData([Random? random]) {
  final bigDipperPositions = [
    _p(0.06, 0.52),
    _p(0.22, 0.54),
    _p(0.38, 0.56),
    _p(0.46, 0.50),
    _p(0.62, 0.36),
    _p(0.76, 0.48),
    _p(0.54, 0.56),
  ];
  final bigDipperNodes = [
    for (var i = 0; i < 7; i++)
      GraphNode(
        id: i,
        label: '$i',
        position: bigDipperPositions[i],
        isPublic: true,
        isAnchor: i == 0,
        clusterId: 0,
        anchorId: i == 0 ? null : 0,
        orderInCluster: i == 0 ? null : i,
        intensity: 1,
      ),
  ];
  final bigDipperEdges = [
    GraphEdge(fromNodeId: 0, toNodeId: 1, similarity: 0.9),
    GraphEdge(fromNodeId: 1, toNodeId: 2, similarity: 0.88),
    GraphEdge(fromNodeId: 2, toNodeId: 3, similarity: 0.88),
    GraphEdge(fromNodeId: 3, toNodeId: 4, similarity: 0.88),
    GraphEdge(fromNodeId: 4, toNodeId: 5, similarity: 0.88),
    GraphEdge(fromNodeId: 5, toNodeId: 6, similarity: 0.88),
    GraphEdge(fromNodeId: 6, toNodeId: 3, similarity: 0.88),
  ];

  const ambientPositions = [
    Offset(0.04, 0.14),
    Offset(0.12, 0.78),
    Offset(0.52, 0.88),
    Offset(0.88, 0.20),
    Offset(0.94, 0.62),
  ];
  final ambientNodes = [
    for (var i = 0; i < 5; i++)
      GraphNode(
        id: 7 + i,
        label: '${7 + i}',
        position: _p(ambientPositions[i].dx, ambientPositions[i].dy),
        isPublic: true,
        clusterId: 0,
        anchorId: 0,
        orderInCluster: i,
        intensity: 1,
      ),
  ];

  final allNodes = [...bigDipperNodes, ...ambientNodes];
  List<GraphEdge> edges = [...bigDipperEdges];

  if (random != null) {
    // W 형태: ambient(7~11) 노드만 사용 — 북두칠성과 구분
    final ambientWithPos = ambientNodes.map((n) => (n.id, n.position)).toList();
    ambientWithPos.sort((a, b) => a.$2.dx.compareTo(b.$2.dx));
    if (ambientWithPos.length >= 4) {
      final i0 = 0;
      final i1 = 1;
      final i2 = 2;
      final i3 = 3;
      final ids = [
        ambientWithPos[i0].$1,
        ambientWithPos[i1].$1,
        ambientWithPos[i2].$1,
        ambientWithPos[i3].$1,
      ];
      edges = [
        ...edges,
        GraphEdge(fromNodeId: ids[0], toNodeId: ids[1], similarity: 0.88),
        GraphEdge(fromNodeId: ids[1], toNodeId: ids[2], similarity: 0.88),
        GraphEdge(fromNodeId: ids[2], toNodeId: ids[3], similarity: 0.88),
      ];
    }
  }

  return GraphData(nodes: allNodes, edges: edges);
}

/// W 엣지가 있으면 그 W를 이루는 4개 노드 id 반환. 없으면 빈 set.
/// W는 ambient(7~11) 노드만 사용.
Set<int> getOnboardingWNodeIds(GraphData graph) {
  const bigDipperIds = <int>{0, 1, 2, 3, 4, 5, 6};
  final ids = <int>{};
  for (final e in graph.edges) {
    final fromIn = bigDipperIds.contains(e.fromNodeId);
    final toIn = bigDipperIds.contains(e.toNodeId);
    if (!fromIn || !toIn) {
      ids.add(e.fromNodeId);
      ids.add(e.toNodeId);
    }
  }
  return ids;
}

/// 온보딩 전용 그래프 뷰. InteractiveViewer + OnboardingGraphPainter만 사용.
class OnboardingGraphView extends StatefulWidget {
  const OnboardingGraphView({
    super.key,
    required this.graph,
    this.resultNodeIds,
    this.searchResultExitT,
    this.searchResultExitAnimation,
    this.searchWaveAnimation,
    this.searchWaveFadeOutAnimation,
    this.searchWaveIntroAnimation,
    this.primaryColor,
  });

  final GraphData graph;
  final Set<int>? resultNodeIds;
  final double? searchResultExitT;
  final Animation<double>? searchResultExitAnimation;
  final Animation<double>? searchWaveAnimation;
  final Animation<double>? searchWaveFadeOutAnimation;
  final Animation<double>? searchWaveIntroAnimation;
  final Color? primaryColor;

  @override
  State<OnboardingGraphView> createState() => _OnboardingGraphViewState();
}

class _OnboardingGraphViewState extends State<OnboardingGraphView>
    with TickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _introController;
  late final Animation<double> _introAnimation;
  int _graphRevision = 0;
  Set<int>? _prevResultNodeIds;
  bool _initialTransformSet = false;
  bool _initialTransformScheduled = false;
  Listenable? _paintListenable;

  /// 축소 시 맞출 기본 뷰 (검색결과 exit와 동기화)
  Matrix4? _defaultTransform;

  /// 검색결과 진입 시 약간 확대된 뷰
  Matrix4? _resultTransform;
  double _viewWidth = 0;
  double _viewHeight = 0;
  VoidCallback? _exitListenerRemover;

  static const double _worldSize = kOnboardingWorldSize;
  static const double _resultFitMargin = 2;

  Listenable _getPaintListenable() {
    final wave = widget.searchWaveAnimation;
    final exit = widget.searchResultExitAnimation;
    if (_paintListenable != null) return _paintListenable!;
    final fadeOut = widget.searchWaveFadeOutAnimation;
    final waveIntro = widget.searchWaveIntroAnimation;
    _paintListenable = Listenable.merge([
      _transformController,
      _introAnimation,
      if (wave != null) wave,
      if (exit != null) exit,
      if (fadeOut != null) fadeOut,
      if (waveIntro != null) waveIntro,
    ]);
    return _paintListenable!;
  }

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _introAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
  }

  void _setInitialTransform(double viewW, double viewH) {
    if (_initialTransformSet || !mounted) return;
    _initialTransformSet = true;
    _viewWidth = viewW;
    _viewHeight = viewH;
    final s = (viewW / _worldSize).clamp(0.35, 4.0);
    final sH = (viewH / _worldSize).clamp(0.35, 4.0);
    final scale = (s <= sH ? s : sH).clamp(0.35, 1.0);
    final tx = viewW / 2 - _worldSize * scale / 2;
    final ty = viewH / 2 - _worldSize * scale / 2;
    final m =
        Matrix4.identity()
          ..translate(tx, ty)
          ..scale(scale);
    _defaultTransform = m.clone();
    _transformController.value = m;
  }

  /// 검색결과 노드 + 연결 엣지만 안 잘리게 fit 확대
  void _applyResultZoomIn() {
    final ids = widget.resultNodeIds;
    if (ids == null || ids.isEmpty || _viewWidth <= 0 || _viewHeight <= 0)
      return;

    final graph = widget.graph;
    final resultNodes =
        ids.map((id) => graph.getNodeById(id)).whereType<GraphNode>().toList();
    if (resultNodes.isEmpty) return;

    const pad = 50.0;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final n in resultNodes) {
      final p = n.position;
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    minX -= pad;
    minY -= pad;
    maxX += pad;
    maxY += pad;
    final w = (maxX - minX).clamp(1.0, double.infinity);
    final h = (maxY - minY).clamp(1.0, double.infinity);
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;

    final availW = (_viewWidth - 2 * _resultFitMargin).clamp(
      20.0,
      double.infinity,
    );
    final availH = (_viewHeight - 2 * _resultFitMargin).clamp(
      20.0,
      double.infinity,
    );
    final scale = (availW / w).clamp(0.1, 5.0);
    final scaleH = (availH / h).clamp(0.1, 5.0);
    final s = (scale < scaleH ? scale : scaleH).clamp(0.35, 4.0);
    final tx = _viewWidth / 2 - cx * s;
    final ty = _viewHeight / 2 - cy * s;

    _resultTransform =
        Matrix4.identity()
          ..translate(tx, ty)
          ..scale(s);
    _transformController.value = _resultTransform!.clone();
  }

  void _syncTransformToExitT(double exitT) {
    final from = _resultTransform;
    final to = _defaultTransform;
    if (from == null || to == null) return;
    final t = exitT.clamp(0.0, 1.0);
    _transformController.value = Matrix4Tween(begin: from, end: to).lerp(t);
  }

  @override
  void didUpdateWidget(covariant OnboardingGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.resultNodeIds;
    final prev = _prevResultNodeIds;
    final wasResult = prev != null && prev.isNotEmpty;
    final isResult = next != null && next.isNotEmpty;
    _prevResultNodeIds = next;

    if (isResult) {
      if (!wasResult) {
        _introController.forward(from: 0);
        _applyResultZoomIn();
      }
      // exit 애니메이션과 동기화: 축소 시 _defaultTransform과 딱 맞게
      final exitAnim = widget.searchResultExitAnimation;
      _exitListenerRemover?.call();
      if (exitAnim != null) {
        void listener() {
          if (!mounted) return;
          _syncTransformToExitT(exitAnim.value);
        }

        exitAnim.addListener(listener);
        _exitListenerRemover = () => exitAnim.removeListener(listener);
        _syncTransformToExitT(exitAnim.value);
      }
    } else {
      _exitListenerRemover?.call();
      _exitListenerRemover = null;
      if (_defaultTransform != null) {
        _transformController.value = _defaultTransform!.clone();
      }
      _introController.stop();
      _introController.reset();
    }
    if (oldWidget.graph != widget.graph) {
      _graphRevision++;
    }
    final resultIdsChanged = isResult != wasResult;
    if (resultIdsChanged ||
        oldWidget.searchWaveAnimation != widget.searchWaveAnimation ||
        oldWidget.searchResultExitAnimation !=
            widget.searchResultExitAnimation ||
        oldWidget.searchWaveFadeOutAnimation !=
            widget.searchWaveFadeOutAnimation ||
        oldWidget.searchWaveIntroAnimation != widget.searchWaveIntroAnimation) {
      _paintListenable = null;
    }
  }

  @override
  void dispose() {
    _exitListenerRemover?.call();
    _transformController.dispose();
    _introController.dispose();
    super.dispose();
  }

  double _zoomFromMatrix(Matrix4 m) {
    final s = m.getMaxScaleOnAxis();
    return s.clamp(0.25, 5.0);
  }

  Widget _buildContent() {
    final primaryColor =
        widget.primaryColor ?? Theme.of(context).colorScheme.primary;
    final inResultMode =
        widget.resultNodeIds != null && widget.resultNodeIds!.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w > 0 && h > 0 && !_initialTransformScheduled) {
          _initialTransformScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _setInitialTransform(w, h);
          });
        }
        return InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.35,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(24),
          child: SizedBox(
            width: _worldSize,
            height: _worldSize,
            child: ListenableBuilder(
              listenable: _getPaintListenable(),
              builder: (_, __) {
                final exitT =
                    widget.searchResultExitAnimation?.value ??
                    (widget.searchResultExitT ?? 1.0);
                final waveFadeOutT = widget.searchWaveFadeOutAnimation?.value;
                final waveIntroT = widget.searchWaveIntroAnimation?.value;
                Widget paintChild() => RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(_worldSize, _worldSize),
                    painter: OnboardingGraphPainter(
                      graph: widget.graph,
                      revision: _graphRevision,
                      primaryColor: primaryColor,
                      overridePositions: null,
                      viewport: null,
                      resultNodeIds: widget.resultNodeIds,
                      searchResultExitT: exitT,
                      searchResultIntroAnimation:
                          inResultMode ? _introAnimation : null,
                      searchWaveAnimation: widget.searchWaveAnimation,
                      searchWaveFadeOutT: waveFadeOutT,
                      searchWaveIntroT: waveIntroT,
                      zoom: _zoomFromMatrix(_transformController.value),
                    ),
                  ),
                );
                if (inResultMode) {
                  return AnimatedBuilder(
                    animation: _introAnimation,
                    builder: (_, __) => paintChild(),
                  );
                }
                return paintChild();
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: _buildContent());
  }
}
