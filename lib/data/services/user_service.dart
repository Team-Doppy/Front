import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_api_service.dart';
import '../models/user_model.dart';
import '../models/military_info_model.dart';
import '../models/military_grid_model.dart';
import 'auth_service.dart';

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
    MilitaryInfo? militaryInfo, // 🎯 군인 정보
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

      // 🎯 militaryInfo가 있으면 추가
      if (militaryInfo != null) {
        data['militaryInfo'] = militaryInfo.toJson();
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
  /// - ✅ 성공 시 로컬 SharedPreferences에 저장 (네트워크 오류 시 참고용)
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
          final result = v is bool ? v : null;

          // ✅ 성공 시 로컬 SharedPreferences에 저장
          if (result != null) {
            await _saveOnboardingCompletedToLocal(result);
          }

          return result;
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

  /// ✅ 로컬 SharedPreferences에 온보딩 완료 여부 저장
  Future<void> _saveOnboardingCompletedToLocal(bool completed) async {
    try {
      final accountKey = AuthService().currentUsernameSync;
      if (accountKey == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'onboarding_completed_$accountKey';
      await prefs.setBool(key, completed);
      debugPrint('[UserService] 로컬에 온보딩 완료 여부 저장: $completed');
    } catch (e) {
      debugPrint('[UserService] 로컬 온보딩 완료 여부 저장 실패: $e');
    }
  }

  /// ✅ 로컬 SharedPreferences에서 온보딩 완료 여부 가져오기
  static Future<bool?> getOnboardingCompletedFromLocal() async {
    try {
      final accountKey = AuthService().currentUsernameSync;
      if (accountKey == null) return null;

      final prefs = await SharedPreferences.getInstance();
      final key = 'onboarding_completed_$accountKey';
      final value = prefs.getBool(key);
      debugPrint('[UserService] 로컬에서 온보딩 완료 여부 조회: $value');
      return value;
    } catch (e) {
      debugPrint('[UserService] 로컬 온보딩 완료 여부 조회 실패: $e');
      return null;
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

  // ============================================
  // 휴가 관련 API (서버에서 관리)
  // ============================================

  /// 휴가 삭제 (DELETE /api/military/vacations/:id)
  /// 서버에서 휴가를 삭제합니다.
  Future<void> deleteVacation(String vacationId) async {
    try {
      debugPrint('[UserService] DELETE /api/military/vacations/$vacationId');
      final response = await _dio.delete('/api/military/vacations/$vacationId');
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('휴가 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('휴가 삭제 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  // ============================================
  // Military Grid API (새로운 시스템)
  // ============================================

  /// Military Grid 조회 (GET /api/military/grid)
  /// - 입대예정/군인: 내 그리드
  /// - 곰신: 연결된 남친 그리드
  /// - phase: 선택 파라미터. 미지정 시 현재 계급 phase 반환, 지정 시 해당 phase만 반환
  Future<MilitaryGridResponse> getMilitaryGrid({
    String? region,
    String? phase,
  }) async {
    try {
      debugPrint(
        '[UserService] GET /api/military/grid (region: $region, phase: $phase)',
      );
      final queryParams = <String, dynamic>{};
      if (region != null) {
        queryParams['region'] = region;
      }
      if (phase != null) {
        queryParams['phase'] = phase;
      }

      final response = await _dio.get(
        '/api/military/grid',
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return MilitaryGridResponse.fromJson(
          data is Map<String, dynamic>
              ? (data['data'] is Map<String, dynamic>
                  ? data['data'] as Map<String, dynamic>
                  : data)
              : data,
        );
      }
      throw Exception('Military Grid 조회 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        throw Exception('Military Grid 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 곰신 요청 보내기 (POST /api/girlfriend-requests)
  /// 곰신이 온보딩에서 군인에게 연결 요청을 보낼 때 사용
  Future<Map<String, dynamic>> sendGirlfriendRequest(
    String targetUsername,
  ) async {
    try {
      debugPrint('[UserService] 곰신 요청 보내기 시작: targetUsername=$targetUsername');
      final response = await _dio.post(
        '/api/girlfriend-requests',
        data: {'targetUsername': targetUsername},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        debugPrint('[UserService] 곰신 요청 보내기 성공: $data');
        return data is Map<String, dynamic>
            ? (data['data'] is Map<String, dynamic>
                ? data['data'] as Map<String, dynamic>
                : data)
            : <String, dynamic>{};
      }
      throw Exception('곰신 요청 보내기 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        debugPrint(
          '[UserService] 곰신 요청 보내기 실패: status=$statusCode, error=$errorData',
        );
        throw Exception(
          '곰신 요청 보내기 실패: $statusCode - ${errorData ?? e.message}',
        );
      }
      rethrow;
    }
  }

  /// 곰신 요청 수락 (POST /api/girlfriend-requests/{requestId}/accept)
  Future<Map<String, dynamic>> acceptGirlfriendRequest(String requestId) async {
    try {
      debugPrint('[UserService] 곰신 요청 수락 시작: requestId=$requestId');
      final response = await _dio.post(
        '/api/girlfriend-requests/$requestId/accept',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        debugPrint('[UserService] 곰신 요청 수락 성공: $data');
        return data is Map<String, dynamic>
            ? (data['data'] is Map<String, dynamic>
                ? data['data'] as Map<String, dynamic>
                : data)
            : <String, dynamic>{};
      }
      throw Exception('곰신 요청 수락 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        debugPrint(
          '[UserService] 곰신 요청 수락 실패: status=$statusCode, error=$errorData',
        );
        throw Exception('곰신 요청 수락 실패: $statusCode - ${errorData ?? e.message}');
      }
      rethrow;
    }
  }

  /// 곰신 요청 거절 (POST /api/girlfriend-requests/{requestId}/reject)
  Future<Map<String, dynamic>> rejectGirlfriendRequest(String requestId) async {
    try {
      debugPrint('[UserService] 곰신 요청 거절 시작: requestId=$requestId');
      final response = await _dio.post(
        '/api/girlfriend-requests/$requestId/reject',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        debugPrint('[UserService] 곰신 요청 거절 성공: $data');
        return data is Map<String, dynamic>
            ? (data['data'] is Map<String, dynamic>
                ? data['data'] as Map<String, dynamic>
                : data)
            : <String, dynamic>{};
      }
      throw Exception('곰신 요청 거절 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        debugPrint(
          '[UserService] 곰신 요청 거절 실패: status=$statusCode, error=$errorData',
        );
        throw Exception('곰신 요청 거절 실패: $statusCode - ${errorData ?? e.message}');
      }
      rethrow;
    }
  }

  /// 헤어짐(연결 해제) (POST /api/military/connection/disconnect)
  /// 응답: 최신 UserMeResponse(bundle 형태)
  Future<Map<String, dynamic>> disconnectMilitaryConnection() async {
    try {
      debugPrint('[UserService] 헤어짐(연결 해제) 시작');
      final response = await _dio.post('/api/military/connection/disconnect');

      if (response.statusCode == 200) {
        final data = response.data;
        debugPrint('[UserService] 헤어짐(연결 해제) 성공: $data');
        return data is Map<String, dynamic>
            ? (data['data'] is Map<String, dynamic>
                ? data['data'] as Map<String, dynamic>
                : data)
            : <String, dynamic>{};
      }
      throw Exception('헤어짐(연결 해제) 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        debugPrint(
          '[UserService] 헤어짐(연결 해제) 실패: status=$statusCode, error=$errorData',
        );
        throw Exception(
          '헤어짐(연결 해제) 실패: $statusCode - ${errorData ?? e.message}',
        );
      }
      rethrow;
    }
  }

  /// 입대일/진급일/계급 보정 (PATCH /api/military/state-adjustment)
  /// 대상: 군인(military) + 입대 후(afterEnlistment)만 사용 가능
  /// 전송한 필드만 반영됨 (부분 업데이트)
  /// currentRank는 수정 불가 (서버가 자동 계산) - 요청에 포함하지 않음
  /// manualPromotionDates는 기존 맵에 병합됨 (전체 치환 아님)
  Future<Map<String, dynamic>> adjustMilitaryState({
    DateTime? enlistmentDate,
    Map<String, String>? manualPromotionDates,
  }) async {
    try {
      final data = <String, dynamic>{};

      if (enlistmentDate != null) {
        data['enlistmentDate'] = enlistmentDate.toIso8601String();
      }

      // currentRank는 수정 불가 (서버가 자동 계산) - 요청에 포함하지 않음

      if (manualPromotionDates != null && manualPromotionDates.isNotEmpty) {
        // ✅ manualPromotionDates는 기존 맵에 병합됨 (전체 치환 아님)
        data['manualPromotionDates'] = manualPromotionDates;
      }

      debugPrint('[UserService] adjustMilitaryState 요청 데이터: $data');
      final response = await _dio.patch(
        '/api/military/state-adjustment',
        data: data,
      );
      debugPrint(
        '[UserService] adjustMilitaryState 응답 상태: ${response.statusCode}',
      );
      debugPrint('[UserService] adjustMilitaryState 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        final decoded = response.data;
        return decoded is Map<String, dynamic>
            ? (decoded['data'] is Map<String, dynamic>
                ? decoded['data'] as Map<String, dynamic>
                : decoded)
            : <String, dynamic>{};
      }
      throw Exception('입대일/진급일/계급 보정 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        debugPrint('[UserService] adjustMilitaryState DioException:');
        debugPrint('  - Status Code: ${e.response?.statusCode}');
        debugPrint('  - Response Data: ${e.response?.data}');
        debugPrint('  - Request Data: ${e.requestOptions.data}');
        debugPrint('  - Message: ${e.message}');
        throw Exception(
          '입대일/진급일/계급 보정 실패: ${e.response?.statusCode} - ${e.response?.data}',
        );
      }
      debugPrint('[UserService] adjustMilitaryState 기타 에러: $e');
      rethrow;
    }
  }

  /// 커플 애칭 업데이트 (PATCH /api/military/connection/pair-alias)
  /// Body: { "pairAlias": "우리애칭" } (null/빈 문자열이면 삭제)
  /// 응답: 최신 bundle(UserMeResponse) → 로컬 캐시를 그대로 덮어쓰기
  Future<Map<String, dynamic>> updatePairAlias(String? pairAlias) async {
    try {
      debugPrint('[UserService] 커플 애칭 업데이트 시작: pairAlias=$pairAlias');
      final response = await _dio.patch(
        '/api/military/connection/pair-alias',
        data: {'pairAlias': pairAlias ?? ''},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        debugPrint('[UserService] 커플 애칭 업데이트 성공: $data');
        return data is Map<String, dynamic>
            ? (data['data'] is Map<String, dynamic>
                ? data['data'] as Map<String, dynamic>
                : data)
            : <String, dynamic>{};
      }
      throw Exception('커플 애칭 업데이트 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        debugPrint(
          '[UserService] 커플 애칭 업데이트 실패: status=$statusCode, error=$errorData',
        );
        throw Exception(
          '커플 애칭 업데이트 실패: $statusCode - ${errorData ?? e.message}',
        );
      }
      rethrow;
    }
  }
}
