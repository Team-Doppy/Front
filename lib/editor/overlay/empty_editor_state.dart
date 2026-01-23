import 'package:flutter/material.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

/// 🎯 에디터가 비어있을 때 표시하는 빈 상태 UI
/// 댓글 빈 상태 UI와 비슷한 스타일
class EmptyEditorState extends StatelessWidget {
  const EmptyEditorState({
    super.key,
    this.onTap,
    this.customMessage, // 🎯 커스텀 메시지 (온보딩용)
  });

  final VoidCallback? onTap;
  final String? customMessage; // 🎯 커스텀 메시지 (null이면 기본 메시지 사용)

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUser;
    final profileImageUrl = currentUser?.profileImageUrl;
    final alias = currentUser?.alias ?? '';
    final username = currentUser?.username ?? ''; // CommonProfileAvatar용으로 유지
    final hasProfileImage =
        profileImageUrl != null && profileImageUrl.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              hasProfileImage
                  ? CommonProfileAvatar(
                    imageUrl: profileImageUrl,
                    username: username,
                    size: 120,
                    borderWidth: 1.5,
                  )
                  : Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        alias.isNotEmpty
                            ? alias[0].toUpperCase()
                            : (username.isNotEmpty
                                ? username[0].toUpperCase()
                                : '?'),
                        style: TextStyle(
                          fontSize: 24,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.45),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
              Text(
                context.tr('tap_to_start_writing'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('tap_to_start_writing_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onBackground.withOpacity(0.8),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
