import 'package:dio/dio.dart';
import 'base_api_service.dart';
import '../models/user_model.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 자기소개 저장
  Future<void> saveSelfIntroduction(String introduction) async {
    try {
      final response = await _dio.put(
        '/api/users/self-introduction',
        data: {'selfIntroduction': introduction},
      );
      if (response.statusCode != 200) {
        throw Exception('자기소개 저장 실패');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('자기소개 저장 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 6. 내 자기소개 조회
  Future<String> getSelfIntroduction() async {
    try {
      final response = await _dio.get('/api/users/self-introduction');
      if (response.statusCode == 200) {
        return response.data['selfIntroduction'];
      }
      throw Exception('자기소개 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('자기소개 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 7. 타인 자기소개 조회
  Future<String> getOtherUserSelfIntroduction(String username) async {
    try {
      final response = await _dio.get('/api/users/$username/self-introduction');
      if (response.statusCode == 200) {
        return response.data['selfIntroduction'];
      }
      throw Exception('타인 자기소개 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('타인 자기소개 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 프로필 정보 업데이트 (/api/profile/info)
  Future<void> updateProfileInfo({
    required String alias,
    required String selfIntroduction,
    List<String>? links, // 🎯 프로필 링크 목록
    Map<String, String>? linkTitles, // 🎯 링크 타이틀 (URL -> 타이틀)
    Map<String, String>? linkThumbnails, // 🎯 링크 썸네일 (URL -> thumbnailUrl)
  }) async {
    try {
      final data = <String, dynamic>{
        'alias': alias,
        'selfIntroduction': selfIntroduction,
      };

      // 🎯 links가 null이 아닐 때 항상 추가 (빈 배열도 전달하여 삭제 가능하게)
      if (links != null) {
        data['links'] = links;
      }

      // 🎯 linkTitles가 있으면 추가 (빈 맵도 전달 가능)
      if (linkTitles != null) {
        data['linkTitles'] = linkTitles;
      }

      // 🎯 linkThumbnails가 있으면 추가 (빈 맵도 전달 가능)
      if (linkThumbnails != null) {
        data['linkThumbnails'] = linkThumbnails;
      }

      final response = await _dio.put('/api/profile/info', data: data);
      if (response.statusCode != 200) {
        throw Exception('프로필 정보 업데이트 실패');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('프로필 정보 업데이트 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 프로필 정보 조회 (/api/profile/info)
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
      print('[UserService] GET /api/profile/settings');
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
      print('[UserService] PUT /api/profile/marketing-consent');
      final response = await _dio.put('/api/profile/marketing-consent');
      if (response.statusCode == 200) {
        final newValue = response.data['marketingConsent'] as bool;
        print('[UserService] marketingConsent toggled to: $newValue');
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
      print('[UserService] PUT /api/profile/notification-enabled');
      final response = await _dio.put('/api/profile/notification-enabled');
      if (response.statusCode == 200) {
        final newValue = response.data['notificationEnabled'] as bool;
        print('[UserService] notificationEnabled toggled to: $newValue');
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

  /// 회원 탈퇴 (DELETE /api/users/account)
  Future<String> deleteAccount() async {
    try {
      print('[UserService] DELETE /api/users/account');
      final response = await _dio.delete('/api/users/account');
      if (response.statusCode == 200) {
        final responseData = response.data;
        final username = responseData['username']?.toString() ?? '';
        print('[UserService] 회원 탈퇴 성공: $username');
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
        print('[UserService] 회원 탈퇴 실패: $errorMessage');
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }
}
