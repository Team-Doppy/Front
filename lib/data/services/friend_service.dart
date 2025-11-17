import 'package:dio/dio.dart';
import 'base_api_service.dart';
import '../models/friend_model.dart';
import '../models/user_model.dart';

/// 친구 요청이 존재하지 않는 경우 예외 (이미 취소되었거나 없음)
class FriendRequestNotFoundException implements Exception {
  final String message;
  FriendRequestNotFoundException(this.message);
  @override
  String toString() => message;
}

class FriendService {
  static final FriendService _instance = FriendService._internal();
  factory FriendService() => _instance;
  FriendService._internal();

  final Dio _dio = BaseApiService().dio;

  /// 8. 친구 신청
  Future<void> sendFriendRequest(String targetUsername) async {
    try {
      print('🚀 [FriendService] 친구 요청 보내기 시작: $targetUsername');
      final response = await _dio.post(
        '/api/friends/request',
        data: {'targetUsername': targetUsername},
      );

      final code = response.statusCode;
      print('✅ [FriendService] 응답 받음 | code=$code data=${response.data}');

      // 일부 서버는 201/204를 반환할 수 있음 → 2xx 모두 성공 처리
      if (code != null && code >= 200 && code < 300) {
        print('✅ [FriendService] 친구 요청 성공: $targetUsername');
        return; // 성공
      }

      print('⚠️ [FriendService] 예상치 못한 응답 코드: $code');
      throw Exception('친구 신청 실패: 응답 코드 $code');
    } catch (e) {
      print('❌ [FriendService] 에러 발생: $e');

      if (e is DioException) {
        final code = e.response?.statusCode;
        final responseData = e.response?.data;

        print('❌ [FriendService] DioException | code=$code');
        print('❌ [FriendService] responseData: $responseData');
        print('❌ [FriendService] error message: ${e.message}');

        // 🎯 특수 케이스: 이미 친구 요청이 존재하는 경우 → 성공으로 간주
        if (code == 400 &&
            responseData.toString().contains('이미 친구 요청이 존재합니다')) {
          print('✅ [FriendService] 이미 친구 요청이 존재함 → 성공 처리');
          return; // 성공으로 처리
        }

        // 특수 케이스: 서버가 바디 파싱 실패(예: No value present) 응답 시
        if (code == 400 &&
            responseData.toString().contains('No value present')) {
          try {
            print('🔄 [FriendService] fallback 시도: 쿼리파라미터 방식');
            // 쿼리파라미터 방식으로 재시도 (서버 구현 케이스 대응)
            final fallback = await _dio.post(
              '/api/friends/request?targetUsername=${Uri.encodeComponent(targetUsername)}',
            );
            final fcode = fallback.statusCode;
            if (fcode != null && fcode >= 200 && fcode < 300) {
              print('✅ [FriendService] fallback 성공!');
              return;
            }
            // ignore: avoid_print
            print(
              '[FriendService] fallback also failed | code=$fcode data=${fallback.data}',
            );
          } catch (fallbackError) {
            // ignore: avoid_print
            print('[FriendService] fallback request failed: $fallbackError');
          }
        }
      }
      throw Exception('친구 신청 실패: $e');
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
        final statusCode = e.response?.statusCode;
        // 🎯 이미 취소된 요청인 경우 (404 또는 적절한 에러 코드)
        if (statusCode == 404) {
          throw FriendRequestNotFoundException('친구 요청이 이미 취소되었거나 존재하지 않습니다');
        }
        throw Exception('친구 요청 수락 실패: $statusCode');
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

  /// 12-1. 다중 친구 삭제 (일괄 해제)
  Future<void> deleteFriendsBatch(List<String> usernames) async {
    try {
      print('🔍 [FriendService] 친구 일괄 삭제 시작: ${usernames.length}명');

      final response = await _dio.delete(
        '/api/friends/delete/batch',
        data: usernames, // username 배열을 body로 전달
      );

      print('📡 [FriendService] API 응답 상태: ${response.statusCode}');
      print('📡 [FriendService] API 응답 데이터: ${response.data}');

      if (response.statusCode == 200) {
        print('✅ [FriendService] 친구 일괄 삭제 성공');
        return;
      } else {
        print(
          '❌ [FriendService] API 오류: ${response.statusCode} - ${response.data}',
        );
        throw Exception('친구 일괄 삭제 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ [FriendService] 친구 일괄 삭제 중 예외 발생: $e');
      if (e is DioException) {
        print(
          '❌ [FriendService] Dio 에러: ${e.response?.statusCode} - ${e.response?.data}',
        );
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
        return data.map((item) => User(username: item['username'])).toList();
      }
      throw Exception('사용자 검색 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('사용자 검색 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 15. 사용자 차단
  /// - [targetUsername] 차단할 사용자명
  Future<void> blockUser(String targetUsername) async {
    try {
      final response = await _dio.post('/api/friends/block/$targetUsername');

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        print('[FriendService] 사용자 차단 성공: $targetUsername');
        return;
      }

      throw Exception('사용자 차단 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage =
            e.response?.data?['message']?.toString() ??
            '사용자 차단 실패: $statusCode';
        print('[FriendService] 사용자 차단 실패: $errorMessage');
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }

  /// 16. 차단 해제
  /// - [targetUsername] 차단 해제할 사용자명
  Future<void> unblockUser(String targetUsername) async {
    try {
      final response = await _dio.delete('/api/friends/block/$targetUsername');

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        print('[FriendService] 차단 해제 성공: $targetUsername');
        return;
      }

      throw Exception('차단 해제 실패: ${response.statusCode}');
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final errorMessage =
            e.response?.data?['message']?.toString() ?? '차단 해제 실패: $statusCode';
        print('[FriendService] 차단 해제 실패: $errorMessage');
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }

  /// 17. 차단 목록 조회
  Future<List<User>> getBlockedUsers() async {
    try {
      final response = await _dio.get('/api/friends/blocked');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((item) => User.fromJson(item)).toList();
      }

      throw Exception('차단 목록 조회 실패');
    } catch (e) {
      if (e is DioException) {
        throw Exception('차단 목록 조회 실패: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  /// 14. 수락된 친구 목록 조회 (페이지네이션 지원)
  Future<List<Friend>> getAcceptedFriends({int page = 0, int size = 20}) async {
    try {
      final response = await _dio.get(
        '/api/friends/accepted',
        queryParameters: {'page': page, 'size': size},
      );
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

  /// 15. 보낸 친구 신청 목록 (페이지네이션 지원)
  Future<List<Friend>> getSentFriendRequests({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/friends/sent-requests',
        queryParameters: {'page': page, 'size': size},
      );
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

  /// 16. 받은 친구 신청 목록 (페이지네이션 지원)
  Future<List<Friend>> getReceivedFriendRequests({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/api/friends/received-requests',
        queryParameters: {'page': page, 'size': size},
      );
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
