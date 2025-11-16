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
    List<String>? links, // 🎯 프로필 링크 목록 (최대 3개)
  }) async {
    try {
      final data = <String, dynamic>{
        'alias': alias,
        'selfIntroduction': selfIntroduction,
      };

      // 🎯 links가 있으면 추가 (최대 3개)
      if (links != null && links.isNotEmpty) {
        data['links'] = links.take(3).toList();
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
}
