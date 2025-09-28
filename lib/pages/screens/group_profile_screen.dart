import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/group_model.dart';
import '../../data/models/group_member_model.dart';
import '../../providers/group_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/auth_provider.dart';

class GroupProfileScreen extends StatefulWidget {
  final Group group;
  final String? heroTag;

  const GroupProfileScreen({super.key, required this.group, this.heroTag});

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen>
    with WidgetsBindingObserver {
  late Group _group;
  bool _fadeCircle = false;
  bool _editing = false;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    WidgetsBinding.instance.addObserver(this);
    _nameCtrl.text = _group.name;
    _descCtrl.text = _group.description;
    // 히어로 원형이 배경으로 녹아들도록 약간 딜레이 후 페이드아웃
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (mounted) setState(() => _fadeCircle = true);
      if (!mounted) return;
      // 멤버 캐시 로드(캐시가 유효하면 notify만, 아니면 fetch)
      context.read<GroupProvider>().fetchGroupMembers(_group.id);
    });
  }

  Widget _buildCircleVisual({double size = 180}) {
    final prov = context.watch<GroupProvider>();
    final List<GroupMember> members = prov.membersOf(_group.id);
    final List<Color> colors = _paletteFrom(_group.id);
    final List<String> urls =
        members
            .map((m) => m.profileImageUrl)
            .whereType<String>()
            .where((u) => u.isNotEmpty)
            .toList();

    if (urls.isEmpty) {
      // 멤버가 없을 때 기본 플레이스홀더
      return ClipOval(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors[0], colors[1]],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Icon(Icons.groups_3, color: Colors.white70, size: 48),
          ),
        ),
      );
    }

    final tiles = urls.take(4).toList();

    Widget network(String u) => Image.network(
      u,
      fit: BoxFit.cover,

      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF3A3A3A)),
    );

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

    return SizedBox(width: size, height: size, child: ClipOval(child: collage));
  }

  List<Color> _paletteFrom(int seed) {
    final idx = seed % _palettes.length;
    return _palettes[idx];
  }

  // 그룹 색 팔레트(보라 계열 베이스)
  final List<List<Color>> _palettes = [
    [Color(0xFF6A85B6), Color(0xFFBAC8E0)],
    [Color(0xFF74EBD5), Color(0xFFACB6E5)],
    [Color(0xFFF5576C), Color(0xFFF093FB)],
    [Color(0xFF5EE7DF), Color(0xFFB490CA)],
    [Color(0xFF536976), Color(0xFF292E49)],
    [Color(0xFFFBD3E9), Color(0xFFBB377D)],
  ];

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshGroupInfo();
    }
  }

  Future<void> _refreshGroupInfo() async {
    try {
      await context.read<GroupProvider>().fetchMyGroups();
      final prov = context.read<GroupProvider>();
      final updated = prov.myGroups.firstWhere(
        (g) => g.id == _group.id,
        orElse: () => _group,
      );
      if (mounted) {
        setState(() => _group = updated);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Hero 원을 헤더 카드의 원과 정렬하기 위한 보정값 계산

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: [
          // 중복 Hero 제거: 헤더 카드의 Hero만 사용
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    if (!_editing)
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: Colors.white.withOpacity(0.8),
                          size: 22,
                        ),
                        onPressed: () {
                          setState(() => _editing = true);
                        },
                      )
                    else ...[
                      TextButton(
                        onPressed: () async {
                          final ok = await context
                              .read<GroupProvider>()
                              .updateGroup(
                                _group.id,
                                _nameCtrl.text.trim(),
                                _descCtrl.text.trim(),
                              );
                          if (ok) {
                            await _refreshGroupInfo();
                            if (!mounted) return;
                            setState(() {
                              _editing = false;
                            });
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('수정 실패')),
                            );
                          }
                        },

                        child: GestureDetector(
                          child: Icon(
                            Icons.close,
                            color: Colors.white.withOpacity(0.8),
                            size: 22,
                          ),
                          onTap: () {
                            setState(() {
                              _editing = false;
                              _nameCtrl.text = _group.name;
                              _descCtrl.text = _group.description;
                            });
                          },
                        ),
                      ),
                      GestureDetector(
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 22,
                        ),
                        onTap: () async {
                          final ok = await context
                              .read<GroupProvider>()
                              .updateGroup(
                                _group.id,
                                _nameCtrl.text.trim(),
                                _descCtrl.text.trim(),
                              );
                          if (!mounted) return;
                          if (ok) {
                            await _refreshGroupInfo();
                            setState(() => _editing = false);
                            FocusScope.of(context).unfocus();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('수정 실패')),
                            );
                          }
                        },
                      ),
                      SizedBox(width: 16),
                    ],
                  ],
                  floating: true,
                ),
                // 상단: 이름/설명 카드
                SliverToBoxAdapter(child: _headerCard()),

                // 하단: 멤버 리스트(원형 아래쪽)
                SliverToBoxAdapter(child: _membersSection()),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: Hero(
                tag: widget.heroTag ?? 'group-${_group.id}',
                flightShuttleBuilder: (
                  context,
                  animation,
                  direction,
                  from,
                  to,
                ) {
                  return SizedBox(
                    width: 300,
                    height: 300,
                    child: ClipOval(child: _buildCircleVisual(size: 300)),
                  );
                },
                child: _buildCircleVisual(size: 300),
              ),
            ),
            SizedBox(height: 15),
            _editing
                ? TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '그룹 이름',
                    hintStyle: const TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  minLines: 1,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                )
                : Text(
                  _group.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            const SizedBox(height: 6),
            _editing
                ? TextField(
                  controller: _descCtrl,
                  maxLines: null,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '그룹 소개',
                    hintStyle: const TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  minLines: 1,
                )
                : Text(
                  _group.description.isNotEmpty
                      ? _group.description
                      : '설명이 없습니다',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 16,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _membersSection() {
    final prov = context.watch<GroupProvider>();
    final List<GroupMember> members = prov.membersOf(_group.id);
    final List<GroupMember> data = members;
    final me = context.read<AuthProvider?>();
    final bool isOwner = _group.ownerId == (me?.username ?? '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              if (isOwner)
                IconButton(
                  onPressed: _showAddMemberSheet,
                  icon: const Icon(Icons.add, color: Colors.white),

                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              if (index >= data.length) return const SizedBox.shrink();
              final m = data[index];
              return _MemberRow(
                member: m,
                removable: isOwner && m.userId != _group.ownerId,
                onRemove: () => _confirmRemoveMember(m.userId),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: data.length,
          ),
        ],
      ),
    );
  }

  // 더미 데이터는 GroupService 확장에서 공급합니다.

  // 이미지 뷰어는 현재 사용되지 않습니다(추후 대표 이미지 연동 시 복구).

  Future<void> _showAddMemberSheet() async {
    final friendProv = context.read<FriendProvider>();
    await friendProv.fetchAllFriendData();

    final groupProv = context.read<GroupProvider>();
    final currentMembers =
        groupProv.membersOf(_group.id).map((m) => m.userId).toSet();
    final allFriends = friendProv.acceptedFriends;

    List<String> selected = [];
    String query = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List filtered =
                allFriends
                    .where((f) => !currentMembers.contains(f.username))
                    .where(
                      (f) =>
                          f.username.toLowerCase().contains(
                            query.toLowerCase(),
                          ) ||
                          (f.alias ?? '').toLowerCase().contains(
                            query.toLowerCase(),
                          ),
                    )
                    .toList();

            return FractionallySizedBox(
              heightFactor: 0.8,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  left: 16,
                  right: 16,
                  top: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '멤버 추가',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: '내 친구 검색',
                        hintStyle: TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Color(0xFF2C2C2E),
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        prefixIcon: Icon(Icons.search, color: Colors.white70),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (v) => setModalState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder:
                            (_, __) => const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final f = filtered[index];
                          final bool isSelected = selected.contains(f.username);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  Theme.of(context).colorScheme.surfaceVariant,
                              backgroundImage:
                                  (f.profileImageUrl?.isNotEmpty ?? false)
                                      ? NetworkImage(f.profileImageUrl!)
                                      : null,
                              child:
                                  (f.profileImageUrl?.isNotEmpty ?? false)
                                      ? null
                                      : const Icon(
                                        Icons.person,
                                        color: Colors.white70,
                                      ),
                            ),
                            title: Text(
                              f.alias ?? f.username,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '@${f.username}',
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (v) {
                                setModalState(() {
                                  if (v == true) {
                                    selected.add(f.username);
                                  } else {
                                    selected.remove(f.username);
                                  }
                                });
                              },
                            ),
                            onTap: () {
                              setModalState(() {
                                if (isSelected) {
                                  selected.remove(f.username);
                                } else {
                                  selected.add(f.username);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            selected.isEmpty
                                ? null
                                : () =>
                                    Navigator.pop(context, selected.join(',')),
                        child: Text('추가 (${selected.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((value) async {
      if (value is String && value.isNotEmpty) {
        final usernames = value.split(',');
        bool allOk = true;
        for (final u in usernames) {
          final ok = await context.read<GroupProvider>().addMember(
            _group.id,
            u,
          );
          allOk = allOk && ok;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(allOk ? '멤버가 추가되었습니다' : '일부 추가 실패')),
        );
      }
    });
  }

  Future<void> _confirmRemoveMember(String userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text('멤버 제거', style: TextStyle(color: Colors.white)),
          content: Text(
            '이 멤버를 제거할까요? (ID: $userId)',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('제거'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      final success = await context.read<GroupProvider>().removeMember(
        _group.id,
        userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '멤버가 제거되었습니다' : '제거 실패')),
      );
    }
  }

  // 공유된 글 섹션은 임시로 제거되었습니다.
}

// (미사용) 필요 시 제스처 카드 위젯을 추가로 정의하세요.

// 수평 아바타 뷰는 현재 미사용입니다(세로 리스트로 대체).

class _MemberRow extends StatelessWidget {
  final GroupMember member;
  final bool removable;
  final VoidCallback? onRemove;

  const _MemberRow({
    required this.member,
    this.removable = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: ClipOval(
            child:
                member.profileImageUrl != null &&
                        member.profileImageUrl!.isNotEmpty
                    ? Image.network(
                      member.profileImageUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      cacheHeight: 120,
                      filterQuality: FilterQuality.low,
                    )
                    : Container(
                      color: Colors.white,
                      child: const Icon(Icons.person, color: Colors.black54),
                    ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.displayName.isNotEmpty
                    ? member.displayName
                    : member.userId,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '@${member.userId}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (removable)
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white70,
              size: 18,
            ),
            onPressed: onRemove,
          ),
      ],
    );
  }
}
