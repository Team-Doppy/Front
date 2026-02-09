import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_text_styles.dart';

/// 통일된 유저 검색 칩 위젯 (search_screen 디자인 기반)
class MilitaryUserSearchChip extends StatelessWidget {
  final String username;
  final String? alias;
  final String? profileImageUrl;
  final UserType? userType; // 역할 (곰신, 군인, 가족, 친구)
  final bool isSelected;
  final String? avatarHeroTag; // ✅ 아바타만 Hero로 연결
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  const MilitaryUserSearchChip({
    super.key,
    required this.username,
    this.alias,
    this.profileImageUrl,
    this.userType,
    this.isSelected = false,
    this.avatarHeroTag,
    this.onTap,
    this.onAdd,
    this.onRemove,
    this.showRemoveButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = alias?.isNotEmpty == true ? alias! : username;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 프로필 아바타
            (avatarHeroTag != null)
                ? Hero(
                  tag: avatarHeroTag!,
                  child: Material(
                    color: Colors.transparent,
                    child: CommonProfileAvatar(
                      imageUrl: profileImageUrl,
                      username: username,
                      size: 60.0,
                      backgroundColor:
                          profileImageUrl == null || profileImageUrl!.isEmpty
                              ? (Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Colors.grey[100]
                                  : Colors.black)
                              : null,
                      borderColor: Colors.transparent,
                      borderWidth: 0,
                    ),
                  ),
                )
                : CommonProfileAvatar(
                  imageUrl: profileImageUrl,
                  username: username,
                  size: 60.0,
                  backgroundColor:
                      profileImageUrl == null || profileImageUrl!.isEmpty
                          ? (Theme.of(context).brightness == Brightness.light
                              ? Colors.grey[100]
                              : Colors.black)
                          : null,
                  borderColor: colorScheme.surface,
                  borderWidth: 0,
                ),
            const SizedBox(width: 16),
            // 사용자 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 별명 또는 username
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // username과 역할
                  Row(
                    children: [
                      Text(
                        '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),

                      // 역할 표시 (곰신, 군인, 가족, 친구) - 기본값: 친구
                    ],
                  ),
                ],
              ),
            ),
            // 역할 배지 (role이 null이면 표시하지 않음)
            if (userType != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    userType!.displayName,
                    style: LocaleTypography.setStyle(
                      context: context,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
