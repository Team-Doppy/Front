import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'account_manager_service.dart';
import 'auth_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/profile_feed_provider.dart';
import '../../providers/group_provider.dart';
import 'blog_service.dart';
import '../../main.dart';

class AccountContextService {
  /// 현재 선택된 계정(context 포함)을 애플리케이션 전역 컨텍스트에 적용하고,
  /// 모든 종속 데이터(유저, 친구, 그룹, 피드)를 병렬로 새로고침한다.
  static Future<bool> applyAccount(
    BuildContext context, {
    required String username,
    required String token,
    required String refreshToken,
    bool clearCaches = true,
  }) async {
    // context가 유효한지 먼저 확인
    if (!context.mounted) {
      print(
        '[AccountContextService] Context is not mounted, skipping account apply',
      );
      return false;
    }

    try {
      // 1) 현재 계정 설정 및 토큰 저장
      await AccountManagerService.setCurrentAccount(username);

      final authService = AuthService();
      await authService.saveToken(token);
      await authService.saveRefreshToken(refreshToken);
      await authService.saveUsername(username);

      // 2) 토큰 검증 및 갱신 시도
      print('[AccountContextService] 토큰 검증 및 갱신 시도...');
      final tokenValid = await authService.validateAndRefreshToken();

      if (!tokenValid) {
        print('[AccountContextService] 토큰 갱신 실패, 계정 전환 중단');
        // 해당 계정을 저장된 계정 목록에서 제거 (리프레시 토큰도 만료된 경우)
        await AccountManagerService.removeAccount(username);

        // 로그인 화면으로 이동
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        }
        return false;
      }

      // 3) AuthProvider 상태 갱신
      final authProvider = context.read<AuthProvider>();
      authProvider.updateAuthState(
        isLoggedIn: true,
        token: token,
        username: username,
      );

      // 4) 필요시 캐시/상태 초기화
      final userProvider = context.read<UserProvider>();
      final friendProvider = context.read<FriendProvider>();
      final profileFeedProvider = context.read<ProfileFeedProvider>();
      final groupProvider = context.read<GroupProvider>();

      if (clearCaches) {
        userProvider.logout();
        friendProvider.logout();
        profileFeedProvider.logout();
        groupProvider.logout();
        BlogService.clearAllCache();
      }

      // 5) 병렬로 데이터 로드
      await Future.wait([
        userProvider.fetchMyProfile(),
        friendProvider.fetchAllFriendData(),
        profileFeedProvider.hardRefresh(username: username),
        groupProvider.fetchMyGroups(),
      ]);

      print('[AccountContextService] 계정 전환 성공: $username');
      return true;
    } catch (e) {
      print('[AccountContextService] 계정 전환 실패: $e');

      // 토큰 관련 오류인 경우 로그인 화면으로 이동
      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
      return false;
    }
  }

  /// AccountManager에 저장된 현재 계정 정보를 읽어 동일 절차 수행
  static Future<bool> applyCurrentAccount(BuildContext context) async {
    final current = await AccountManagerService.getCurrentAccount();
    if (current == null) {
      return false;
    }
    return await applyAccount(
      context,
      username: current.username,
      token: current.token,
      refreshToken: current.refreshToken,
    );
  }

  /// Context 없이 계정 전환 (Global NavigatorKey 사용)
  static Future<bool> applyAccountGlobal({
    required String username,
    required String token,
    required String refreshToken,
    bool clearCaches = true,
  }) async {
    try {
      // 1) 현재 계정 설정 및 토큰 저장
      await AccountManagerService.setCurrentAccount(username);

      final authService = AuthService();
      await authService.saveToken(token);
      await authService.saveRefreshToken(refreshToken);
      await authService.saveUsername(username);

      // 2) 토큰 검증 및 갱신 시도
      print('[AccountContextService] 토큰 검증 및 갱신 시도...');
      final tokenValid = await authService.validateAndRefreshToken();

      if (!tokenValid) {
        print('[AccountContextService] 토큰 갱신 실패, 계정 전환 중단');
        // 해당 계정을 저장된 계정 목록에서 제거 (리프레시 토큰도 만료된 경우)
        await AccountManagerService.removeAccount(username);
        return false;
      }

      // 3) Global context를 통해 Provider 상태 갱신
      final globalContext = navigatorKey.currentContext;
      if (globalContext == null || !globalContext.mounted) {
        print('[AccountContextService] Global context is not available');
        return false;
      }

      final authProvider = globalContext.read<AuthProvider>();
      authProvider.updateAuthState(
        isLoggedIn: true,
        token: token,
        username: username,
      );

      // 4) 필요시 캐시/상태 초기화
      final userProvider = globalContext.read<UserProvider>();
      final friendProvider = globalContext.read<FriendProvider>();
      final profileFeedProvider = globalContext.read<ProfileFeedProvider>();
      final groupProvider = globalContext.read<GroupProvider>();

      if (clearCaches) {
        userProvider.logout();
        friendProvider.logout();
        profileFeedProvider.logout();
        groupProvider.logout();
        BlogService.clearAllCache();
      }

      // 5) 병렬로 데이터 로드
      await Future.wait([
        userProvider.fetchMyProfile(),
        friendProvider.fetchAllFriendData(),
        profileFeedProvider.hardRefresh(username: username),
        groupProvider.fetchMyGroups(),
      ]);

      print('[AccountContextService] 계정 전환 성공: $username');
      return true;
    } catch (e) {
      print('[AccountContextService] 계정 전환 실패: $e');
      return false;
    }
  }
}
