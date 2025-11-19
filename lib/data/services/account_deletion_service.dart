import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doppy/data/services/auth_service.dart';

/// 회원 탈퇴 이유 저장 서비스 (Firebase Firestore)
///
/// ⚠️ 서버 API 호출 없이 Firebase에 직접 저장합니다.
/// userId 대신 username을 사용하여 서버 의존성을 제거했습니다.
class AccountDeletionService {
  static final AccountDeletionService _instance =
      AccountDeletionService._internal();
  factory AccountDeletionService() => _instance;
  AccountDeletionService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  /// 현재 로그인한 사용자 username 가져오기 (서버 API 호출 없음)
  Future<String?> _getCurrentUsername() async {
    try {
      final username = await _authService.getUsername();
      if (username == null || username.isEmpty) {
        print('[AccountDeletionService] 로그인한 사용자가 없습니다');
        return null;
      }
      return username;
    } catch (e) {
      print('[AccountDeletionService] 사용자 username 가져오기 실패: $e');
      return null;
    }
  }

  /// 탈퇴 이유를 Firebase Firestore에 저장 (서버 API 호출 없음)
  /// - [reason] 탈퇴 이유 키 (예: 'not_useful', 'privacy', 'other' 등)
  /// - [reasonText] 탈퇴 이유 텍스트
  /// - [detail] 상세 설명 (기타 선택 시 필수)
  Future<void> saveDeletionReason({
    required String reason,
    required String reasonText,
    String? detail,
  }) async {
    try {
      // 현재 로그인한 사용자 username (서버 API 호출 없음)
      final username = await _getCurrentUsername();
      if (username == null || username.isEmpty) {
        throw Exception('로그인한 사용자 정보를 가져올 수 없습니다');
      }

      final now = DateTime.now().toUtc();

      // Firestore에 탈퇴 이유 저장 (username 사용, 서버 API 호출 없음)
      final deletionData = <String, dynamic>{
        'username': username, // userId 대신 username 사용
        'reason': reason, // 탈퇴 이유 키
        'reasonText': reasonText, // 탈퇴 이유 텍스트
        if (detail != null && detail.trim().isNotEmpty)
          'detail': detail.trim(), // 상세 설명 (기타 선택 시)
        'deletedAt': Timestamp.fromDate(now),
        'createdAt': Timestamp.fromDate(now),
      };

      await _firestore.collection('account_deletions').add(deletionData);

      print(
        '[AccountDeletionService] ✅ 탈퇴 이유 Firestore 저장 성공: username=$username, reason=$reason',
      );
    } catch (e) {
      print('[AccountDeletionService] ❌ 탈퇴 이유 저장 실패: $e');
      throw Exception('탈퇴 이유 저장 실패: ${e.toString()}');
    }
  }
}
