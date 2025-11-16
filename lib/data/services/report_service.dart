import 'package:dio/dio.dart';
import 'base_api_service.dart';

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

/// 신고 서비스
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 유저 신고
  /// - [targetUsername] 신고할 사용자명
  /// - [reason] 신고 사유
  /// - [description] 상세 설명 (선택사항)
  Future<void> reportUser({
    required String targetUsername,
    required ReportReason reason,
    String? description,
  }) async {
    try {
      final data = <String, dynamic>{'reason': reason.value};

      if (description != null && description.trim().isNotEmpty) {
        data['description'] = description.trim();
      }

      final response = await _dio.post(
        '/api/reports/users/$targetUsername',
        data: data,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        print('[ReportService] 유저 신고 성공: $targetUsername');
        return;
      }

      throw Exception('유저 신고 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage =
            e.response?.data?['message']?.toString() ?? '유저 신고 실패: $statusCode';
        print('[ReportService] 유저 신고 실패: $errorMessage');
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }

  /// 글 신고
  /// - [postId] 신고할 포스트 ID
  /// - [reason] 신고 사유
  /// - [description] 상세 설명 (선택사항)
  Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String? description,
  }) async {
    try {
      final data = <String, dynamic>{'reason': reason.value};

      if (description != null && description.trim().isNotEmpty) {
        data['description'] = description.trim();
      }

      final response = await _dio.post(
        '/api/reports/posts/$postId',
        data: data,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        print('[ReportService] 글 신고 성공: $postId');
        return;
      }

      throw Exception('글 신고 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage =
            e.response?.data?['message']?.toString() ?? '글 신고 실패: $statusCode';
        print('[ReportService] 글 신고 실패: $errorMessage');
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }
}
