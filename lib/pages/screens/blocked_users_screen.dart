import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/data/services/friend_service.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/components/custom_refresh_indicator.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final FriendService _friendService = FriendService();
  final List<Friend> _blockedUsers = [];
  final Set<String> _selectedUsernames = {}; // 🎯 선택된 사용자들
  bool _isLoading = false;
  bool _showShimmer = false; // 🎯 0.7초 이상 로딩 시에만 true
  bool _showEmptyState = false; // 🎯 차단한 사용자가 없을 때 0.7초 후 표시
  bool _isSelectionMode = false; // 🎯 선택 모드 여부
  Timer? _shimmerTimer; // 🎯 shimmer 타이머
  Timer? _emptyStateTimer; // 🎯 empty state 타이머

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  @override
  void dispose() {
    _shimmerTimer?.cancel();
    _emptyStateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBlockedUsers() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _showShimmer = false;
      _showEmptyState = false;
    });

    // 🎯 0.7초 후에도 로딩 중이면 shimmer 표시
    _shimmerTimer?.cancel();
    _shimmerTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _isLoading) {
        setState(() {
          _showShimmer = true;
        });
      }
    });

    try {
      final users = await _friendService.getBlockedUsers();
      _shimmerTimer?.cancel();
      if (mounted) {
        final isEmpty = users.isEmpty;
        setState(() {
          _blockedUsers.clear();
          _blockedUsers.addAll(users);
          _isLoading = false;
          _showShimmer = false;
        });

        // 🎯 차단한 사용자가 없을 때 0.7초 후에 Empty UI 표시
        if (isEmpty) {
          _emptyStateTimer?.cancel();
          _emptyStateTimer = Timer(const Duration(milliseconds: 700), () {
            if (mounted) {
              setState(() {
                _showEmptyState = true;
              });
            }
          });
        } else {
          _emptyStateTimer?.cancel();
          setState(() {
            _showEmptyState = true;
          });
        }
      }
    } catch (e) {
      _shimmerTimer?.cancel();
      _emptyStateTimer?.cancel();
      debugPrint('[BlockedUsersScreen] 차단한 계정 목록 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showShimmer = false;
          _showEmptyState = true;
        });
        ErrorHandler.showError(context, '차단한 계정 목록을 불러올 수 없습니다.');
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadBlockedUsers();
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedUsernames.clear();
      }
    });
  }

  void _toggleSelection(String username) {
    setState(() {
      if (_selectedUsernames.contains(username)) {
        _selectedUsernames.remove(username);
      } else {
        _selectedUsernames.add(username);
      }
      // 선택된 항목이 없으면 선택 모드 해제
      if (_selectedUsernames.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  Future<void> _unblockUser(Friend friend) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await DialogUtils.showConfirmDialog(
      context,
      title: l10n.t('unblock_user_title'),
      message: l10n
          .t('unblock_user_message')
          .replaceAll(
            '{name}',
            friend.alias.isNotEmpty ? friend.alias : friend.username,
          ),
      confirmText: l10n.t('unblock_user'),
      cancelText: l10n.t('cancel'),
      isDestructive: false,
    );

    if (confirm != true || !mounted) return;

    try {
      // 🎯 단일 차단 해제도 배치 엔드포인트 사용
      final message = await _friendService.unblockUsersBatch([friend.username]);

      // 목록에서 제거
      if (mounted) {
        setState(() {
          _blockedUsers.removeWhere((f) => f.username == friend.username);
        });

        // FriendProvider 상태 업데이트
        final friendProvider = context.read<FriendProvider>();
        await friendProvider.checkFriendStatus(friend.username);

        // ErrorHandler.showInfo로 차단 해제 메시지 표시
        ErrorHandler.showInfo(context, message);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '차단 해제 실패: $e');
      }
    }
  }

  Future<void> _unblockSelected() async {
    if (_selectedUsernames.isEmpty || !mounted) return;

    final l10n = AppLocalizations.of(context);
    final count = _selectedUsernames.length;
    final confirm = await DialogUtils.showConfirmDialog(
      context,
      title: '${count}명 차단 해제',
      message: '${count}명의 차단을 해제하시겠습니까?',
      confirmText: '차단 해제',
      cancelText: l10n.t('cancel'),
      isDestructive: false,
    );

    if (confirm != true || !mounted) return;

    try {
      final usernames = _selectedUsernames.toList();
      final message = await _friendService.unblockUsersBatch(usernames);

      // 목록에서 제거
      if (mounted) {
        setState(() {
          _blockedUsers.removeWhere(
            (f) => _selectedUsernames.contains(f.username),
          );
          _selectedUsernames.clear();
          _isSelectionMode = false;
        });

        // FriendProvider 상태 업데이트 (첫 번째 사용자만)
        if (usernames.isNotEmpty) {
          final friendProvider = context.read<FriendProvider>();
          await friendProvider.checkFriendStatus(usernames.first);
        }

        // ErrorHandler.showInfo로 차단 해제 메시지 표시
        ErrorHandler.showInfo(context, message);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, '차단 해제 실패: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.75),
            size: 24,
          ),
        ),
        title: Text(
          _isSelectionMode && _selectedUsernames.isNotEmpty
              ? '선택됨(${_selectedUsernames.length})'
              : context.tr('blocked_users'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        actions: [
          if (_blockedUsers.isNotEmpty) ...[
            if (!_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _toggleSelectionMode,
                tooltip: '선택',
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
                tooltip: '취소',
              ),
            ],
          ],
        ],
      ),
      bottomNavigationBar:
          _isSelectionMode && _selectedUsernames.isNotEmpty
              ? Container(
                padding: EdgeInsets.only(
                  bottom: 0,
                  top: 0,
                  left: 16,
                  right: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
                      width: 0.5,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _unblockSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.only(top: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        '차단 해제(${_selectedUsernames.length})',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              : null,
      body: CustomRefreshIndicator(
        onRefresh: _onRefresh,
        child:
            _showShimmer && _blockedUsers.isEmpty
                ? ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          ShimmerBox(
                            width: 50,
                            height: 50,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShimmerBox(
                                  width: 120,
                                  height: 16,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                const SizedBox(height: 8),
                                ShimmerBox(
                                  width: 80,
                                  height: 14,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
                : _blockedUsers.isEmpty && _showEmptyState
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.block,
                          size: 64,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('no_blocked_users'),
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                : _blockedUsers.isEmpty
                ? const SizedBox.shrink() // 🎯 0.7초가 지나지 않았으면 아무것도 표시하지 않음
                : RawScrollbar(
                  thumbColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.3),
                  thickness: 4,
                  radius: const Radius.circular(8),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _blockedUsers.length,
                    itemBuilder: (context, index) {
                      final friend = _blockedUsers[index];
                      final isSelected = _selectedUsernames.contains(
                        friend.username,
                      );
                      final hasImage =
                          friend.profileImageUrl != null &&
                          friend.profileImageUrl!.isNotEmpty;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap:
                            _isSelectionMode
                                ? () => _toggleSelection(friend.username)
                                : () {
                                  // User 모델로 변환하여 프로필 화면으로 이동
                                  final user = User(
                                    username: friend.username,
                                    alias: friend.alias,
                                    profileImageUrl: friend.profileImageUrl,
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => UserProfileScreen(
                                            otherUser: user,
                                          ),
                                    ),
                                  );
                                },
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            _toggleSelectionMode();
                            _toggleSelection(friend.username);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          color:
                              isSelected
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                          child: Row(
                            children: [
                              if (_isSelectionMode) ...[
                                if (isSelected) ...[
                                  Icon(
                                    Icons.check,
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    size: 24,
                                  ),
                                ] else ...[
                                  Icon(
                                    Icons.check,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.5),
                                    size: 24,
                                  ),
                                ],
                                const SizedBox(width: 14),
                              ],
                              CommonProfileAvatar(
                                imageUrl: friend.profileImageUrl,
                                username: friend.username,
                                size: 50,
                                borderWidth: hasImage ? 0 : 2,
                                borderColor:
                                    Theme.of(context).colorScheme.surface,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      friend.alias.isNotEmpty
                                          ? friend.alias
                                          : friend.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            isSelected
                                                ? Theme.of(
                                                  context,
                                                ).colorScheme.surface
                                                : Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '@${friend.username}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                            isSelected
                                                ? Theme.of(
                                                  context,
                                                ).colorScheme.surface
                                                : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_isSelectionMode) ...[
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () => _unblockUser(friend),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: Text(
                                    context.tr('unblock_user'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      ),
    );
  }
}
