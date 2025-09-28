import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:http/http.dart' as http;

class LikeService extends ChangeNotifier {
  static final LikeService _instance = LikeService._internal();
  factory LikeService() => _instance;
  LikeService._internal();

  static final String _baseUrl = ApiServiceBase.baseUrl;

  // 포스트별 좋아요 상태 캐시 (프론트엔드에서만 관리)
  final Map<String, bool> _postLikeStatus = {};
  // 포스트별 좋아요 수 캐시 (프론트엔드에서만 관리)
  final Map<String, int> _postLikeCounts = {};

  // Getters
  bool isPostLiked(String postId) => _postLikeStatus[postId] ?? false;
  int getPostLikeCount(String postId) => _postLikeCounts[postId] ?? 0;

  /// 초기 좋아요 상태와 수 설정 (PostData에서 가져온 값)
  void setInitialLikeData(String postId, bool isLiked, int count) {
    _postLikeStatus[postId] = isLiked;
    _postLikeCounts[postId] = count;
  }

  /// 포스트 좋아요 토글
  Future<void> togglePostLike(String postId) async {
    if (postId.isEmpty) {
      print('[LikeService] 잘못된 postId: $postId');
      throw ArgumentError('postId가 비어있습니다');
    }

    try {
      final token = await AuthService().getToken();
      if (token == null) {
        print('[LikeService] 토큰이 없습니다');
        throw HttpException('인증 토큰이 없습니다');
      }

      final isCurrentlyLiked = _postLikeStatus[postId] ?? false;

      Uri uri;
      if (isCurrentlyLiked) {
        // 좋아요 취소
        uri = Uri.parse('$_baseUrl/api/posts/$postId/like');
      } else {
        // 좋아요 추가
        uri = Uri.parse('$_baseUrl/api/posts/$postId/like');
      }

      print('[LikeService] 좋아요 ${isCurrentlyLiked ? '취소' : '추가'}: $postId');

      final response =
          isCurrentlyLiked
              ? await http
                  .delete(
                    uri,
                    headers: {
                      'Authorization': 'Bearer $token',
                      'Content-Type': 'application/json',
                    },
                  )
                  .timeout(const Duration(seconds: 5))
              : await http
                  .post(
                    uri,
                    headers: {
                      'Authorization': 'Bearer $token',
                      'Content-Type': 'application/json',
                    },
                  )
                  .timeout(const Duration(seconds: 5));

      print('[LikeService] 좋아요 응답: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        // 성공 시 로컬 상태 업데이트
        _postLikeStatus[postId] = !isCurrentlyLiked;

        // 카운트 업데이트
        final currentCount = _postLikeCounts[postId] ?? 0;
        _postLikeCounts[postId] =
            isCurrentlyLiked
                ? (currentCount - 1).clamp(0, double.infinity).toInt()
                : currentCount + 1;

        notifyListeners();
        print(
          '[LikeService] 좋아요 토글 성공: $postId = ${_postLikeStatus[postId]}, 카운트: ${_postLikeCounts[postId]}',
        );
      } else if (response.statusCode == 400) {
        print(
          '[LikeService] 잘못된 요청: ${response.statusCode} - ${response.body}',
        );
        // 400 에러 시 서버 상태로 강제 동기화
        await _forceSyncWithServer(postId, token);
        throw HttpException('좋아요 상태가 서버와 다릅니다. 다시 시도해주세요.');
      } else if (response.statusCode == 401) {
        print('[LikeService] 인증 실패: ${response.statusCode}');
        throw HttpException('인증이 필요합니다. 다시 로그인해주세요.');
      } else if (response.statusCode == 404) {
        print('[LikeService] 포스트를 찾을 수 없음: ${response.statusCode}');
        throw HttpException('포스트를 찾을 수 없습니다.');
      } else {
        print(
          '[LikeService] 좋아요 토글 실패: ${response.statusCode} - ${response.body}',
        );
        throw HttpException('좋아요 처리 중 오류가 발생했습니다: ${response.statusCode}');
      }
    } catch (e) {
      print('[LikeService] 좋아요 토글 오류: $e');
      rethrow;
    }
  }

  /// 서버 상태로 강제 동기화 (400 에러 시)
  Future<void> _forceSyncWithServer(String postId, String token) async {
    try {
      // 서버 상태 확인
      final statusUri = Uri.parse('$_baseUrl/api/posts/$postId/like/status');
      final statusResponse = await http
          .get(
            statusUri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 3));

      if (statusResponse.statusCode == 200) {
        final serverIsLiked = statusResponse.body.toLowerCase() == 'true';
        _postLikeStatus[postId] = serverIsLiked;

        // 카운트도 서버에서 가져오기
        final countUri = Uri.parse('$_baseUrl/api/posts/$postId/like/count');
        final countResponse = await http
            .get(
              countUri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 3));

        if (countResponse.statusCode == 200) {
          final serverCount = int.tryParse(countResponse.body) ?? 0;
          _postLikeCounts[postId] = serverCount;
        }

        notifyListeners();
        print('[LikeService] 서버 상태로 강제 동기화 완료: $postId = $serverIsLiked');
      }
    } catch (e) {
      print('[LikeService] 강제 동기화 실패: $e');
    }
  }

  /// 캐시 초기화
  void clearCache() {
    _postLikeStatus.clear();
    _postLikeCounts.clear();
    notifyListeners();
  }

  /// 특정 포스트 캐시 제거
  void clearPostCache(String postId) {
    _postLikeStatus.remove(postId);
    _postLikeCounts.remove(postId);
    notifyListeners();
  }
}
