import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/profile_action_bottom_sheet.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

/// 🎯 댓글 이모션을 누른 사용자 목록 바텀시트
class CommentReactionUsersBottomSheet extends StatelessWidget {
  final Map<String, dynamic>
  emotionData; // 🎯 {emoji: {count: int, users: List}}
  final String? commentId; // 🎯 댓글 ID (이모지 취소용)
  final Function(String commentId, String emoji)?
  onReactionToggle; // 🎯 이모지 토글 콜백

  const CommentReactionUsersBottomSheet({
    Key? key,
    required this.emotionData,
    this.commentId,
    this.onReactionToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(
                            context,
                          ).translate('reaction_users'),
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                        size: 24,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // 리스트 (모든 사용자를 차례대로 나열)
              Expanded(child: _buildUserList(context, scrollController)),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  /// 🎯 모든 사용자를 하나의 리스트로 합치기
  Widget _buildUserList(
    BuildContext context,
    ScrollController scrollController,
  ) {
    if (emotionData.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            AppLocalizations.of(context).translate('no_reaction_users'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    // 🎯 모든 사용자를 하나의 리스트로 합치기 (중복 제거, 각 사용자가 누른 이모지 정보 포함)
    final userMap = <String, Map<String, dynamic>>{};

    for (final emojiEntry in emotionData.entries) {
      final emoji = emojiEntry.key;
      final data = emojiEntry.value as Map<String, dynamic>;
      final users = data['users'] as List<Map<String, dynamic>>? ?? [];

      for (final user in users) {
        final username = user['username'] as String? ?? '';
        if (username.isEmpty) continue;

        if (userMap.containsKey(username)) {
          // 이미 존재하는 사용자면 이모지 리스트에 추가
          final existingEmojis =
              userMap[username]!['emojis'] as List<String>? ?? [];
          if (!existingEmojis.contains(emoji)) {
            existingEmojis.add(emoji);
            userMap[username]!['emojis'] = existingEmojis;
          }
        } else {
          // 새로운 사용자 추가
          userMap[username] = {
            'username': username,
            'alias': user['alias'],
            'profileImageUrl': user['profileImageUrl'],
            'emojis': [emoji],
          };
        }
      }
    }

    final allUsers = userMap.values.toList();

    if (allUsers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            AppLocalizations.of(context).translate('no_reaction_users'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      itemCount: allUsers.length,
      separatorBuilder:
          (context, index) => Divider(
            height: 1,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
      itemBuilder: (context, index) {
        final user = allUsers[index];
        final emojis = user['emojis'] as List<String>? ?? [];
        // 🎯 첫 번째 이모지만 표시 (여러 개면 첫 번째 것만)
        final primaryEmoji = emojis.isNotEmpty ? emojis.first : null;

        return _UserTile(
          username: user['username'] as String? ?? '',
          alias: user['alias'] as String?,
          profileImageUrl: user['profileImageUrl'] as String?,
          emoji: primaryEmoji,
          emojis: emojis, // 🎯 모든 이모지 정보 전달 (취소용)
          commentId: commentId,
          onReactionToggle: onReactionToggle,
        );
      },
    );
  }
}

/// 🎯 사용자 타일 위젯
class _UserTile extends StatelessWidget {
  final String username;
  final String? alias;
  final String? profileImageUrl;
  final String? commentId; // 🎯 댓글 ID (이모지 취소용)
  final String? emoji; // 🎯 표시할 이모지 (프로필 이미지 오른쪽 하단)
  final List<String>? emojis; // 🎯 사용자가 누른 모든 이모지 (취소용)
  final Function(String commentId, String emoji)?
  onReactionToggle; // 🎯 이모지 토글 콜백

  const _UserTile({
    required this.username,
    this.alias,
    this.profileImageUrl,
    this.commentId,
    this.emoji,
    this.emojis,
    this.onReactionToggle,
  });

  void _showProfileActionSheet(BuildContext context) {
    Navigator.pop(context); // 바텀시트 먼저 닫기
    ProfileActionBottomSheet.show(
      context,
      username: username,
      alias: alias,
      profileImageUrl: profileImageUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<UserProvider>().currentUser;
    final isCurrentUser =
        currentUser != null && currentUser.username == username;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // 프로필 아바타 (이모지 오버레이 포함)
          Stack(
            clipBehavior: Clip.none,
            children: [
              CommonProfileAvatar(
                imageUrl: profileImageUrl ?? '',
                username: username,
                size: 56,
                borderWidth: 0,
              ),
              // 🎯 이모지 오버레이 (오른쪽 하단)
              if (emoji != null)
                Positioned(
                  right: -2.2,
                  bottom: -4,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              if (emoji != null)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 28,
                    height: 28,

                    child: Center(
                      child: Text(emoji!, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),

          // 사용자 정보 (현재 사용자인 경우 전체 영역 클릭 가능)
          Expanded(
            child: GestureDetector(
              // 🎯 현재 사용자인 경우에만 클릭 가능 (취소하려면 누르세요)
              onTap:
                  (isCurrentUser && emojis != null && emojis!.isNotEmpty)
                      ? () {
                        // 🎯 바텀시트 닫기
                        Navigator.pop(context);
                        // 🎯 첫 번째 이모지 반응 취소
                        if (commentId != null && onReactionToggle != null) {
                          onReactionToggle!(commentId!, emojis!.first);
                        }
                      }
                      : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alias?.isNotEmpty == true ? alias! : username,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (alias?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      username,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                  // 🎯 현재 사용자인 경우 "취소하려면 누르세요" 텍스트 표시
                  if (isCurrentUser &&
                      emojis != null &&
                      emojis!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '취소하려면 누르세요',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // more_vert 아이콘 (유저 액션은 여기서만)
          IconButton(
            icon: Icon(
              Icons.more_vert,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showProfileActionSheet(context),
          ),
        ],
      ),
    );
  }
}
