import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doppy/data/services/auth_service.dart';

/// 신고 사유 enum
enum ReportReason {
  spam('SPAM'), // 스팸
  inappropriateContent('INAPPROPRIATE_CONTENT'), // 부적절한 내용
  harassment('HARASSMENT'), // 괴롭힘
  fakeAccount('FAKE_ACCOUNT'), // 가짜 계정 (유저 신고만)
  copyrightViolation('COPYRIGHT_VIOLATION'), // 저작권 침해 (글 신고만)
  other('OTHER'); // 기타

  final String value;
  const ReportReason(this.value);
}

/// 신고 서비스 (Firebase Firestore 직접 저장)
///
/// ⚠️ 서버 API 호출 없이 Firebase에 직접 저장합니다.
/// userId 대신 username을 사용하여 서버 의존성을 제거했습니다.
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  /// 현재 로그인한 사용자 username 가져오기 (서버 API 호출 없음)
  Future<String?> _getCurrentUsername() async {
    try {
      final username = await _authService.getUsername();
      if (username == null || username.isEmpty) {
        print('[ReportService] 로그인한 사용자가 없습니다');
        return null;
      }
      return username;
    } catch (e) {
      print('[ReportService] 사용자 username 가져오기 실패: $e');
      return null;
    }
  }

  /// 포스트 ID를 숫자로 변환 (가능한 경우)
  int? _parsePostId(String postId) {
    try {
      return int.parse(postId);
    } catch (e) {
      // 숫자가 아니면 해시코드 사용
      return postId.hashCode;
    }
  }

  /// 유저 신고 (Firebase Firestore에 직접 저장, 서버 API 호출 없음)
  /// - [targetUsername] 신고할 사용자명
  /// - [reason] 신고 사유
  /// - [description] 상세 설명 (선택사항)
  Future<void> reportUser({
    required String targetUsername,
    required ReportReason reason,
    String? description,
  }) async {
    try {
      // 현재 로그인한 사용자 username (서버 API 호출 없음)
      final reporterUsername = await _getCurrentUsername();
      if (reporterUsername == null || reporterUsername.isEmpty) {
        throw Exception('로그인한 사용자 정보를 가져올 수 없습니다');
      }

      final now = DateTime.now().toUtc();

      // Firestore에 신고 데이터 저장 (username 사용)
      final reportData = <String, dynamic>{
        'reporterUsername': reporterUsername, // userId 대신 username 사용
        'reportedUsername': targetUsername, // userId 대신 username 사용
        'targetType': 'USER',
        'reason': reason.value,
        'description': description?.trim() ?? '',
        'status': 'PENDING',
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      await _firestore.collection('reports').add(reportData);

      print(
        '[ReportService] ✅ 유저 신고 Firestore 저장 성공: $targetUsername (reporter: $reporterUsername)',
      );
    } catch (e) {
      print('[ReportService] ❌ 유저 신고 실패: $e');
      throw Exception('유저 신고 실패: ${e.toString()}');
    }
  }

  /// 글 신고 (Firebase Firestore에 직접 저장, 서버 API 호출 없음)
  /// - [postId] 신고할 포스트 ID
  /// - [reason] 신고 사유
  /// - [description] 상세 설명 (선택사항)
  /// - [authorUsername] 포스트 작성자 username (선택사항)
  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String? description,
    String? authorUsername,
  }) async {
    try {
      // 현재 로그인한 사용자 username (서버 API 호출 없음)
      final reporterUsername = await _getCurrentUsername();
      if (reporterUsername == null || reporterUsername.isEmpty) {
        throw Exception('로그인한 사용자 정보를 가져올 수 없습니다');
      }

      // 포스트 ID를 숫자로 변환 (문자열도 저장 가능)
      final targetId = _parsePostId(postId);
      if (targetId == null) {
        throw Exception('포스트 ID를 파싱할 수 없습니다: $postId');
      }

      final now = DateTime.now().toUtc();

      // Firestore에 신고 데이터 저장 (username 사용, 서버 API 호출 없음)
      final reportData = <String, dynamic>{
        'reporterUsername': reporterUsername, // userId 대신 username 사용
        if (authorUsername != null && authorUsername.isNotEmpty)
          'authorUsername': authorUsername, // 포스트 작성자 username (있는 경우)
        'postId': postId, // 원본 postId 문자열도 저장
        'targetId': targetId, // 파싱된 숫자 ID
        'targetType': 'POST',
        'reason': reason.value,
        'description': description?.trim() ?? '',
        'status': 'PENDING',
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      await _firestore.collection('reports').add(reportData);

      print(
        '[ReportService] ✅ 글 신고 Firestore 저장 성공: $postId (reporter: $reporterUsername, author: $authorUsername)',
      );
    } catch (e) {
      print('[ReportService] ❌ 글 신고 실패: $e');
      throw Exception('글 신고 실패: ${e.toString()}');
    }
  }
}
