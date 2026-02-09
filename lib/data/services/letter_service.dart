import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/base_api_service.dart';

class LetterService {
  static final LetterService _instance = LetterService._internal();
  factory LetterService() => _instance;
  LetterService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 최근 받은 편지 조회 (최근 7일간)
  /// GET /api/letters/recent
  Future<Map<String, dynamic>> getRecentLetters({String? region}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (region != null) {
        queryParams['region'] = region;
      }

      debugPrint('[LetterService] 최근 편지 조회 요청: region=$region');
      final response = await _dio.get(
        '/api/letters/recent',
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      debugPrint('[LetterService] 최근 편지 조회 응답 상태: ${response.statusCode}');
      debugPrint('[LetterService] 최근 편지 조회 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;
        // 응답 형식: { "success": true, "data": { "letters": [...] } }
        if (decoded is Map<String, dynamic> && decoded['success'] == true) {
          return decoded['data'] as Map<String, dynamic>;
        }
        return decoded as Map<String, dynamic>;
      }
      throw Exception('최근 편지 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        debugPrint('[LetterService] 최근 편지 조회 DioException:');
        debugPrint('  - Status Code: ${e.response?.statusCode}');
        debugPrint('  - Response Data: ${e.response?.data}');
        debugPrint('  - Message: ${e.message}');
        throw Exception(
          '최근 편지 조회 실패: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      debugPrint('[LetterService] 최근 편지 조회 기타 에러: $e');
      rethrow;
    }
  }

  /// 받은 편지 전체 조회 (페이지네이션)
  /// GET /api/letters/received
  Future<Map<String, dynamic>> getReceivedLetters({
    int page = 0,
    int size = 20,
    String? region,
  }) async {
    try {
      final queryParams = <String, dynamic>{'page': page, 'size': size};
      if (region != null) {
        queryParams['region'] = region;
      }

      debugPrint(
        '[LetterService] 받은 편지 조회 요청: page=$page, size=$size, region=$region',
      );
      final response = await _dio.get(
        '/api/letters/received',
        queryParameters: queryParams,
      );

      debugPrint('[LetterService] 받은 편지 조회 응답 상태: ${response.statusCode}');
      debugPrint('[LetterService] 받은 편지 조회 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;
        // 응답 형식: { "success": true, "data": { "letters": [...], "currentPage": 0, ... } }
        if (decoded is Map<String, dynamic> && decoded['success'] == true) {
          return decoded['data'] as Map<String, dynamic>;
        }
        return decoded as Map<String, dynamic>;
      }
      throw Exception('받은 편지 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        debugPrint('[LetterService] 받은 편지 조회 DioException:');
        debugPrint('  - Status Code: ${e.response?.statusCode}');
        debugPrint('  - Response Data: ${e.response?.data}');
        debugPrint('  - Message: ${e.message}');
        throw Exception(
          '받은 편지 조회 실패: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      debugPrint('[LetterService] 받은 편지 조회 기타 에러: $e');
      rethrow;
    }
  }
}
