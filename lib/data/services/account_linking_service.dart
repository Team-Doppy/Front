import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/data/services/account_manager_service.dart';

/// 계정 연동 서버 API 서비스
class AccountLinkingService {
  static final AccountLinkingService _instance =
      AccountLinkingService._internal();
  factory AccountLinkingService() => _instance;
  AccountLinkingService._internal();

  final String _baseUrl = ApiServiceBase.baseUrl;

  /// 서버에 계정 연동 정보 동기화
  /// 현재 로컬에 저장된 모든 계정 정보를 서버에 전송
  Future<bool> syncAccountsToServer() async {
    try {
      final accounts = await AccountManagerService.getAllAccounts();
      final currentAccount = await AccountManagerService.getCurrentAccount();

      if (accounts.isEmpty) {
        print('[AccountLinkingService] No accounts to sync');
        return true;
      }

      final token = await AuthService().getToken();
      if (token == null) {
        print('[AccountLinkingService] No auth token available');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/account/sync');
      final body = {
        'accounts':
            accounts
                .map(
                  (account) => {
                    'username': account.username,
                    'alias': account.alias,
                    'profileImageUrl': account.profileImageUrl,
                    'accessToken': account.token,
                    'refreshToken': account.refreshToken,
                    'isCurrent': account.username == currentAccount?.username,
                  },
                )
                .toList(),
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        print(
          '[AccountLinkingService] Successfully synced ${accounts.length} accounts to server',
        );
        return true;
      } else {
        print(
          '[AccountLinkingService] Failed to sync accounts: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print('[AccountLinkingService] Error syncing accounts: $e');
      return false;
    }
  }

  /// 서버에서 계정 연동 정보 가져오기
  /// 서버에 저장된 계정 정보를 로컬로 동기화
  Future<bool> syncAccountsFromServer() async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('[AccountLinkingService] No auth token available');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/account/sync');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final accountsData = jsonDecode(response.body) as List<dynamic>;

        // 서버에서 받은 계정 정보를 로컬에 저장
        for (final accountData in accountsData) {
          final accountInfo = AccountInfo(
            username: accountData['username'],
            alias: accountData['alias'] ?? '',
            profileImageUrl: accountData['profileImageUrl'] ?? '',
            token: accountData['accessToken'] ?? '',
            refreshToken: accountData['refreshToken'] ?? '',
          );

          await AccountManagerService.addAccount(
            accountInfo,
            syncToServer: false,
          );

          // 현재 계정 설정
          if (accountData['isCurrent'] == true) {
            await AccountManagerService.setCurrentAccount(
              accountInfo.username,
              syncToServer: false,
            );
          }
        }

        print(
          '[AccountLinkingService] Successfully synced ${accountsData.length} accounts from server',
        );
        return true;
      } else {
        print(
          '[AccountLinkingService] Failed to sync accounts from server: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print('[AccountLinkingService] Error syncing accounts from server: $e');
      return false;
    }
  }

  /// 서버에 계정 추가 알림
  /// 새로운 계정이 연동될 때 서버에 알림
  Future<bool> notifyAccountAdded(AccountInfo accountInfo) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('[AccountLinkingService] No auth token available');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/account/add');
      final body = {
        'username': accountInfo.username,
        'alias': accountInfo.alias,
        'profileImageUrl': accountInfo.profileImageUrl,
        'accessToken': accountInfo.token,
        'refreshToken': accountInfo.refreshToken,
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        print(
          '[AccountLinkingService] Successfully notified server about account addition: ${accountInfo.username}',
        );
        return true;
      } else {
        print(
          '[AccountLinkingService] Failed to notify account addition: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print('[AccountLinkingService] Error notifying account addition: $e');
      return false;
    }
  }

  /// 서버에 계정 제거 알림
  /// 계정이 연동 해제될 때 서버에 알림
  Future<bool> notifyAccountRemoved(String username) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('[AccountLinkingService] No auth token available');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/account/remove');
      final body = {'username': username};

      final response = await http.delete(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        print(
          '[AccountLinkingService] Successfully notified server about account removal: $username',
        );
        return true;
      } else {
        print(
          '[AccountLinkingService] Failed to notify account removal: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print('[AccountLinkingService] Error notifying account removal: $e');
      return false;
    }
  }

  /// 서버에 현재 계정 변경 알림
  /// 활성 계정이 변경될 때 서버에 알림
  Future<bool> notifyCurrentAccountChanged(String username) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('[AccountLinkingService] No auth token available');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/account/current');
      final body = {'username': username};

      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        print(
          '[AccountLinkingService] Successfully notified server about current account change: $username',
        );
        return true;
      } else {
        print(
          '[AccountLinkingService] Failed to notify current account change: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print(
        '[AccountLinkingService] Error notifying current account change: $e',
      );
      return false;
    }
  }

  /// 서버에 계정 정보 업데이트 알림
  /// 계정의 프로필 정보가 변경될 때 서버에 알림
  Future<bool> notifyAccountUpdated(AccountInfo accountInfo) async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('[AccountLinkingService] No auth token available');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/account/update');
      final body = {
        'username': accountInfo.username,
        'alias': accountInfo.alias,
        'profileImageUrl': accountInfo.profileImageUrl,
      };

      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        print(
          '[AccountLinkingService] Successfully notified server about account update: ${accountInfo.username}',
        );
        return true;
      } else {
        print(
          '[AccountLinkingService] Failed to notify account update: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print('[AccountLinkingService] Error notifying account update: $e');
      return false;
    }
  }

  /// 서버에서 계정 연동 상태 확인
  /// 서버와 로컬 계정 정보가 동기화되어 있는지 확인
  Future<bool> checkAccountSyncStatus() async {
    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('[AccountLinkingService] No auth token available');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/account/status');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverAccountCount = data['linkedAccountCount'] as int;
        final localAccountCount = await AccountManagerService.getAccountCount();

        final isSynced = serverAccountCount == localAccountCount;
        print(
          '[AccountLinkingService] Account sync status: Server=$serverAccountCount, Local=$localAccountCount, Synced=$isSynced',
        );

        return isSynced;
      } else {
        print(
          '[AccountLinkingService] Failed to check sync status: ${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print('[AccountLinkingService] Error checking sync status: $e');
      return false;
    }
  }

  /// 전체 계정 동기화 (양방향)
  /// 서버와 로컬 간의 계정 정보를 완전히 동기화
  Future<bool> fullAccountSync() async {
    try {
      print('[AccountLinkingService] Starting full account sync...');

      // 1. 서버에서 계정 정보 가져오기
      final syncFromServer = await syncAccountsFromServer();
      if (!syncFromServer) {
        print(
          '[AccountLinkingService] Failed to sync from server, trying to sync to server...',
        );
        // 서버 동기화 실패 시 로컬 정보를 서버로 전송
        return await syncAccountsToServer();
      }

      // 2. 로컬 정보를 서버로 동기화 (최신 정보 반영)
      final syncToServer = await syncAccountsToServer();

      print(
        '[AccountLinkingService] Full account sync completed: FromServer=$syncFromServer, ToServer=$syncToServer',
      );
      return syncFromServer && syncToServer;
    } catch (e) {
      print('[AccountLinkingService] Error during full account sync: $e');
      return false;
    }
  }
}
