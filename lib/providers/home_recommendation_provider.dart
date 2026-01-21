import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/models/home_recommendation_model.dart';
import '../data/services/blog_service.dart';
import '../image/utils/read_image_cache_manager.dart';

class HomeRecommendationProvider with ChangeNotifier {
  final BlogService _blogService = BlogService();

  List<RecCardForHomeResponse> _recommendations = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RecCardForHomeResponse> get recommendations => _recommendations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 홈용 추천 카드 로드
  Future<void> loadHomeRecommendations() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await _blogService.getHomeRecommendations();
      final recommendations =
          data.map((json) => RecCardForHomeResponse.fromJson(json)).toList();

      setState(() {
        _recommendations = recommendations;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[HomeRecommendationProvider] 추천 카드 로드 실패: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 타입별 추천 카드 필터링
  List<RecCardForHomeResponse> getRecommendationsByType(RecCardType type) {
    return _recommendations.where((rec) => rec.recType == type).toList();
  }

  /// 상태 업데이트 헬퍼
  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  /// 초기화
  void clear() {
    _recommendations = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// ✅ 홈 화면의 모든 이미지/영상 URL 수집
  /// HomeRecommendationProvider, FriendProvider, MyProfileFeedProvider에서 수집
  static List<String> collectAllHomeMediaUrls({
    required List<RecCardForHomeResponse> recommendations,
    required List<Map<String, dynamic>> friendPosts,
    required List<Map<String, dynamic>> myProfilePosts,
    String? profileImageUrl,
  }) {
    final urls = <String>[];

    // 1. HomeRecommendationProvider의 모든 추천 포스트
    for (final rec in recommendations) {
      for (final post in rec.posts) {
        final thumbnailUrl = post['thumbnailImageUrl'] as String?;
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
          urls.add(thumbnailUrl);
        }
      }
    }

    // 2. FriendProvider의 친구 포스트
    for (final post in friendPosts) {
      final thumbnailUrl = post['thumbnailImageUrl'] as String?;
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        urls.add(thumbnailUrl);
      }
    }

    // 3. RecapCard용 (프로필 이미지 또는 포스트 썸네일)
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      urls.add(profileImageUrl);
    } else {
      // 프로필 이미지가 없으면 포스트 썸네일 사용
      for (final post in myProfilePosts.take(3)) {
        final thumbnailUrl = post['thumbnailImageUrl'] as String?;
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
          urls.add(thumbnailUrl);
          break; // 첫 번째만 사용
        }
      }
    }

    // 중복 제거
    return urls.toSet().toList();
  }

  /// ✅ 홈 화면의 모든 이미지/영상을 비동기로 프리캐싱
  /// 홈 데이터 로드 후 호출하여 백그라운드에서 프리캐싱 시작
  static Future<void> precacheAllHomeMedia({
    required BuildContext context,
    required List<RecCardForHomeResponse> recommendations,
    required List<Map<String, dynamic>> friendPosts,
    required List<Map<String, dynamic>> myProfilePosts,
    String? profileImageUrl,
  }) async {
    if (!context.mounted) return;

    final urls = collectAllHomeMediaUrls(
      recommendations: recommendations,
      friendPosts: friendPosts,
      myProfilePosts: myProfilePosts,
      profileImageUrl: profileImageUrl,
    );

    if (urls.isEmpty) {
      debugPrint('[HomeRecommendationProvider] 프리캐싱할 이미지 없음');
      return;
    }

    debugPrint(
      '[HomeRecommendationProvider] 🚀 홈 화면 이미지/영상 프리캐싱 시작: ${urls.length}개',
    );

    // 비동기로 프리캐싱 (화면 진입을 막지 않음)
    Future.microtask(() async {
      final screenWidth = MediaQuery.of(context).size.width;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      // ✅ 실제 렌더링 memCacheWidth와 동일 기준(=캐시 히트 핵심)
      const maxDecodeWidthPx = 3072; // ✅ 과도한 디코드는 실패/지연 방지
      final memCacheWidth = (screenWidth * dpr * 2).round().clamp(
        1,
        maxDecodeWidthPx,
      );

      // 배치로 나누어 처리 (한 번에 너무 많이 하면 메모리 부족)
      const batchSize = 10;
      for (int i = 0; i < urls.length; i += batchSize) {
        if (!context.mounted) break;

        final batch = urls.skip(i).take(batchSize).toList();
        await Future.wait(
          batch.map((url) async {
            if (!context.mounted) return;

            try {
              // 이미지인지 영상인지 확인
              final urlLower = url.toLowerCase();
              final isVideo =
                  urlLower.endsWith('.mp4') ||
                  urlLower.endsWith('.mov') ||
                  urlLower.endsWith('.m4v') ||
                  urlLower.contains('/videos/') ||
                  urlLower.contains('video');

              if (isVideo) {
                // 영상은 썸네일만 프리캐싱 (실제 비디오는 나중에 로드)
                // 썸네일 URL이 따로 있으면 사용, 없으면 스킵
                debugPrint(
                  '[HomeRecommendationProvider] 영상 프리캐싱 스킵 (썸네일만): $url',
                );
                return;
              }

              // 이미지 프리캐싱
              final provider = CachedNetworkImageProvider(
                url,
                cacheManager: ReadImageCacheManager.instance,
              );
              final resizedProvider = ResizeImage(
                provider,
                width: memCacheWidth,
              );
              await precacheImage(resizedProvider, context);

              debugPrint('[HomeRecommendationProvider] ✅ 이미지 프리캐싱 완료: $url');
            } catch (e) {
              if (e.toString().contains('dispose') ||
                  e.toString().contains('mounted')) {
                debugPrint(
                  '[HomeRecommendationProvider] ⚠️ context dispose로 인한 중단: $url',
                );
                return;
              }
              debugPrint(
                '[HomeRecommendationProvider] ❌ 이미지 프리캐싱 실패: $url - $e',
              );
            }
          }),
          eagerError: false, // 하나 실패해도 계속 진행
        );

        // 배치 간 짧은 딜레이 (메모리 부담 완화)
        if (i + batchSize < urls.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      debugPrint(
        '[HomeRecommendationProvider] ✅ 홈 화면 이미지/영상 프리캐싱 완료: ${urls.length}개',
      );
    });
  }
}
