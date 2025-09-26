import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/group_model.dart';
import '../../../providers/group_provider.dart';
import 'group_profile_screen.dart';

// 그룹 관리 화면 메인 위젯
class ManageGroupScreen extends StatefulWidget {
  final bool embedded; // Tab 내 임베드 시 true
  final String? filterText; // 상위에서 전달한 검색어로 그룹 필터
  const ManageGroupScreen({Key? key, this.embedded = false, this.filterText})
    : super(key: key);

  @override
  State<ManageGroupScreen> createState() => _ManageGroupScreenState();
}

class _ManageGroupScreenState extends State<ManageGroupScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // 첫 빌드 후 캐시 우선 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GroupProvider>().fetchMyGroups();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupProv = context.watch<GroupProvider>();
    List<Group> groups = groupProv.myGroups;
    final q = (widget.filterText ?? '').trim().toLowerCase();
    if (q.isNotEmpty) {
      groups = groups.where((g) => g.name.toLowerCase().contains(q)).toList();
    }
    final List<Widget> slivers = [];

    // 상단 헤더는 단독 화면일 때만 포함(탭 임베드 시 상위 공통 AppBar 사용)
    if (!widget.embedded) {
      slivers.add(
        SliverAppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          floating: true,
          snap: true,
          expandedHeight: 100,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Theme.of(
                  context,
                ).colorScheme.background.withOpacity(0.8),
              ),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [_buildSearchBar(), const SizedBox(width: 16)],
        ),
      );
    } else {
      // 임베드일 때는 상단 여백만 살짝 추가
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }

    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child:
                groupProv.isLoading
                    ? const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    )
                    : Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: List.generate(groups.length, (index) {
                        final group = groups[index];
                        final size = _sizeForIndex(group.id, index);
                        return DragTarget<String>(
                          builder: (context, candidate, rejected) {
                            final bool isHover = candidate.isNotEmpty;
                            return _AnimatedStaggered(
                              index: index,
                              child: _GroupBubble(
                                group: group,
                                size: size,
                                overlayGlow: isHover,
                                onOpen: () async {
                                  final dummyGroup = Group(
                                    id: group.id,
                                    name: group.name,
                                    description: group.description,
                                    ownerId: group.ownerId,
                                    owner: group.owner,
                                    createdAt: group.createdAt,
                                  );
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => GroupProfileScreen(
                                            group: dummyGroup,
                                            heroTag: 'group-${group.id}',
                                          ),
                                    ),
                                  );
                                  if (result == 'deleted') {
                                    await context
                                        .read<GroupProvider>()
                                        .fetchMyGroups(forceRefresh: true);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('그룹이 삭제되었습니다'),
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                          onWillAccept:
                              (data) => data != null && data.isNotEmpty,
                          onAccept: (username) async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$username 님을 "${group.name}"에 추가합니다',
                                ),
                              ),
                            );
                            // TODO: GroupService.addMemberToGroup 연결
                          },
                        );
                      }),
                    ),
          ),
        ),
      ),
    );

    final Widget body = CustomScrollView(
      controller: _scrollController,
      slivers: slivers,
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,

      body: body,
    );
  }

  // 검색 바 위젯
  Widget _buildSearchBar() {
    return Container(
      height: 44,
      width: MediaQuery.of(context).size.width - 50,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: '그룹 검색',
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search_rounded),
          contentPadding: const EdgeInsets.only(top: 0),
        ),
      ),
    );
  }

  // 각 인덱스에 따라 크기를 가변으로 부여(원형 타일)
  double _sizeForIndex(int id, int index) {
    final seed = id ^ (index * 1315423911);
    final r = math.Random(seed);
    final options = [120.0, 150.0, 180.0, 210.0];
    return options[r.nextInt(options.length)];
  }
}

// 핀터레스트 스타일의 원형 타일
class _GroupBubble extends StatelessWidget {
  final Group group;
  final double size;
  final VoidCallback onOpen;
  final bool overlayGlow;

  const _GroupBubble({
    required this.group,
    required this.size,
    required this.onOpen,
    this.overlayGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _paletteFrom(group.id);
    final prov = context.watch<GroupProvider>();
    final members = prov.membersOf(group.id);
    final urls =
        members
            .map((m) => m.profileImageUrl)
            .whereType<String>()
            .where((u) => u.isNotEmpty)
            .toList();

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 배경 콜라주
            Hero(
              tag: 'group-${group.id}',
              flightShuttleBuilder: (context, animation, direction, from, to) {
                return SizedBox.expand(
                  child: ClipOval(
                    child: _GroupCollage(urls: urls, fallbackColors: colors),
                  ),
                );
              },
              child: SizedBox.expand(
                child: ClipOval(
                  child: _GroupCollage(urls: urls, fallbackColors: colors),
                ),
              ),
            ),
            // 오버레이 제거
            if (overlayGlow)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.25),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            // 멤버 수 배지(우상단)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${members.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Text(
                group.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  group.owner.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _paletteFrom(int seed) {
    final idx = seed % _palettes.length;
    return _palettes[idx];
  }
}

// 그룹 멤버 프로필 2x2 콜라주
class _GroupCollage extends StatelessWidget {
  final List<String> urls;
  final List<Color> fallbackColors;
  const _GroupCollage({required this.urls, required this.fallbackColors});

  @override
  Widget build(BuildContext context) {
    final tiles = urls.take(4).toList();
    Widget network(String u) => Stack(
      fit: StackFit.expand,
      children: [
        const ShimmerBox(width: double.infinity, height: double.infinity),
        Image.network(
          u,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return const SizedBox.expand(
              child: ShimmerBox(
                width: double.infinity,
                height: double.infinity,
              ),
            );
          },
          errorBuilder:
              (_, __, ___) => Container(color: const Color(0xFF3A3A3A)),
        ),
      ],
    );

    if (tiles.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [fallbackColors[0], fallbackColors[1]],
          ),
        ),
      );
    }

    Widget collage;
    if (tiles.length == 1) {
      collage = network(tiles[0]);
    } else if (tiles.length == 2) {
      collage = Row(
        children: [
          Expanded(child: network(tiles[0])),
          Expanded(child: network(tiles[1])),
        ],
      );
    } else {
      collage = Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(child: network(tiles[0])),
                Expanded(
                  child: network(tiles.length > 2 ? tiles[2] : tiles[0]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: network(tiles.length > 1 ? tiles[1] : tiles[0]),
                ),
                Expanded(
                  child: network(tiles.length > 3 ? tiles[3] : tiles[1]),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Padding(padding: const EdgeInsets.all(0), child: collage);
  }
}

// 타일 등장 시 더 부드러운 스태거드(슬라이드+페이드)
class _AnimatedStaggered extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedStaggered({required this.index, required this.child});

  @override
  State<_AnimatedStaggered> createState() => _AnimatedStaggeredState();
}

class _AnimatedStaggeredState extends State<_AnimatedStaggered>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);

    Future<void>.delayed(Duration(milliseconds: 60 * widget.index)).then((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

const List<List<Color>> _palettes = [
  [Color(0xFF6A85B6), Color(0xFFBAC8E0)],
  [Color(0xFF74EBD5), Color(0xFFACB6E5)],
  [Color(0xFFF5576C), Color(0xFFF093FB)],
  [Color(0xFF5EE7DF), Color(0xFFB490CA)],
  [Color(0xFF536976), Color(0xFF292E49)],
  [Color(0xFFFBD3E9), Color(0xFFBB377D)],
];
