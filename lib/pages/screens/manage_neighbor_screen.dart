import 'package:doppy/providers/group_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friend_provider.dart';
import '../../data/models/friend_model.dart';
import 'manage_group_screen.dart';
import '../../data/models/user_model.dart';
import 'user_profile_screen.dart';
import '../components/shimmer_box.dart';

// 이웃 관리 화면 메인 위젯
class ManageNeighborScreen extends StatefulWidget {
  final int initialTabIndex; // 0: 이웃, 1: 그룹
  const ManageNeighborScreen({Key? key, this.initialTabIndex = 0})
    : super(key: key);

  @override
  State<ManageNeighborScreen> createState() => _ManageNeighborScreenState();
}

class _ManageNeighborScreenState extends State<ManageNeighborScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FriendProvider>().fetchAllFriendData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friendProv = context.watch<FriendProvider>();
    final List<Friend> friends = friendProv.acceptedFriends;
    final bool loading = friendProv.isLoading;

    // 로컬 필터링
    final lower = _query.trim().toLowerCase();
    final filtered =
        lower.isEmpty
            ? friends
            : friends
                .where((f) => f.username.toLowerCase().contains(lower))
                .toList();

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).colorScheme.background,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: MediaQuery.of(context).size.width - 70,
                child: _SearchField(
                  controller: _searchController,
                  onChanged: (q) => setState(() => _query = q),
                  onSubmitted: (q) => setState(() => _query = q),
                  onClear:
                      () => setState(() {
                        _searchController.clear();
                        _query = '';
                      }),
                ),
              ),
            ],
          ),
          centerTitle: false,
        ),

        body: TabBarView(
          children: [
            // 이웃 탭
            loading
                ? const _ShimmerNeighbors()
                : RefreshIndicator(
                  onRefresh:
                      () => context.read<FriendProvider>().fetchAllFriendData(),
                  child: Builder(
                    builder: (context) {
                      final received = friendProv.receivedRequests;
                      final sent = friendProv.sentRequests;
                      final List<dynamic> items = [];
                      if (received.isNotEmpty) {
                        items.add('title:받은 요청');
                        for (final f in received) {
                          items.add({'type': 'recv', 'friend': f});
                        }
                      }
                      if (sent.isNotEmpty) {
                        if (items.isNotEmpty) items.add('divider');
                        items.add('title:보낸 요청');
                        for (final f in sent) {
                          items.add({'type': 'sent', 'friend': f});
                        }
                      }
                      if (filtered.isNotEmpty) {
                        if (items.isNotEmpty) items.add('divider');
                        for (final f in filtered) {
                          items.add({'type': 'friend', 'friend': f});
                        }
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                        itemBuilder: (context, index) {
                          final it = items[index];
                          if (it is String) {
                            if (it == 'divider') {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: Divider(
                                  height: 10,
                                  color: Colors.grey.withOpacity(0.4),
                                ),
                              );
                            }
                            if (it.startsWith('title:')) {
                              final t = it.substring('title:'.length);
                              return Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  bottom: 6,
                                  top: 2,
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              );
                            }
                          }
                          final map = it as Map<String, dynamic>;
                          final f = map['friend'] as Friend;
                          final type = map['type'] as String;
                          if (type == 'recv') {
                            return _ReceivedFriendRow(
                              friend: f,
                              onAccept: () async {
                                final ok = await context
                                    .read<FriendProvider>()
                                    .acceptFriendRequestOptimistic(f.username);
                                if (ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('요청을 수락했어요')),
                                  );
                                }
                              },
                            );
                          }
                          if (type == 'sent') {
                            return _PendingFriendRow(
                              friend: f,
                              onCancel: () async {
                                final ok = await context
                                    .read<FriendProvider>()
                                    .cancelSentRequestOptimistic(f.username);
                                if (ok && context.mounted) {
                                  print('요청 취소 성공');
                                }
                              },
                            );
                          }
                          return _FriendRow(
                            friend: f,
                            onDelete: () async {
                              final ok = await context
                                  .read<FriendProvider>()
                                  .deleteFriend(f.username);
                              if (ok && context.mounted) {
                                print('이웃 해제 성공');

                                await context
                                    .read<GroupProvider>()
                                    .fetchMyGroups(forceRefresh: true);
                              }
                            },
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: items.length,
                      );
                    },
                  ),
                ),
            // 그룹 탭: 기존 그룹 관리 UI를 임베드
            ManageGroupScreen(embedded: true, filterText: _query),
          ],
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final Friend friend;
  final VoidCallback? onDelete;

  const _FriendRow({required this.friend, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => UserProfileScreen(
                    otherUser: User(
                      id: 0,
                      username: friend.username,
                      alias: friend.username,
                      profileImageUrl:
                          friend.alias.isNotEmpty &&
                                  friend.alias.startsWith('http')
                              ? friend.alias
                              : null,
                    ),
                  ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Hero(
                tag: 'user-${friend.username}',
                child: ClipOval(
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child:
                        ((friend.profileImageUrl ?? '').isNotEmpty)
                            ? Stack(
                              fit: StackFit.expand,
                              children: [
                                const ShimmerBox(
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                                Image.network(
                                  friend.profileImageUrl!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (ctx, child, prog) {
                                    if (prog == null) return child;
                                    return const ShimmerBox(
                                      width: double.infinity,
                                      height: double.infinity,
                                    );
                                  },
                                  errorBuilder:
                                      (_, __, ___) => Icon(
                                        Icons.person,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            )
                            : Icon(
                              Icons.person,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.username,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '이웃됨 • ${friend.createdAt.year}.${friend.createdAt.month.toString().padLeft(2, '0')}.${friend.createdAt.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).textTheme.bodySmall?.color?.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: Colors.grey.withOpacity(0.8),
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder:
                        (_) => Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SafeArea(
                            child: Wrap(
                              children: [
                                const SizedBox(height: 22),
                                ListTile(
                                  leading: const Icon(
                                    Icons.remove,
                                    color: Colors.redAccent,
                                  ),
                                  title: const Text(
                                    '이웃을 해제할게요',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    onDelete?.call();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<String>(
      data: friend.username,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 32,
          ),
          child: Opacity(opacity: 0.9, child: content),
        ),
      ),
      dragAnchorStrategy: childDragAnchorStrategy,
      onDragStarted: () {
        final TabController c = DefaultTabController.of(context);
        c.animateTo(1);
      },
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: dragginFeedback(context, friend),
      ),
      child: content,
    );
  }
}

class _ReceivedFriendRow extends StatelessWidget {
  final Friend friend;
  final VoidCallback onAccept;
  const _ReceivedFriendRow({required this.friend, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return _ProfileRow(
      friend: friend,
      trailing: TextButton(
        onPressed: onAccept,
        style: TextButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(70, 32),
        ),
        child: Text(
          '수락',
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
        ),
      ),
    );
  }
}

class _PendingFriendRow extends StatelessWidget {
  final Friend friend;
  final VoidCallback onCancel;
  const _PendingFriendRow({required this.friend, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return _ProfileRow(
      friend: friend,
      trailing: TextButton(
        onPressed: onCancel,
        style: TextButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(70, 32),
        ),
        child: Text(
          '취소',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final Friend friend;
  final Widget? trailing;
  const _ProfileRow({required this.friend, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: Hero(
          tag: 'user-${friend.username}',
          child: CircleAvatar(
            radius: 30,
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            foregroundImage:
                (friend.profileImageUrl ?? '').isNotEmpty
                    ? NetworkImage(friend.profileImageUrl!)
                    : null,
            child: Icon(
              Icons.person,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        title: Hero(
          tag: 'user-name-${friend.username}',
          transitionOnUserGestures: true,
          child: Material(
            type: MaterialType.transparency,
            child: Text(
              friend.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => UserProfileScreen(
                    otherUser: User(
                      id: 0,
                      username: friend.username,
                      alias: friend.username,
                      profileImageUrl:
                          (friend.profileImageUrl ?? '').isNotEmpty
                              ? friend.profileImageUrl
                              : null,
                    ),
                  ),
            ),
          );
        },
        trailing: trailing,
      ),
    );
  }
}

Widget dragginFeedback(BuildContext context, Friend friend) {
  return Material(
    color: Colors.transparent,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 32,
      ),
      child: Opacity(
        opacity: 0.9,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  border: Border.all(color: Colors.black12),
                ),
                child: const Icon(Icons.person, color: Colors.black54),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.username,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      friend.alias,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).textTheme.bodySmall?.color?.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SearchField extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  const _SearchField({
    this.controller,
    this.onSubmitted,
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: "친구 검색",
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        prefixIcon: Icon(
          Icons.search,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        suffixIcon:
            controller != null && (controller!.text.isNotEmpty)
                ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onClear,
                )
                : null,
        filled: true,
        fillColor: color.surface,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class _ShimmerNeighbors extends StatelessWidget {
  const _ShimmerNeighbors();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemBuilder: (_, __) {
        return Row(
          children: [
            const ClipOval(child: ShimmerBox(width: 60, height: 60)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(
                    width: 160,
                    height: 14,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  SizedBox(height: 8),
                  ShimmerBox(
                    width: 100,
                    height: 12,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 10,
    );
  }
}
