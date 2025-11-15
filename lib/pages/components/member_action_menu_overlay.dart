import 'dart:ui' as ui;
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/group_model.dart';
import '../../providers/group_provider.dart';

// 🎯 고급스러운 멤버 액션 메뉴 오버레이
class MemberActionMenuOverlay extends StatelessWidget {
  final String username;
  final String? profileImageUrl;
  final Group? selectedGroup;
  final Animation<double> animation;

  const MemberActionMenuOverlay({
    Key? key,
    required this.username,
    required this.profileImageUrl,
    required this.selectedGroup,
    required this.animation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color:
                Theme.of(context).colorScheme.brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.black.withOpacity(0.5),
            child: Center(
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(
                  opacity: animation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 🎯 프로필 이미지
                      Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.surface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          border: Border.all(color: Colors.white, width: 0.5),
                        ),
                        child: ClipOval(
                          child: CommonProfileAvatar(
                            imageUrl: profileImageUrl,
                            username: username,
                            size: 240,
                            borderWidth: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 사용자 이름
                      Text(
                        username,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // 🎯 액션 버튼들
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 60),
                        decoration: BoxDecoration(
                          color: AppColors.darkSurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 프로필 방문
                            _buildActionButton(
                              context,
                              icon: Icons.person,
                              label: context.tr('visit_profile'),
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => UserProfileScreen(
                                          otherUser: User(username: username),
                                        ),
                                  ),
                                );
                              },
                            ),
                            // 구분선
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: AppColors.lightBorder.withOpacity(0.2),
                            ),
                            // 그룹에서 제거
                            _buildActionButton(
                              context,
                              icon: Icons.person_remove_outlined,
                              label: context.tr('remove_from_group'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _removeMemberFromGroup(
                                  context,
                                  username,
                                  selectedGroup,
                                );
                              },
                              isDestructive: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    isDestructive
                        ? Theme.of(context).colorScheme.error
                        : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🎯 그룹에서 멤버 제거
  static Future<void> _removeMemberFromGroup(
    BuildContext context,
    String username,
    Group? selectedGroup,
  ) async {
    if (selectedGroup == null || selectedGroup.id == -1) return;

    final groupProv = context.read<GroupProvider>();

    try {
      await groupProv.removeMember(selectedGroup.id, username);

      if (context.mounted) {
        ErrorHandler.showInfo(
          context,
          context
              .tr('member_removed_from_group')
              .replaceAll('{username}', username),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showError(context, context.tr('remove_member_failed'));
      }
    }
  }
}
