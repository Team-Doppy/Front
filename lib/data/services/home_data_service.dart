import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:flutter/material.dart';

/// 피드 데이터 컨테이너
class HomeData {
  final List<PostData> friendsPosts;
  final List<PostData> allPosts;
  final DateTime loadedAt;

  HomeData({
    required this.friendsPosts,
    required this.allPosts,
    DateTime? loadedAt,
  }) : loadedAt = loadedAt ?? DateTime.now();

  bool get isEmpty => friendsPosts.isEmpty && allPosts.isEmpty;

  HomeData copyWith({
    List<PostData>? friendsPosts,
    List<PostData>? allPosts,
    DateTime? loadedAt,
  }) {
    return HomeData(
      friendsPosts: friendsPosts ?? this.friendsPosts,
      allPosts: allPosts ?? this.allPosts,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }
}

/// 캐시된 피드 데이터
class CachedFeedData {
  final List<PostData> posts;
  final DateTime cachedAt;
  final int page;

  const CachedFeedData({
    required this.posts,
    required this.cachedAt,
    required this.page,
  });

  bool get isExpired {
    final cacheValidDuration = Duration(minutes: 5);
    return DateTime.now().difference(cachedAt) > cacheValidDuration;
  }
}

/// 스마트 피드 캐시
class SmartFeedCache {
  static const int _maxCacheSize = 10; // 캐시 항목 수 제한
  final Map<String, CachedFeedData> _cache = {};

  /// 캐시 키 생성
  String _generateKey(String type, int page, int size) {
    return '${type}_${page}_$size';
  }

  /// 피드 데이터 캐시
  void cacheFeedData(String type, List<PostData> posts, int page, int size) {
    final key = _generateKey(type, page, size);

    // LRU 캐시 구현 - 오래된 항목 제거
    if (_cache.length >= _maxCacheSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    _cache[key] = CachedFeedData(
      posts: posts,
      cachedAt: DateTime.now(),
      page: page,
    );
  }

  /// 캐시된 피드 데이터 조회
  List<PostData>? getCachedFeedData(String type, int page, int size) {
    final key = _generateKey(type, page, size);
    final cached = _cache[key];

    if (cached == null) {
      return null;
    }

    if (cached.isExpired) {
      _cache.remove(key);
      return null;
    }

    return cached.posts;
  }

  /// 특정 타입의 캐시 무효화
  void invalidateCache(String type) {
    final keysToRemove =
        _cache.keys.where((key) => key.startsWith(type)).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }

  /// 전체 캐시 클리어
  void clearAll() {
    _cache.clear();
  }
}

/// 통합 피드 데이터 서비스
class HomeDataService {
  static final HomeDataService _instance = HomeDataService._internal();
  factory HomeDataService() => _instance;
  HomeDataService._internal();

  final BlogService _blogService = BlogService();
  final SmartFeedCache _cache = SmartFeedCache();

  /// 스플래시에서 사용: 두 섹션 데이터 동시 로드
  Future<HomeData> preloadAllSections({int page = 0, int size = 20}) async {
    try {
      // 두 섹션 데이터를 병렬로 로드
      final results = await Future.wait([
        _loadFriendsPostsDirect(page: page, size: size),
        _loadAllPostsDirect(page: page, size: size),
      ]);

      final friendsPosts =
          results[0].map((e) => PostData.fromServer(e)).toList();
      final allPosts = results[1].map((e) => PostData.fromServer(e)).toList();

      // 캐시 저장
      _cache.cacheFeedData('friends', friendsPosts, page, size);
      _cache.cacheFeedData('all', allPosts, page, size);

      final feedData = HomeData(friendsPosts: friendsPosts, allPosts: allPosts);

      return feedData;
    } catch (e) {
      // 에러를 그대로 전파해서 홈화면에서 적절한 에러 UI 표시
      rethrow;
    }
  }

  /// 친구글 로드 (캐시 우선)
  Future<List<PostData>> loadFriendsPosts({
    int page = 0,
    int size = 20, // 🎯 10 -> 20으로 변경
    bool refresh = false,
  }) async {
    // 새로고침이면 캐시 완전히 비우기
    if (refresh) {
      _cache.invalidateCache('friends');
    }

    // 새로고침이 아니면 캐시 확인
    if (!refresh) {
      final cached = _cache.getCachedFeedData('friends', page, size);
      if (cached != null) {
        return cached;
      }
    }

    try {
      final serverData = await _loadFriendsPostsDirect(page: page, size: size);
      final posts = serverData.map((e) => PostData.fromServer(e)).toList();

      // 캐시 저장
      _cache.cacheFeedData('friends', posts, page, size);

      return posts;
    } catch (e) {
      rethrow;
    }
  }

  /// 전체글 로드 (캐시 우선)
  Future<List<PostData>> loadAllPosts({
    int page = 0,
    int size = 20, // 🎯 10 -> 20으로 변경
    bool refresh = false,
  }) async {
    // 새로고침이면 캐시 완전히 비우기
    if (refresh) {
      _cache.invalidateCache('all');
    }

    // 새로고침이 아니면 캐시 확인
    if (!refresh) {
      final cached = _cache.getCachedFeedData('all', page, size);
      if (cached != null) {
        return cached;
      }
    }

    try {
      final serverData = await _loadAllPostsDirect(page: page, size: size);
      final posts = serverData.map((e) => PostData.fromServer(e)).toList();

      // 캐시 저장
      _cache.cacheFeedData('all', posts, page, size);

      return posts;
    } catch (e) {
      rethrow;
    }
  }

  /// 이미지와 비디오 배치 프리캐싱 (20개 전체)
  Future<void> precacheImages(
    List<PostData> posts,
    BuildContext context,
  ) async {
    if (posts.isEmpty) return;

    // 🎯 이미지 URL 추출 (비디오 제외)
    final imagesToCache =
        posts
            .where((post) => post.thumbnailImageUrl.isNotEmpty)
            .where((post) {
              // 🎯 비디오 파일(.mp4, .mov 등) 제외 - 이미지만 프리캐시
              final url = post.thumbnailImageUrl.toLowerCase();
              return !url.endsWith('.mp4') &&
                  !url.endsWith('.mov') &&
                  !url.endsWith('.avi') &&
                  !url.endsWith('.webm') &&
                  !url.contains('/videos/');
            })
            .map((post) => post.thumbnailImageUrl)
            .toSet() // 중복 제거
            .toList();

    // 🎯 비디오 URL 추출
    final videosToCache =
        posts
            .where((post) => post.thumbnailImageUrl.isNotEmpty)
            .where((post) {
              final url = post.thumbnailImageUrl.toLowerCase();
              return url.endsWith('.mp4') ||
                  url.endsWith('.mov') ||
                  url.endsWith('.avi') ||
                  url.endsWith('.webm') ||
                  url.contains('/videos/');
            })
            .map((post) => post.thumbnailImageUrl)
            .toSet() // 중복 제거
            .toList();

    // 🎯 이미지 프리캐싱 (병렬 처리)
    if (imagesToCache.isNotEmpty) {
      print('[HomeDataService] 이미지 ${imagesToCache.length}개 배치 프리로드 시작');
      final imageFutures =
          imagesToCache.map((url) {
            return precacheImage(NetworkImage(url), context).catchError((e) {
              print('[HomeDataService] 이미지 프리캐싱 실패: $url');
            });
          }).toList();

      try {
        await Future.wait(imageFutures, eagerError: false);
        print('[HomeDataService] ✅ 이미지 배치 프리로드 완료: ${imagesToCache.length}개');
      } catch (e) {
        print('[HomeDataService] 이미지 배치 프리로드 중 오류: $e');
      }
    }

    // 🎯 비디오 프리로드 (VideoCacheService 사용, 비동기 처리)
    if (videosToCache.isNotEmpty) {
      print('[HomeDataService] 비디오 ${videosToCache.length}개 배치 프리로드 시작');
      // 비동기로 처리 (이미지 로드를 막지 않음)
      Future.microtask(() async {
        final videoCacheService = VideoCacheService();
        for (final videoUrl in videosToCache) {
          try {
            // VideoCacheService를 통해 컨트롤러 생성 (프리로드)
            videoCacheService.getOrCreateController(
              videoUrl,
              namespace: 'home',
            );
            print('[HomeDataService] 비디오 프리로드 시작: $videoUrl');
          } catch (e) {
            print('[HomeDataService] 비디오 프리로드 실패: $videoUrl - $e');
          }
        }
        print(
          '[HomeDataService] ✅ 비디오 배치 프리로드 요청 완료: ${videosToCache.length}개',
        );
      });
    }
  }

  /// 캐시 무효화
  void invalidateCache({String? type}) {
    if (type != null) {
      _cache.invalidateCache(type);
    } else {
      _cache.clearAll();
    }
  }

  /// 친구글 직접 로드
  Future<List<Map<String, dynamic>>> _loadFriendsPostsDirect({
    int page = 0,
    int size = 10,
  }) async {
    return _blogService.getFriendsPosts(page: page, size: size);
  }

  /// 전체글 직접 로드
  Future<List<Map<String, dynamic>>> _loadAllPostsDirect({
    int page = 0,
    int size = 10,
  }) async {
    return _blogService.getRecommendedPosts(page: page, size: size);
  }
}
