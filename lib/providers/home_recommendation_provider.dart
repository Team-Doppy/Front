import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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

    // ✅ 성능: 안드로이드에서 특히 프리캐시(다운로드+디코드)가 메인 스레드를 오래 점유할 수 있어
    // - "즉시 microtask" 대신, 최소 1프레임 이후에 시작
    // - 동시 디코드 개수/디코드 폭을 줄여서 프레임 드롭 완화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      unawaited(() async {
        // 홈 첫 렌더/애니메이션이 안정화될 시간을 조금 준다 (안드로이드에서 체감 큼)
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!context.mounted) return;

        final isAndroid = defaultTargetPlatform == TargetPlatform.android;
        final screenWidth = MediaQuery.of(context).size.width;
        final dpr = MediaQuery.of(context).devicePixelRatio;

        // ✅ 홈 썸네일은 "완전한 2x"가 꼭 필요하지 않음.
        // Android는 디코드 비용이 커서 1.5x로 낮춰 프레임 드롭을 줄인다.
        final double multiplier = isAndroid ? 1.5 : 2.0;
        final int maxDecodeWidthPx = isAndroid ? 2048 : 3072;
        final memCacheWidth = (screenWidth * dpr * multiplier).round().clamp(
          1,
          maxDecodeWidthPx,
        );

        // ✅ 동시 프리캐시 제한 (안드로이드는 더 보수적으로)
        final int concurrency = isAndroid ? 2 : 4;
        final int yieldMs = isAndroid ? 16 : 4; // 프레임 양보

        debugPrint(
          '[HomeRecommendationProvider] ⚙️ precache cfg: '
          'platform=${defaultTargetPlatform.name}, '
          'concurrency=$concurrency, memCacheWidth=$memCacheWidth',
        );

        Future<void> precacheOne(String url) async {
          if (!context.mounted) return;

          final urlLower = url.toLowerCase();
          final isVideo =
              urlLower.endsWith('.mp4') ||
              urlLower.endsWith('.mov') ||
              urlLower.endsWith('.m4v') ||
              urlLower.contains('/videos/') ||
              urlLower.contains('video');
          if (isVideo) return; // 비디오는 여기서 이미지 precache 하지 않음

          final provider = CachedNetworkImageProvider(
            url,
            cacheManager: ReadImageCacheManager.instance,
          );
          final resizedProvider = ResizeImage(provider, width: memCacheWidth);
          await precacheImage(resizedProvider, context);
        }

        // ✅ 배치(=동시성) 단위로 쪼개서, 배치 사이에 프레임을 양보한다.
        for (int i = 0; i < urls.length; i += concurrency) {
          if (!context.mounted) break;
          final batch = urls.skip(i).take(concurrency).toList();
          try {
            await Future.wait(
              batch.map((u) async {
                try {
                  await precacheOne(u);
                } catch (e) {
                  // best-effort
                  if (kDebugMode) {
                    debugPrint(
                      '[HomeRecommendationProvider] ⚠️ precache 실패(무시): $u - $e',
                    );
                  }
                }
              }),
              eagerError: false,
            );
          } catch (_) {
            // batch 자체 실패도 best-effort
          }

          // 🎯 메인 스레드 양보: UI가 먼저 그려지게 함 (안드로이드 프레임 드롭 완화)
          if (i + concurrency < urls.length) {
            // endOfFrame은 너무 느릴 수 있어 짧은 delay로 타협
            await Future<void>.delayed(Duration(milliseconds: yieldMs));
          }
        }

        debugPrint(
          '[HomeRecommendationProvider] ✅ 홈 화면 이미지 프리캐싱 완료: ${urls.length}개',
        );
      }());
    });
  }
}
