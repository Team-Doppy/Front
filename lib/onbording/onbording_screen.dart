import 'package:doppy/graph/graph.dart';
import 'package:doppy/main.dart';
import 'package:doppy/onbording/join_flow.dart';
import 'package:doppy/onbording/onboarding_graph_view.dart'
    show createOnboardingGraphData, getOnboardingWNodeIds;
import 'package:doppy/screens/%20setting_screen.dart';
import 'package:doppy/utils/typograpy_util.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

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
  late GraphData _onboardingGraph; // build마다 새로 만들지 말고, 스타일 바뀔 때만 교체
  late AnimationController _cursorController;
  late AnimationController _searchResultExitController;
  late Animation<double> _searchResultExitAnimation;
  NodeGraphMode _graphMode = NodeGraphMode.onboarding;
  Set<int> _searchResultNodeIds = {};

  @override
  void initState() {
    super.initState();
    _onboardingGraph = createOnboardingGraphData(math.Random());
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _searchResultExitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _searchResultExitAnimation = CurvedAnimation(
      parent: _searchResultExitController,
      curve: Curves.easeOutCubic,
    );
    _searchResultExitController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
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
            // 글씨를 다 썼을 때만 한 번 검색완료 애니메이션 스케줄 (마지막 글자 입력 직후)
            if (_charIndex == currentWord.length && !_deleteScheduled) {
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
    const exitDurationMs = 520; // _searchResultExitController와 동일
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

      final nextCycle = _searchResultCycle + 1;
      // 짝수: 북두칠성, 홀수: W 형태
      final wIds = getOnboardingWNodeIds(_onboardingGraph);
      final constellationIds =
          (nextCycle.isOdd && wIds.isNotEmpty)
              ? wIds
              : const <int>{0, 1, 2, 3, 4, 5, 6};
      final phase = (nextCycle * 0.173) % 1.0;
      final ids = _pickDistributedSearchResultNodeIds(
        graph: _onboardingGraph,
        constellationIds: constellationIds,
        desiredHubs: constellationIds.length >= 7 ? 3 : 2,
        neighborsPerHub: constellationIds.length >= 7 ? 2 : 1,
        minTotal: constellationIds.length.clamp(4, 7),
        phase: phase,
      );
      setState(() {
        _searchResultCycle = nextCycle;
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
    required GraphData graph,
    Set<int>? constellationIds,
    required int desiredHubs,
    required int neighborsPerHub,
    required int minTotal,
    double phase = 0.0,
  }) {
    var nodes = graph.nodes;
    var edges = graph.edges;
    if (constellationIds != null) {
      nodes = nodes.where((n) => constellationIds.contains(n.id)).toList();
      edges =
          edges
              .where(
                (e) =>
                    constellationIds.contains(e.fromNodeId) &&
                    constellationIds.contains(e.toNodeId),
              )
              .toList();
    }
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
              // NodeGraphView — 메인 canvas/페인터와 똑같이 (canvas.dart)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedBuilder(
                      animation: _searchResultExitAnimation,
                      builder:
                          (context, _) => NodeGraphView(
                            graph: _onboardingGraph,
                            mode:
                                _searchResultNodeIds.isEmpty
                                    ? NodeGraphMode.onboarding
                                    : NodeGraphMode.searchResult,
                            resultNodeIds:
                                _searchResultNodeIds.isEmpty
                                    ? null
                                    : _searchResultNodeIds,
                            onboardingSearchResult: true,
                            searchResultExitT:
                                _searchResultNodeIds.isEmpty
                                    ? 1.0
                                    : _searchResultExitAnimation.value,
                            useProvidedPositions: true,
                            layoutIrregularity: null,
                            nodeRadius: 18,
                            outerPadding: 12,
                          ),
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
