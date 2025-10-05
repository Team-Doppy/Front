import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/services/account_manager_service.dart';
import 'package:doppy/data/services/account_context_service.dart';

class RemoveAccountResult {
  final bool isCurrentRemoved;
  final List<AccountInfo> remainingAccounts;

  RemoveAccountResult({
    required this.isCurrentRemoved,
    required this.remainingAccounts,
  });
}

class UserProfileController {
  final BuildContext context;

  UserProfileController(this.context);

  // Global context를 사용하는 정적 메서드
  static Future<bool> switchToAccountGlobal(AccountInfo info) async {
    try {
      return await AccountContextService.applyAccountGlobal(
        username: info.username,
        token: info.token,
        refreshToken: info.refreshToken,
      );
    } catch (e) {
      print('[-] [UserProfileController] switchToAccountGlobal error: $e');
      return false;
    }
  }

  Future<void> checkFriendStatus(String username) async {
    await context.read<FriendProvider>().checkFriendStatus(username);
  }

  Future<void> loadFeed({String? username, required bool force}) async {
    await context.read<ProfileFeedProvider>().loadInitial(
      username: username,
      force: force,
    );
  }

  Future<bool> switchToAccount(AccountInfo info) async {
    // context가 유효한지 확인
    if (!context.mounted) {
      print(
        '[-] [UserProfileController] Context is not mounted, skipping account switch',
      );
      return false;
    }

    final success = await AccountContextService.applyAccount(
      context,
      username: info.username,
      token: info.token,
      refreshToken: info.refreshToken,
    );

    if (success) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    return success;
  }

  Future<RemoveAccountResult> removeAccount(AccountInfo account) async {
    final current = await AccountManagerService.getCurrentAccount();
    final isCurrent = current?.username == account.username;
    await AccountManagerService.removeAccount(account.username);
    final remaining = await AccountManagerService.getAllAccounts();
    return RemoveAccountResult(
      isCurrentRemoved: isCurrent,
      remainingAccounts: remaining,
    );
  }

  Future<bool> deleteProfileImageAndUpdateCache() async {
    final userProvider = context.read<UserProvider>();
    final success = await userProvider.deleteProfileImage();
    if (success) {
      await AccountManagerService.updateCurrentAccount(profileImageUrl: '');
    }
    return success;
  }

  Future<void> updateProfileImageAfterUpload(String imageUrl) async {
    await context.read<UserProvider>().updateProfileImage(imageUrl: imageUrl);
    await AccountManagerService.updateCurrentAccount(profileImageUrl: imageUrl);
  }
}
