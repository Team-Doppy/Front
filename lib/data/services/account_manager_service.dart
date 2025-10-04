import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 계정 정보 모델
class AccountInfo {
  final String username;
  String alias;
  String profileImageUrl;
  final String token;
  final String refreshToken;

  AccountInfo({
    required this.username,
    required this.alias,
    required this.profileImageUrl,
    required this.token,
    required this.refreshToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'alias': alias,
      'profileImageUrl': profileImageUrl,
      'token': token,
      'refreshToken': refreshToken,
    };
  }

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    return AccountInfo(
      username: json['username'] ?? '',
      alias: json['alias'] ?? '',
      profileImageUrl: json['profileImageUrl'] ?? '',
      token: json['token'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
    );
  }
}

/// 계정 관리 서비스
class AccountManagerService {
  static const String _accountsKey = 'linked_accounts';
  static const String _currentAccountKey = 'current_account';

  /// 모든 연결된 계정 목록 가져오기
  static Future<List<AccountInfo>> getAllAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountsJson = prefs.getStringList(_accountsKey) ?? [];

      return accountsJson.map((jsonString) {
        final json = jsonDecode(jsonString);
        return AccountInfo.fromJson(json);
      }).toList();
    } catch (e) {
      print('[-] [AccountManagerService] getAllAccounts error: $e');
      return [];
    }
  }

  /// 계정 추가 (중복 시 업데이트)
  static Future<bool> addAccount(AccountInfo accountInfo) async {
    try {
      final accounts = await getAllAccounts();

      // 이미 존재하는 계정인지 확인
      final existingIndex = accounts.indexWhere(
        (account) => account.username == accountInfo.username,
      );

      if (existingIndex != -1) {
        // 기존 계정 업데이트
        accounts[existingIndex] = accountInfo;
        print(
          '[-] [AccountManagerService] addAccount updated: ${accountInfo.username}',
        );
      } else {
        // 새 계정 추가
        accounts.add(accountInfo);
        print(
          '[-] [AccountManagerService] addAccount success: ${accountInfo.username}',
        );
      }

      // SharedPreferences에 저장
      final prefs = await SharedPreferences.getInstance();
      final accountsJson =
          accounts.map((account) => jsonEncode(account.toJson())).toList();

      await prefs.setStringList(_accountsKey, accountsJson);

      return true;
    } catch (e) {
      print('[-] [AccountManagerService] addAccount error: $e');
      return false;
    }
  }

  /// 계정 제거
  static Future<bool> removeAccount(String username) async {
    try {
      final accounts = await getAllAccounts();
      accounts.removeWhere((account) => account.username == username);

      final prefs = await SharedPreferences.getInstance();
      final accountsJson =
          accounts.map((account) => jsonEncode(account.toJson())).toList();

      await prefs.setStringList(_accountsKey, accountsJson);

      // 현재 계정이 제거된 계정이라면 현재 계정 정보도 제거
      final currentAccount = await getCurrentAccount();
      if (currentAccount?.username == username) {
        await clearCurrentAccount();
      }

      print('[-] [AccountManagerService] removeAccount success: $username');
      return true;
    } catch (e) {
      print('[-] [AccountManagerService] removeAccount error: $e');
      return false;
    }
  }

  /// 특정 계정 정보 가져오기
  static Future<AccountInfo?> getAccount(String username) async {
    try {
      final accounts = await getAllAccounts();
      return accounts.firstWhere(
        (account) => account.username == username,
        orElse: () => throw Exception('Account not found'),
      );
    } catch (e) {
      print('[-] [AccountManagerService] getAccount error: $e');
      return null;
    }
  }

  /// 현재 활성 계정 설정
  static Future<bool> setCurrentAccount(String username) async {
    try {
      final account = await getAccount(username);
      if (account == null) {
        print(
          '[-] [AccountManagerService] setCurrentAccount: Account not found',
        );
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentAccountKey, jsonEncode(account.toJson()));

      print('[-] [AccountManagerService] setCurrentAccount success: $username');
      return true;
    } catch (e) {
      print('[-] [AccountManagerService] setCurrentAccount error: $e');
      return false;
    }
  }

  /// 현재 활성 계정 정보 가져오기
  static Future<AccountInfo?> getCurrentAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentAccountJson = prefs.getString(_currentAccountKey);

      if (currentAccountJson == null) {
        return null;
      }

      final json = jsonDecode(currentAccountJson);
      return AccountInfo.fromJson(json);
    } catch (e) {
      print('[-] [AccountManagerService] getCurrentAccount error: $e');
      return null;
    }
  }

  /// 현재 계정 정보 업데이트
  static Future<bool> updateCurrentAccount({
    String? profileImageUrl,
    String? alias,
  }) async {
    try {
      final currentAccount = await getCurrentAccount();
      if (currentAccount == null) {
        print(
          '[-] [AccountManagerService] updateCurrentAccount: No current account',
        );
        return false;
      }

      final updatedAccount = AccountInfo(
        username: currentAccount.username,
        alias: alias ?? currentAccount.alias,
        profileImageUrl: profileImageUrl ?? currentAccount.profileImageUrl,
        token: currentAccount.token,
        refreshToken: currentAccount.refreshToken,
      );

      // 계정 목록에서 업데이트
      await addAccount(updatedAccount);

      // 현재 계정도 업데이트
      await setCurrentAccount(updatedAccount.username);

      print('[-] [AccountManagerService] updateCurrentAccount success');
      return true;
    } catch (e) {
      print('[-] [AccountManagerService] updateCurrentAccount error: $e');
      return false;
    }
  }

  /// 현재 계정 토큰 업데이트
  static Future<bool> updateCurrentAccountTokens({
    required String token,
    required String refreshToken,
  }) async {
    try {
      final currentAccount = await getCurrentAccount();
      if (currentAccount == null) {
        print(
          '[-] [AccountManagerService] updateCurrentAccountTokens: No current account',
        );
        return false;
      }

      final updatedAccount = AccountInfo(
        username: currentAccount.username,
        alias: currentAccount.alias,
        profileImageUrl: currentAccount.profileImageUrl,
        token: token,
        refreshToken: refreshToken,
      );

      // 계정 목록에서 업데이트
      await addAccount(updatedAccount);

      // 현재 계정도 업데이트
      await setCurrentAccount(updatedAccount.username);

      print('[-] [AccountManagerService] updateCurrentAccountTokens success');
      return true;
    } catch (e) {
      print('[-] [AccountManagerService] updateCurrentAccountTokens error: $e');
      return false;
    }
  }

  /// 현재 계정 정보 초기화
  static Future<bool> clearCurrentAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_currentAccountKey);

      print('[-] [AccountManagerService] clearCurrentAccount success');
      return true;
    } catch (e) {
      print('[-] [AccountManagerService] clearCurrentAccount error: $e');
      return false;
    }
  }

  /// 모든 계정 정보 초기화
  static Future<bool> clearAllAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accountsKey);
      await prefs.remove(_currentAccountKey);

      print('[-] [AccountManagerService] clearAllAccounts success');
      return true;
    } catch (e) {
      print('[-] [AccountManagerService] clearAllAccounts error: $e');
      return false;
    }
  }

  /// 계정이 존재하는지 확인
  static Future<bool> hasAccount(String username) async {
    try {
      final accounts = await getAllAccounts();
      return accounts.any((account) => account.username == username);
    } catch (e) {
      print('[-] [AccountManagerService] hasAccount error: $e');
      return false;
    }
  }

  /// 연결된 계정 수 가져오기
  static Future<int> getAccountCount() async {
    try {
      final accounts = await getAllAccounts();
      return accounts.length;
    } catch (e) {
      print('[-] [AccountManagerService] getAccountCount error: $e');
      return 0;
    }
  }

  /// 디버그: 현재 저장된 모든 계정 정보를 로그로 출력
  static Future<void> debugPrintAllAccounts() async {
    try {
      final accounts = await getAllAccounts();
      final current = await getCurrentAccount();
      print(
        '===== [AccountManagerService][DEBUG] Linked accounts (${accounts.length}) =====',
      );
      for (int i = 0; i < accounts.length; i++) {
        final a = accounts[i];
        final isCurrent = current?.username == a.username;
        final tokenHead =
            a.token.isNotEmpty
                ? a.token.substring(
                  0,
                  (a.token.length > 12 ? 12 : a.token.length),
                )
                : '';
        final refreshHead =
            a.refreshToken.isNotEmpty
                ? a.refreshToken.substring(
                  0,
                  (a.refreshToken.length > 12 ? 12 : a.refreshToken.length),
                )
                : '';
        print(
          '[$i] username=${a.username}, alias=${a.alias}, imageUrl=${a.profileImageUrl}, token=${tokenHead}..., refresh=${refreshHead}..., current=$isCurrent',
        );
      }
      print('===== [/AccountManagerService][DEBUG] =====');
    } catch (e) {
      print('[-] [AccountManagerService] debugPrintAllAccounts error: $e');
    }
  }
}
