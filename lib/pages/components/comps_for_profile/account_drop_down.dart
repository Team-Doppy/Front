import 'dart:ui';

import 'package:doppy/data/services/account_manager_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/comps_for_profile/user_profile_controller.dart';
import 'package:doppy/pages/user/join_screen.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountDropDown {
  VoidCallback? _onAccountChanged;

  /// 계정 변경 콜백 설정
  void setOnAccountChanged(VoidCallback? callback) {
    _onAccountChanged = callback;
  }

  /// 계정 드롭다운 표시
  void showAccountDropdown(BuildContext context) async {
    // 현재 사용자 정보 가져오기
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    final displayImageUrl = currentUser?.profileImageUrl ?? '';
    final displayUsername = currentUser?.username ?? '';
    final displayAlias = currentUser?.alias;

    // 연결된 계정 목록 가져오기
    final linkedAccounts = await AccountManagerService.getAllAccounts();
    final currentAccount = await AccountManagerService.getCurrentAccount();

    AccountManagerService.debugPrintAllAccounts();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Stack(
          children: [
            // 배경 터치로 닫기
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            // 드롭다운 컨텐츠
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 0,
              left: 20,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 현재 계정 (헤더)
                          Row(
                            children: [
                              Expanded(
                                child: _buildDropdownItem(
                                  icon: CommonProfileAvatar(
                                    imageUrl: displayImageUrl,
                                    username: displayUsername,
                                    size: 50,
                                    borderColor: Colors.white.withOpacity(0.2),
                                  ),
                                  title: displayUsername,
                                  subtitle: displayAlias ?? displayUsername,
                                  backgroundColor: Colors.white.withOpacity(
                                    0.1,
                                  ),
                                  context: context,
                                  onTap: () {},
                                ),
                              ),
                            ],
                          ),

                          // 구분선
                          Container(
                            height: 1,
                            margin: EdgeInsets.symmetric(horizontal: 16),
                            color: Colors.white.withOpacity(0.1),
                          ),

                          // 연결된 계정 목록 (슬라이드 삭제 가능)
                          ...linkedAccounts
                              .where(
                                (account) =>
                                    account.username !=
                                    currentAccount?.username,
                              )
                              .map(
                                (account) => Dismissible(
                                  key: Key(account.username),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                    ),
                                    child: Text(
                                      '삭제',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    return await _showDeleteConfirmDialog(
                                      context,
                                      account,
                                    );
                                  },
                                  onDismissed: (direction) async {
                                    await _removeAccount(account, context);
                                  },
                                  child: _buildDropdownItem(
                                    icon: CommonProfileAvatar(
                                      imageUrl: account.profileImageUrl,
                                      username: account.username,
                                      size: 50,
                                    ),
                                    title: account.username,
                                    subtitle: account.alias,
                                    context: context,
                                    onTap: () async {
                                      Navigator.of(context).pop();
                                      await _switchToAccount(account, context);
                                    },
                                  ),
                                ),
                              )
                              .toList(),

                          // 계정 관리 버튼
                          _buildDropdownItem(
                            icon: CommonProfileAvatar(
                              imageUrl: null,
                              username: "+",
                              size: 50,
                            ),
                            title: '계정 추가',
                            subtitle: '새 계정 생성 또는 기존 계정 연동',
                            context: context,
                            onTap: () {
                              Navigator.of(context).pop();
                              _showAccountManagementOverlay(context);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 드롭다운 아이템 빌드
  Widget _buildDropdownItem({
    required Widget icon,
    required String title,
    required String subtitle,
    Color? backgroundColor,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return Material(
      color: backgroundColor ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 계정 삭제 확인 다이얼로그
  Future<bool?> _showDeleteConfirmDialog(
    BuildContext context,
    AccountInfo account,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            '계정 삭제',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            '${account.alias} (${account.username}) 계정을 삭제하시겠습니까?\n\n이 작업은 되돌릴 수 없습니다.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                '취소',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(
                '삭제',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 계정 삭제
  Future<void> _removeAccount(AccountInfo account, BuildContext context) async {
    try {
      print('[-] [AccountDropDown] 계정 삭제 시작: ${account.username}');
      final controller = UserProfileController(context);

      final result = await controller.removeAccount(account);
      if (result.isCurrentRemoved) {
        if (result.remainingAccounts.isNotEmpty) {
          await _switchToAccount(result.remainingAccounts.first, context);
        } else {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      }

      print('[-] [AccountDropDown] 계정 삭제 완료: ${account.username}');
    } catch (e) {
      print('[-] [AccountDropDown] _removeAccount error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('계정 삭제에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 계정 전환
  Future<void> _switchToAccount(
    AccountInfo accountInfo,
    BuildContext context,
  ) async {
    try {
      print('[-] [AccountDropDown] 계정 전환 시작: ${accountInfo.username}');

      // Global 메서드 사용 (context 의존성 제거)
      final success = await UserProfileController.switchToAccountGlobal(
        accountInfo,
      );

      if (!success) {
        return;
      }

      // 계정 변경 콜백 호출 (context 체크 없이)
      _onAccountChanged?.call();

      print('[-] [AccountDropDown] 계정 전환 완료: ${accountInfo.username}');
    } catch (e) {
      print('[-] [AccountDropDown] _switchToAccount error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('계정 전환에 실패했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 계정 관리 바텀시트 표시
  void _showAccountManagementOverlay(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // 디버그: 드롭다운 열릴 때 계정 상태 덤프
        AccountManagerService.debugPrintAllAccounts();
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: JoinScreen(isRedirectMode: true),
          ),
        );
      },
    );
  }
}
