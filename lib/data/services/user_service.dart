import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'base_api_service.dart';
import '../models/user_model.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 프로필 정보 업데이트 (/api/profile/info)
  Future<void> updateProfileInfo({
    required String alias,
    List<String>? links, // 🎯 프로필 링크 목록
    Map<String, String>? linkTitles, // 🎯 링크 타이틀 (URL -> 타이틀)
    Map<String, String>? linkThumbnails, // 🎯 링크 썸네일 (URL -> thumbnailUrl)
  }) async {
    try {
      final data = <String, dynamic>{'alias': alias};

      // 🎯 links가 null이 아닐 때 항상 추가 (빈 배열도 전달하여 삭제 가능하게)
      if (links != null) {
        data['links'] = links;
      }

      // 🎯 linkTitles가 있으면 추가 (빈 맵도 전달 가능)
      // 단, links에 포함된 URL만 포함하도록 필터링
      if (linkTitles != null && linkTitles.isNotEmpty) {
        final filteredLinkTitles = <String, String>{};
        if (links != null) {
          // links에 포함된 URL만 linkTitles에 포함
          for (final url in links) {
            if (linkTitles.containsKey(url)) {
              filteredLinkTitles[url] = linkTitles[url]!;
            }
          }
        }
        // 필터링된 맵이 비어있지 않을 때만 추가
        if (filteredLinkTitles.isNotEmpty) {
          data['linkTitles'] = filteredLinkTitles;
        }
      }

      // 🎯 linkThumbnails가 있으면 추가 (빈 맵도 전달 가능)
      // 단, links에 포함된 URL만 포함하도록 필터링
      if (linkThumbnails != null && linkThumbnails.isNotEmpty) {
        final filteredLinkThumbnails = <String, String>{};
        if (links != null) {
          // links에 포함된 URL만 linkThumbnails에 포함
          for (final url in links) {
            if (linkThumbnails.containsKey(url)) {
              filteredLinkThumbnails[url] = linkThumbnails[url]!;
            }
          }
        }
        // 필터링된 맵이 비어있지 않을 때만 추가
        if (filteredLinkThumbnails.isNotEmpty) {
          data['linkThumbnails'] = filteredLinkThumbnails;
        }
      }

      debugPrint('[UserService] updateProfileInfo 요청 데이터: $data');
      final response = await _dio.put('/api/profile/info', data: data);
      debugPrint(
        '[UserService] updateProfileInfo 응답 상태: ${response.statusCode}',
      );
      debugPrint('[UserService] updateProfileInfo 응답 데이터: ${response.data}');

      if (response.statusCode != 200) {
        throw Exception('프로필 정보 업데이트 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioException) {
        debugPrint('[UserService] updateProfileInfo DioException:');
        debugPrint('  - Status Code: ${e.response?.statusCode}');
        debugPrint('  - Response Data: ${e.response?.data}');
        debugPrint('  - Request Data: ${e.requestOptions.data}');
        debugPrint('  - Message: ${e.message}');
        throw Exception(
          '프로필 정보 업데이트 실패: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      debugPrint('[UserService] updateProfileInfo 기타 에러: $e');
      rethrow;
    }
  }

  /// 유저 + 세팅 번들 조회 (GET /api/users/bundle)
  Future<Map<String, dynamic>> getUserBundle() async {
    try {
      final response = await _dio.get('/api/users/bundle');
      if (response.statusCode == 200) {
        final decoded = response.data;
        // 일반 Map 또는 { data: {...} } 형태 모두 대응
        if (decoded is Map<String, dynamic>) {
          return decoded['data'] is Map<String, dynamic>
              ? decoded['data'] as Map<String, dynamic>
              : decoded;
        }
        throw Exception('유저 번들 응답 형식 오류: ${decoded.runtimeType}');
      }
      throw Exception('유저 번들 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('유저 번들 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 온보딩 완료 상태 업데이트 (PATCH /api/users/onboarding)
  /// - body: { "onboardingCompleted": true/false }
  /// - 서버 스펙: onboardingCompleted가 없거나 null이면 true로 처리(완료 호출 기준)
  Future<bool?> updateOnboardingCompleted({bool? onboardingCompleted}) async {
    try {
      final response = await _dio.patch(
        '/api/users/onboarding',
        data: <String, dynamic>{'onboardingCompleted': onboardingCompleted},
      );

      if (response.statusCode == 200) {
        final decoded = response.data;
        if (decoded is Map<String, dynamic>) {
          final map =
              decoded['data'] is Map<String, dynamic>
                  ? decoded['data'] as Map<String, dynamic>
                  : decoded;
          final v = map['onboardingCompleted'];
          return v is bool ? v : null;
        }
        throw Exception('온보딩 업데이트 응답 형식 오류: ${decoded.runtimeType}');
      }
      throw Exception('온보딩 업데이트 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('온보딩 업데이트 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 프로필 정보 조회 (/api/profile/info) - 하위 호환성 유지
  Future<User> getMyProfile() async {
    try {
      final response = await _dio.get('/api/profile/info');
      if (response.statusCode == 200) {
        final decoded = response.data;
        // 일반 Map 또는 { data: {...} } 형태 모두 대응
        if (decoded is Map<String, dynamic>) {
          final map =
              decoded['data'] is Map<String, dynamic>
                  ? decoded['data'] as Map<String, dynamic>
                  : decoded;
          return User.fromJson(map);
        }
        throw Exception('프로필 응답 형식 오류: ${decoded.runtimeType}');
      }
      throw Exception('프로필 정보 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('프로필 정보 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 프로필 이미지 삭제 (기본 이미지로 되돌리기)
  Future<void> deleteProfileImage() async {
    try {
      final response = await _dio.delete('/api/profile/image');
      if (response.statusCode != 200) {
        throw Exception('프로필 이미지 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('프로필 이미지 삭제 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 설정 조회
  Future<Map<String, bool>> getSettings() async {
    try {
      debugPrint('[UserService] GET /api/profile/settings');
      final response = await _dio.get('/api/profile/settings');
      if (response.statusCode == 200) {
        final data = response.data;
        return {
          'marketingConsent': data['marketingConsent'] as bool? ?? false,
          'notificationEnabled': data['notificationEnabled'] as bool? ?? true,
        };
      }
      throw Exception('설정 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('설정 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 마케팅 정보 수신 동의 토글
  Future<bool> toggleMarketingConsent() async {
    try {
      debugPrint('[UserService] PUT /api/profile/marketing-consent');
      final response = await _dio.put('/api/profile/marketing-consent');
      if (response.statusCode == 200) {
        final newValue = response.data['marketingConsent'] as bool;
        debugPrint('[UserService] marketingConsent toggled to: $newValue');
        return newValue;
      }
      throw Exception('마케팅 동의 토글 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('마케팅 동의 토글 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 알림 허용 토글
  Future<bool> toggleNotificationEnabled() async {
    try {
      debugPrint('[UserService] PUT /api/profile/notification-enabled');
      final response = await _dio.put('/api/profile/notification-enabled');
      if (response.statusCode == 200) {
        final newValue = response.data['notificationEnabled'] as bool;
        debugPrint('[UserService] notificationEnabled toggled to: $newValue');
        return newValue;
      }
      throw Exception('알림 토글 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('알림 토글 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 주차 기여도 조회 (GET /api/weeks/contributions)
  /// 응답: WeekContributionResponse { year, weeksInYear, weeks[], greeting{} }
  Future<Map<String, dynamic>> getWeeklyContributions({int? year}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (year != null) {
        queryParams['year'] = year;
      }
      final response = await _dio.get(
        '/api/weeks/contributions',
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      if (response.statusCode == 200) {
        final decoded = response.data;
        // 일반 Map 또는 { data: {...} } 형태 모두 대응
        if (decoded is Map<String, dynamic>) {
          return decoded['data'] is Map<String, dynamic>
              ? decoded['data'] as Map<String, dynamic>
              : decoded;
        }
        throw Exception('주차 기여도 응답 형식 오류: ${decoded.runtimeType}');
      }
      throw Exception('주차 기여도 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('주차 기여도 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 회원 탈퇴 (DELETE /api/users/account)
  /// 탈퇴는 시간이 오래 걸릴 수 있으므로 1분 타임아웃 적용
  Future<String> deleteAccount() async {
    try {
      debugPrint('[UserService] DELETE /api/users/account');
      // 탈퇴 요청은 1분 타임아웃 적용
      final baseOptions = _dio.options;
      final dioWithTimeout = Dio(
        BaseOptions(
          baseUrl: baseOptions.baseUrl,
          connectTimeout: const Duration(minutes: 1),
          receiveTimeout: const Duration(minutes: 1),
          sendTimeout: const Duration(minutes: 1),
          headers: baseOptions.headers,
        ),
      );
      // 인터셉터 복사 (토큰 인증 등)
      dioWithTimeout.interceptors.addAll(_dio.interceptors);

      final response = await dioWithTimeout.delete('/api/users/account');
      if (response.statusCode == 200) {
        final responseData = response.data;
        final username = responseData['username']?.toString() ?? '';
        debugPrint('[UserService] 회원 탈퇴 성공: $username');
        return username;
      }
      throw Exception('회원 탈퇴 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage =
            e.response?.data?['error']?.toString() ??
            e.response?.data?['message']?.toString() ??
            '회원 탈퇴 실패: $statusCode';
        debugPrint('[UserService] 회원 탈퇴 실패: $errorMessage');
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }
}
