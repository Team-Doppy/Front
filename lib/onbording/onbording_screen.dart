import 'package:doppy/graph/graph.dart';
import 'package:doppy/main.dart';
import 'package:doppy/onbording/join_flow.dart';
import 'package:doppy/screens/%20setting_screen.dart';
import 'package:doppy/utils/snackbar_util.dart';
import 'package:doppy/utils/typograpy_util.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

class LoginScreen extends StatefulWidget {
  /// 회원 탈퇴 후 진입 시 결과에 따라 스낵바 표시
  final bool? deletionResult;

  const LoginScreen({super.key, this.deletionResult});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// 온보딩용 그래프 (30노드). 레이아웃은 NodeGraphView에서 ForceDirected 적용.
/// - clusterId / anchorId / orderInCluster / intensity / isAnchor 로 메인 앱과 동일 스타일
GraphData createOnboardingGraph() {
  const zero = Offset.zero;
  return GraphData(
    nodes: [
      // 상단 허브 0 (앵커) + 이웃 1~7
      GraphNode(id: 0, label: '0', position: zero, isPublic: true, isAnchor: true, clusterId: 0, intensity: 3),
      GraphNode(id: 1, label: '1', position: zero, isPublic: false, clusterId: 0, anchorId: 0, orderInCluster: 0, intensity: 2),
      GraphNode(id: 2, label: '2', position: zero, isPublic: true, clusterId: 0, anchorId: 0, orderInCluster: 1, intensity: 3),
      GraphNode(id: 3, label: '3', position: zero, isPublic: false, clusterId: 0, anchorId: 0, orderInCluster: 2, intensity: 2),
      GraphNode(id: 4, label: '4', position: zero, isPublic: true, clusterId: 0, anchorId: 0, orderInCluster: 3, intensity: 2),
      GraphNode(id: 5, label: '5', position: zero, isPublic: false, clusterId: 0, anchorId: 0, orderInCluster: 4, intensity: 3),
      GraphNode(id: 6, label: '6', position: zero, isPublic: true, clusterId: 0, anchorId: 0, orderInCluster: 5, intensity: 2),
      GraphNode(id: 7, label: '7', position: zero, isPublic: false, clusterId: 0, anchorId: 0, orderInCluster: 6, intensity: 2),
      // 중앙 허브 8 (앵커) + 이웃 9~14
      GraphNode(id: 8, label: '8', position: zero, isPublic: true, isAnchor: true, clusterId: 1, intensity: 3),
      GraphNode(id: 9, label: '9', position: zero, isPublic: false, clusterId: 1, anchorId: 8, orderInCluster: 0, intensity: 2),
      GraphNode(id: 10, label: '10', position: zero, isPublic: true, clusterId: 1, anchorId: 8, orderInCluster: 1, intensity: 3),
      GraphNode(id: 11, label: '11', position: zero, isPublic: false, clusterId: 1, anchorId: 8, orderInCluster: 2, intensity: 2),
      GraphNode(id: 12, label: '12', position: zero, isPublic: true, clusterId: 1, anchorId: 8, orderInCluster: 3, intensity: 2),
      GraphNode(id: 13, label: '13', position: zero, isPublic: false, clusterId: 1, anchorId: 8, orderInCluster: 4, intensity: 2),
      GraphNode(id: 14, label: '14', position: zero, isPublic: true, clusterId: 1, anchorId: 8, orderInCluster: 5, intensity: 2),
      // 하단 허브 15 (앵커) + 이웃 16~21
      GraphNode(id: 15, label: '15', position: zero, isPublic: true, isAnchor: true, clusterId: 2, intensity: 3),
      GraphNode(id: 16, label: '16', position: zero, isPublic: false, clusterId: 2, anchorId: 15, orderInCluster: 0, intensity: 2),
      GraphNode(id: 17, label: '17', position: zero, isPublic: true, clusterId: 2, anchorId: 15, orderInCluster: 1, intensity: 3),
      GraphNode(id: 18, label: '18', position: zero, isPublic: false, clusterId: 2, anchorId: 15, orderInCluster: 2, intensity: 2),
      GraphNode(id: 19, label: '19', position: zero, isPublic: true, clusterId: 2, anchorId: 15, orderInCluster: 3, intensity: 2),
      GraphNode(id: 20, label: '20', position: zero, isPublic: false, clusterId: 2, anchorId: 15, orderInCluster: 4, intensity: 2),
      GraphNode(id: 21, label: '21', position: zero, isPublic: true, clusterId: 2, anchorId: 15, orderInCluster: 5, intensity: 2),
      // 독립 노드 22~29 (intensity 1 = 회색)
      GraphNode(id: 22, label: '22', position: zero, isPublic: false, intensity: 1),
      GraphNode(id: 23, label: '23', position: zero, isPublic: true, intensity: 1),
      GraphNode(id: 24, label: '24', position: zero, isPublic: false, intensity: 1),
      GraphNode(id: 25, label: '25', position: zero, isPublic: true, intensity: 1),
      GraphNode(id: 26, label: '26', position: zero, isPublic: false, intensity: 1),
      GraphNode(id: 27, label: '27', position: zero, isPublic: true, intensity: 1),
      GraphNode(id: 28, label: '28', position: zero, isPublic: false, intensity: 1),
      GraphNode(id: 29, label: '29', position: zero, isPublic: true, intensity: 1),
    ],
    edges: [
      // 상단 허브: 0 → 3개만 (불규칙하게)
      GraphEdge(fromNodeId: 0, toNodeId: 1, similarity: 0.88),
      GraphEdge(fromNodeId: 0, toNodeId: 3, similarity: 0.85),
      GraphEdge(fromNodeId: 0, toNodeId: 6, similarity: 0.82),
      // 중앙 허브: 8 → 3개만
      GraphEdge(fromNodeId: 8, toNodeId: 9, similarity: 0.85),
      GraphEdge(fromNodeId: 8, toNodeId: 12, similarity: 0.82),
      GraphEdge(fromNodeId: 8, toNodeId: 14, similarity: 0.8),
      // 하단 허브: 15 → 3개만
      GraphEdge(fromNodeId: 15, toNodeId: 17, similarity: 0.85),
      GraphEdge(fromNodeId: 15, toNodeId: 19, similarity: 0.82),
      GraphEdge(fromNodeId: 15, toNodeId: 21, similarity: 0.8),
    ],
  );
}

final _onboardingGraph = createOnboardingGraph();

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final List<String> _exampleWords = [
    '행복했던 날들',
    '사랑은 어려워',
    '상처받은 순간들',
    '퇴근 후 공허함',
  ];
  int _currentWordIndex = 0;
  String _displayText = '';
  int _charIndex = 0;
  bool _isDeleting = false;
  bool _deleteScheduled = false;
  Timer? _timer;
  Timer? _resultEnterTimer;
  Timer? _resultExitTimer;
  Timer? _deleteStartTimer;
  int _searchResultCycle = 0;
  late AnimationController _cursorController;
  late AnimationController _searchResultExitController;
  late Animation<double> _searchResultExitAnimation;
  NodeGraphMode _graphMode = NodeGraphMode.onboarding;
  Set<int> _searchResultNodeIds = {};
  bool _exitAnimRebuildScheduled = false;

  void _onSearchResultExitTick() {
    if (!mounted || _exitAnimRebuildScheduled) return;
    _exitAnimRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _exitAnimRebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _searchResultExitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _searchResultExitAnimation = CurvedAnimation(
      parent: _searchResultExitController,
      curve: Curves.easeInOutCubic,
    )..addListener(_onSearchResultExitTick);
    _searchResultExitController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        // setState during build 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _graphMode = NodeGraphMode.onboarding;
              _searchResultNodeIds = {};
              _searchResultExitController.reset();
            });
          }
        });
      }
    });
    _startTypingAnimation();
    final result = widget.deletionResult;
    if (result != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (result) {
          SnackbarUtil.showInfo(
            context,
            '탈퇴 처리되었습니다. 이용해 주셔서 감사합니다.',
            duration: const Duration(seconds: 3),
          );
        } else {
          SnackbarUtil.showError(
            context,
            '탈퇴에 실패했어요. 다시 시도해 주세요.',
            duration: const Duration(seconds: 3),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resultEnterTimer?.cancel();
    _resultExitTimer?.cancel();
    _deleteStartTimer?.cancel();
    _cursorController.dispose();
    _searchResultExitController.dispose();
    super.dispose();
  }

  void _startTypingAnimation() {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) return;

      setState(() {
        final currentWord = _exampleWords[_currentWordIndex];

        if (!_isDeleting) {
          if (_charIndex < currentWord.length) {
            _displayText = currentWord.substring(0, _charIndex + 1);
            _charIndex++;
          } else {
            // 한 번만 스케줄: 치고 지우기까지 시간을 좀 둠
            if (!_deleteScheduled) {
              _deleteScheduled = true;
              _scheduleSearchResultBetweenTypingAndDeleting();
            }
          }
        } else {
          if (_displayText.isNotEmpty) {
            _displayText = _displayText.substring(0, _displayText.length - 1);
          } else {
            // Move to next word
            _isDeleting = false;
            _charIndex = 0;
            _currentWordIndex = (_currentWordIndex + 1) % _exampleWords.length;
          }
        }
      });
    });
  }

  /// “타이핑 끝 ↔ 삭제 시작” 사이 구간에만 검색결과 연출을 넣고,
  /// 삭제 시작 전에 복귀(exit)가 끝나도록 타이밍을 맞춘다.
  void _scheduleSearchResultBetweenTypingAndDeleting() {
    _resultEnterTimer?.cancel();
    _resultExitTimer?.cancel();
    _deleteStartTimer?.cancel();

    const totalPauseMs = 3500; // 타이핑 끝나고 삭제 시작까지 여유
    const enterDelayMs = 350; // 타이핑 끝난 직후 약간 쉬었다가 결과 진입
    const exitDurationMs = 680; // _searchResultExitController와 동일
    const exitBufferMs = 80; // 프레임 여유
    final exitStartMs = math.max(
      0,
      totalPauseMs - exitDurationMs - exitBufferMs,
    );

    // 1) 결과 진입 (타이핑과 삭제 사이)
    _resultEnterTimer = Timer(const Duration(milliseconds: enterDelayMs), () {
      if (!mounted) return;
      if (_isDeleting) return;
      if (_graphMode != NodeGraphMode.onboarding) return;

      _searchResultCycle++;
      final phase = (_searchResultCycle * 0.173) % 1.0; // 매번 다르게(결정적)
      final ids = _pickDistributedSearchResultNodeIds(
        desiredHubs: 3,
        neighborsPerHub: 4,
        minTotal: 12,
        phase: phase,
      );
      setState(() {
        _searchResultNodeIds = ids;
        _graphMode = NodeGraphMode.searchResult;
      });
    });

    // 2) 삭제 시작 전에 복귀(exit) 시작
    _resultExitTimer = Timer(Duration(milliseconds: exitStartMs), () {
      if (!mounted) return;
      if (_graphMode != NodeGraphMode.searchResult) return;
      if (!_searchResultExitController.isAnimating) {
        _searchResultExitController.forward(from: 0);
      }
    });

    // 3) 삭제 시작
    _deleteStartTimer = Timer(const Duration(milliseconds: totalPauseMs), () {
      if (!mounted) return;
      setState(() {
        _isDeleting = true;
        _deleteScheduled = false;
      });
      // 안전장치: 아직 결과 모드면 즉시 exit 트리거
      if (mounted &&
          _graphMode == NodeGraphMode.searchResult &&
          !_searchResultExitController.isAnimating) {
        _searchResultExitController.forward(from: 0);
      }
    });
  }

  /// 온보딩 검색결과에서 “엣지가 뻗는 포스트”가 1개로 몰리지 않게
  /// - 상단에 1개 허브를 **보장**하고(사용자 요구),
  /// - 좌하/우하에 1개씩 추가로 허브를 고른 뒤,
  /// - 각 허브의 이웃 노드를 몇 개씩 포함해 결과를 구성한다.
  Set<int> _pickDistributedSearchResultNodeIds({
    required int desiredHubs,
    required int neighborsPerHub,
    required int minTotal,
    double phase = 0.0,
  }) {
    final nodes = _onboardingGraph.nodes;
    final edges = _onboardingGraph.edges;
    if (nodes.isEmpty) return {};

    // 중심점(각도 계산용)
    var sx = 0.0;
    var sy = 0.0;
    for (final n in nodes) {
      sx += n.position.dx;
      sy += n.position.dy;
    }
    final center = Offset(sx / nodes.length, sy / nodes.length);

    // 인접 리스트(유사도 내림차순)
    final adj = <int, List<(int, double)>>{};
    for (final e in edges) {
      (adj[e.fromNodeId] ??= []).add((e.toNodeId, e.similarity));
      (adj[e.toNodeId] ??= []).add((e.fromNodeId, e.similarity));
    }
    for (final entry in adj.entries) {
      entry.value.sort((a, b) => b.$2.compareTo(a.$2));
    }

    // 노드 degree (허브 선택용)
    final degree = <int, int>{};
    for (final e in edges) {
      degree[e.fromNodeId] = (degree[e.fromNodeId] ?? 0) + 1;
      degree[e.toNodeId] = (degree[e.toNodeId] ?? 0) + 1;
    }

    GraphNode? pickHubFrom(List<GraphNode> list, int salt) {
      if (list.isEmpty) return null;
      final sorted = [...list]..sort((a, b) {
        final da = degree[a.id] ?? 0;
        final db = degree[b.id] ?? 0;
        if (da != db) return db.compareTo(da); // degree desc
        final ra = (a.position - center).distance;
        final rb = (b.position - center).distance;
        return rb.compareTo(ra); // 더 바깥쪽 우선
      });
      final topK = math.min(4, sorted.length);
      final idx = ((phase * topK).floor() + salt) % topK;
      return sorted[idx];
    }

    // 허브 3개: 상단 1개 + 좌하 1개 + 우하 1개 (가능하면)
    final top = nodes.where((n) => n.position.dy < center.dy).toList();
    final bottomLeft =
        nodes
            .where(
              (n) => n.position.dy >= center.dy && n.position.dx < center.dx,
            )
            .toList();
    final bottomRight =
        nodes
            .where(
              (n) => n.position.dy >= center.dy && n.position.dx >= center.dx,
            )
            .toList();

    final seedIds = <int>{};
    final hubs = <GraphNode?>[
      pickHubFrom(top, 0),
      pickHubFrom(bottomLeft, 1),
      pickHubFrom(bottomRight, 2),
    ];
    for (final h in hubs) {
      if (h != null) seedIds.add(h.id);
    }
    // fallback: 부족하면 degree 높은 순으로 채우기
    if (seedIds.length < desiredHubs) {
      final allSorted = [...nodes]
        ..sort((a, b) => (degree[b.id] ?? 0).compareTo(degree[a.id] ?? 0));
      for (final n in allSorted) {
        seedIds.add(n.id);
        if (seedIds.length >= desiredHubs) break;
      }
    }

    // 각도 기준 정렬 (minTotal 채우기용으로 “골고루”)
    final byAngle = [...nodes]..sort((a, b) {
      final aa = math.atan2(
        a.position.dy - center.dy,
        a.position.dx - center.dx,
      );
      final bb = math.atan2(
        b.position.dy - center.dy,
        b.position.dx - center.dx,
      );
      return aa.compareTo(bb);
    });

    final resultIds = <int>{};
    for (final sid in seedIds) {
      resultIds.add(sid);
      final neighbors = adj[sid] ?? const [];
      for (final pair in neighbors.take(neighborsPerHub)) {
        resultIds.add(pair.$1);
      }
    }

    // 부족하면 각도 순으로 채우기 (너무 적게 선택되면 엣지도 희박해 보임)
    if (resultIds.length < minTotal) {
      for (final n in byAngle) {
        resultIds.add(n.id);
        if (resultIds.length >= minTotal) break;
      }
    }

    return resultIds;
  }

  void _stopSearchCycle() {
    _resultEnterTimer?.cancel();
    _resultExitTimer?.cancel();
    _deleteStartTimer?.cancel();
    if (mounted) {
      setState(() {
        _graphMode = NodeGraphMode.onboarding;
        _searchResultNodeIds = {};
      });
    }
  }

  void _navigateToPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => const WebViewScreen(
              url: AppConstants.termsOfServiceUrl,
              title: "개인정보 처리방침 및 이용약관",
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Title text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: '기록을 넘어',
                          style: TypographyUtil.style(
                            context: context,
                            fontSize: 28,
                            fontWeight: FontWeight.w400,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 50),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '패턴을 ',
                              style: TypographyUtil.style(
                                context: context,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            TextSpan(
                              text: '발견하다',
                              style: TypographyUtil.style(
                                context: context,
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 50),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // NodeGraphView (하드코딩 데이터 모드)
              // exit 애니메이션 중 매 프레임 리빌드로 색상/투명도 전환 부드럽게
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedBuilder(
                    animation: _searchResultExitController,
                    builder:
                        (context, _) => NodeGraphView(
                          graph: _onboardingGraph,
                          mode: _graphMode,
                          resultNodeIds:
                              _searchResultNodeIds.isEmpty
                                  ? null
                                  : _searchResultNodeIds,
                          onboardingSearchResult: true,
                          searchResultExitT:
                              _graphMode == NodeGraphMode.searchResult &&
                                      _searchResultExitController.value > 0
                                  ? _searchResultExitAnimation.value
                                  : null,
                          enableNodeDrag: true,
                          showLabels: false,
                          onNodeTap: null,
                          onNodeSelected: null,
                          edgeRenderMode: EdgeRenderMode.all,
                          useProvidedPositions: false,
                          layoutIrregularity: 0.22,
                          maxEdges: 50,
                          minEdgeSimilarity: 0.0,
                        ),
                  ),
                ),
              ),

              // Input field with typing animation
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color:
                            isDark
                                ? Theme.of(context).colorScheme.background
                                : Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  _displayText,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                AnimatedBuilder(
                                  animation: _cursorController,
                                  builder: (context, child) {
                                    return Opacity(
                                      opacity: _cursorController.value,
                                      child: Container(
                                        width: 2,
                                        height: 20,
                                        margin: const EdgeInsets.only(left: 2),
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.search,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 50),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          _stopSearchCycle();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const JoinFlow()),
                          ).then((_) {
                            FocusScope.of(context).unfocus();
                            if (!mounted) return;
                            // 뒤로 돌아왔을 때 애니메이션 루프 재개
                            if (_deleteScheduled && !_isDeleting) {
                              setState(() {
                                _isDeleting = true;
                                _deleteScheduled = false;
                              });
                            }
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.onSurface,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          '시작하기',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.surface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Privacy Policy Link
                    GestureDetector(
                      onTap: _navigateToPrivacyPolicy,
                      child: Text(
                        '개인정보 처리방침 및 이용약관',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 60),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
