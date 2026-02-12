import 'package:doppy/graph/models/edge.dart';
import 'package:doppy/graph/widgets/node_graph_view.dart';
import 'package:doppy/providers/graph_provider.dart';
import 'package:doppy/screens/%20setting_screen.dart';
import 'package:doppy/widgets/home_header.dart';
import 'package:doppy/widgets/home_search_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ===== 메인 화면 =====

class HomeScreen extends StatefulWidget {
  final HomeViewMode viewMode;
  final VoidCallback? onSearchClose;
  final void Function(int nodeId)? onNavigateToPost;

  const HomeScreen({
    super.key,
    this.viewMode = HomeViewMode.normal,
    this.onSearchClose,
    this.onNavigateToPost,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int? _selectedNodeId;
  bool _isAtMinScale = false;
  int _headerTabIndex = 0;
  GraphProvider? _pendingChipCloseProvider;
  late AnimationController _searchResultExitController;
  late Animation<double> _searchResultExitAnimation;
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
    _searchResultExitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _searchResultExitAnimation = CurvedAnimation(
      parent: _searchResultExitController,
      curve: Curves.easeInOutCubic,
    )..addListener(_onSearchResultExitTick);
    _searchResultExitController.addStatusListener(_onSearchResultExitStatus);
  }

  void _onSearchResultExitStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        _pendingChipCloseProvider == null)
      return;
    final prov = _pendingChipCloseProvider!;
    _pendingChipCloseProvider = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      prov.closeToNormal();
      widget.onSearchClose?.call();
      _searchResultExitController.reset();
    });
  }

  @override
  void dispose() {
    _searchResultExitController.removeStatusListener(_onSearchResultExitStatus);
    _searchResultExitController.dispose();
    super.dispose();
  }

  void _onNodeTap(int nodeId) {
    setState(() {
      _selectedNodeId = _selectedNodeId == nodeId ? null : nodeId;
    });
  }

  void _onChipClose(GraphProvider graphProv) {
    if (_searchResultExitController.isAnimating) return;
    _pendingChipCloseProvider = graphProv;
    _searchResultExitController.forward(from: 0);
  }

  NodeGraphMode _graphModeFrom(GraphProvider gp) {
    switch (gp.searchPhase) {
      case SearchPhase.searching:
        return NodeGraphMode.searching;
      case SearchPhase.searchResult:
        return NodeGraphMode.searchResult;
      default:
        return NodeGraphMode.normal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Consumer<GraphProvider>(
        builder: (context, graphProv, _) {
          final isSearchMode = widget.viewMode == HomeViewMode.search;
          final graphData = graphProv.graph ?? GraphData(nodes: [], edges: []);
          final showSearchField = isSearchMode && graphProv.isSearchFieldOpen;
          final keyboardVisible =
              MediaQuery.of(context).viewInsets.bottom > 20 || showSearchField;
          final showHeaderWithChip =
              isSearchMode &&
              graphProv.searchPhase == SearchPhase.searchResult &&
              !graphProv.isSearchFieldOpen &&
              !keyboardVisible;
          final showHeaderNormal =
              ((!isSearchMode && _isAtMinScale) ||
                  (isSearchMode &&
                      graphProv.searchPhase == SearchPhase.idle)) &&
              !keyboardVisible;

          return Stack(
            children: [
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 30),
                    Expanded(
                      child: NodeGraphView(
                        graph: graphData,
                        mode: _graphModeFrom(graphProv),
                        minEdgeSimilarity: 0.0,
                        maxEdges: 5000,
                        resultNodeIds:
                            graphProv.searchPhase == SearchPhase.searchResult
                                ? graphProv.resultNodeIds
                                : null,
                        searchResultExitT:
                            _searchResultExitController.value > 0
                                ? _searchResultExitAnimation.value
                                : null,
                        showLabels:
                            graphProv.searchPhase != SearchPhase.searching,
                        enableNodeDrag:
                            graphProv.searchPhase != SearchPhase.searching,
                        selectedNodeId: _selectedNodeId,
                        onNodeSelected: (nodeId) {
                          setState(() {
                            _selectedNodeId = nodeId;
                          });
                        },
                        onIsAtMinScale: (value) {
                          if (mounted && _isAtMinScale != value) {
                            setState(() => _isAtMinScale = value);
                          }
                        },
                        onNodeTap: _onNodeTap,
                        onNavigateToPost: widget.onNavigateToPost,
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: (showHeaderNormal || showHeaderWithChip) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !(showHeaderNormal || showHeaderWithChip),
                    child: Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: SafeArea(
                        bottom: false,
                        child: HomeHeader(
                          visible: true,
                          selectedIndex: _headerTabIndex,
                          onTabChanged:
                              (i) => setState(() => _headerTabIndex = i),
                          onMenuTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SettingScreen(),
                              ),
                            );
                          },
                          searchChipQuery:
                              showHeaderWithChip ? graphProv.searchQuery : null,
                          onChipTap:
                              showHeaderWithChip
                                  ? graphProv.openSearchField
                                  : null,
                          onChipClose:
                              showHeaderWithChip
                                  ? () => _onChipClose(graphProv)
                                  : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (isSearchMode && showSearchField) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.onSearchClose,
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
                HomeSearchField(
                  onClose: () => widget.onSearchClose?.call(),
                  onSubmitted: (query) {
                    FocusScope.of(context).unfocus();
                    graphProv.submitSearch(query);
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
