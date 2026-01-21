import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'base_api_service.dart';

class RecapService {
  final BaseApiService _baseApiService;

  RecapService({BaseApiService? baseApiService})
    : _baseApiService = baseApiService ?? BaseApiService();

  /// 유료 맛보기(InsightContent) 생성
  ///
  /// API: POST /api/insight-content/generate
  Future<Map<String, dynamic>> generate({
    required Map<String, dynamic> postSelection,
    bool forceRegenerate = false,
  }) async {
    final body = <String, dynamic>{
      'postSelection': postSelection,
      'forceRegenerate': forceRegenerate,
    };

    debugPrint('[InsightContentService] POST /api/insight-content/generate');
    debugPrint('[InsightContentService] request: $body');

    try {
      final res = await _baseApiService.dio.post(
        '/api/insight-content/generate',
        data: body,
        options: Options(
          // 오래 걸리는 작업(LLM/분석) 대비
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 3),
        ),
      );

      final data = res.data;
      if (data is Map<String, dynamic>) {
        debugPrint(
          '[InsightContentService] response ${res.statusCode} keys=${data.keys.toList()}',
        );
        // ✅ 400 응답도 정상 응답으로 처리 (success: false 형태로 반환)
        return data;
      }
      debugPrint(
        '[InsightContentService] unexpected response type: ${data.runtimeType}',
      );
      return <String, dynamic>{};
    } catch (e) {
      if (e is DioException) {
        // ✅ 400 응답의 경우 response.data를 반환 (success: false 형태)
        if (e.response?.statusCode == 400) {
          final errorData = e.response?.data;
          if (errorData is Map<String, dynamic>) {
            debugPrint(
              '[InsightContentService] 400 응답 처리: ${errorData.keys.toList()}',
            );
            return errorData;
          }
        }
        debugPrint(
          '[InsightContentService] DioException status=${e.response?.statusCode} body=${e.response?.data}',
        );
        throw HttpException(
          'insight content generate failed ${e.response?.statusCode}: ${e.response?.data}',
        );
      }
      rethrow;
    }
  }
}
