import 'package:dio/dio.dart';
import 'base_api_service.dart';
import '../models/friend_model.dart';
import '../models/user_model.dart';

class FriendService {
  static final FriendService _instance = FriendService._internal();
  factory FriendService() => _instance;
  FriendService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 8. 친구 신청
  Future<void> sendFriendRequest(String targetUsername) async {
    try {
      final response = await _dio.post(
        '/api/friends/request',
        data: {'targetUsername': targetUsername},
      );

      final code = response.statusCode;
      // 일부 서버는 201/204를 반환할 수 있음 → 2xx 모두 성공 처리
      if (code != null && code >= 200 && code < 300) {
        return; // 성공
      }
    } catch (e) {
      if (e is DioException) {
        final code = e.response?.statusCode;
        final responseData = e.response?.data;

        // 특수 케이스: 서버가 바디 파싱 실패(예: No value present) 응답 시
        if (code == 400 &&
            responseData.toString().contains('No value present')) {
          try {
            // 쿼리파라미터 방식으로 재시도 (서버 구현 케이스 대응)
            final fallback = await _dio.post(
              '/api/friends/request?targetUsername=${Uri.encodeComponent(targetUsername)}',
            );
            final fcode = fallback.statusCode;
            if (fcode != null && fcode >= 200 && fcode < 300) return;
            // ignore: avoid_print
            print(
              '[FriendService] fallback also failed | code=$fcode data=${fallback.data}',
            );
          } catch (fallbackError) {
            // ignore: avoid_print
            print('[FriendService] fallback request failed: $fallbackError');
          }
        }

        // 디버그를 위해 상태/본문 로그 남김
        // ignore: avoid_print
        print(
          '[FriendService] sendFriendRequest failed | code=$code data=$responseData',
        );
      }
      throw Exception('친구 신청 실패');
    }
  }

  /// 9. 친구 수락
  Future<void> acceptFriendRequest(String requesterUsername) async {
    try {
      final response = await _dio.post(
        '/api/friends/accept/$requesterUsername',
      );
      if (response.statusCode != 200) throw Exception('친구 요청 수락 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('친구 요청 수락 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 10. 친구 거절
  Future<void> rejectFriendRequest(String requesterUsername) async {
    try {
      final response = await _dio.post(
        '/api/friends/reject/$requesterUsername',
      );
      if (response.statusCode != 200) throw Exception('친구 요청 거절 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('친구 요청 거절 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 12. 친구 삭제
  Future<void> deleteFriend(String targetUsername) async {
    try {
      final response = await _dio.delete('/api/friends/delete/$targetUsername');
      if (response.statusCode != 200) throw Exception('친구 삭제 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('친구 삭제 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 13. 사용자 검색
  Future<List<User>> searchUsers(String query) async {
    try {
      final response = await _dio.get('/api/friends/search?username=$query');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        // API 응답이 {"username": "..."} 이므로 User 모델로 변환
        return data
            .map((item) => User(id: 0, username: item['username']))
            .toList();
      }
      throw Exception('사용자 검색 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('사용자 검색 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 14. 수락된 친구 목록 조회
  Future<List<Friend>> getAcceptedFriends() async {
    try {
      final response = await _dio.get('/api/friends/accepted');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((item) => Friend.fromJson(item)).toList();
      }
      throw Exception('친구 목록 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('친구 목록 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 15. 보낸 친구 신청 목록
  Future<List<Friend>> getSentFriendRequests() async {
    try {
      final response = await _dio.get('/api/friends/sent-requests');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((item) => Friend.fromJson(item)).toList();
      }
      throw Exception('보낸 친구 신청 목록 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('보낸 친구 신청 목록 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 15-1. 보낸 친구 신청 취소
  Future<void> cancelFriendRequest(String targetUsername) async {
    try {
      // 명세 준수: DELETE /api/friends/cancel-request/{username}
      final response = await _dio.delete(
        '/api/friends/cancel-request/$targetUsername',
      );
      print('┌─[RES] ${response.statusCode} ${response.data}');
      print('└────────────────────────────────');
      if (response.statusCode != 200) {
        throw Exception('친구 요청 취소 실패');
      }
    } catch (e) {
      if (e is DioException) {
        throw Exception('친구 요청 취소 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 16. 받은 친구 신청 목록
  Future<List<Friend>> getReceivedFriendRequests() async {
    try {
      final response = await _dio.get('/api/friends/received-requests');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((item) => Friend.fromJson(item)).toList();
      }
      throw Exception('받은 친구 신청 목록 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('받은 친구 신청 목록 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }
}
