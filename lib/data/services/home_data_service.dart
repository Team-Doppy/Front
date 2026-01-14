import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/data/services/video_cache_service.dart';
import 'package:doppy/image/utils/read_image_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ✅ compute용: server 응답을 PostData로 파싱하는 무거운 작업을 background isolate로 이동
Map<String, dynamic> _parseHomeDataInBackground(Map<String, dynamic> args) {
  final friendsRaw = (args['friends'] as List?)?.cast<Map>() ?? const <Map>[];
  final allRaw = (args['all'] as List?)?.cast<Map>() ?? const <Map>[];

  final friends =
      friendsRaw
          .map(
            (e) =>
                PostData.fromServerMeta(
                  Map<String, dynamic>.from(e),
                ).toPrimitiveMap(),
          )
          .toList();
  final all =
      allRaw
          .map(
            (e) =>
                PostData.fromServerMeta(
                  Map<String, dynamic>.from(e),
                ).toPrimitiveMap(),
          )
          .toList();

  return {'friends': friends, 'all': all};
}

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
      // 통합 API로 두 섹션 데이터를 한 번에 로드
      final homeFeedData = await _blogService.getHomeFeedData(
        page: page,
        size: size,
      );

      // 🎯 스플래시 스피너/애니메이션이 끊기지 않도록, PostData 파싱을 compute(isolate)로 이동
      final parsed = await compute(_parseHomeDataInBackground, {
        'friends': homeFeedData['friends'] ?? [],
        'all': homeFeedData['all'] ?? [],
      });

      final friendsPosts =
          (parsed['friends'] as List)
              .cast<Map>()
              .map(
                (m) => PostData.fromPrimitiveMap(Map<String, dynamic>.from(m)),
              )
              .toList();
      final allPosts =
          (parsed['all'] as List)
              .cast<Map>()
              .map(
                (m) => PostData.fromPrimitiveMap(Map<String, dynamic>.from(m)),
              )
              .toList();

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
      final posts = serverData.map((e) => PostData.fromServerMeta(e)).toList();

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
      final posts = serverData.map((e) => PostData.fromServerMeta(e)).toList();

      // 캐시 저장
      _cache.cacheFeedData('all', posts, page, size);

      return posts;
    } catch (e) {
      rethrow;
    }
  }

  /// 이미지와 비디오 배치 프리캐싱 (처음 몇 개만 동기, 나머지는 비동기)
  ///
  /// - 처음 [syncCount]개만 await로 프리로드 (즉시 보일 이미지)
  /// - 나머지는 비동기로 백그라운드에서 처리 (메모리 절약)
  Future<void> precacheImages(
    List<PostData> posts,
    BuildContext context, {
    int syncCount = 3, // 처음 몇 개만 동기 프리로드
    bool preloadVideos = false, // ✅ 초기 구간 jank 방지용
  }) async {
    if (posts.isEmpty) return;

    // 🎯 이미지 URL 추출 (비디오 제외)
    // ✅ 카드(PostCard)가 기본 NetworkImage(ResizeImage width=800)를 쓰므로 동일 provider로 프리캐시
    // (프리캐시와 실제 렌더가 다른 provider면 imageCache 키가 달라 체감이 안 날 수 있음)
    final Set<String> urlsToCache = <String>{};
    for (final post in posts) {
      final url = post.thumbnailUrlForCache.trim();
      if (url.isEmpty) continue;
      final lower = url.toLowerCase();
      if (!lower.startsWith('http')) continue;
      // 🎯 비디오 파일(.mp4, .mov 등) 제외 - 이미지만 프리캐시
      final isVideo =
          lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.webm') ||
          lower.contains('/videos/');
      if (isVideo) continue;
      urlsToCache.add(url);
    }

    final urls = urlsToCache.toList();
    const int cardMemCacheWidth = 800; // PostCard의 memCacheWidth와 맞춤

    if (urls.isEmpty) {
      // 이미지가 없으면 비디오만 처리(옵션)
      if (preloadVideos) {
        _preloadVideosAsync(posts);
      }
      return;
    }

    // 🎯 처음 syncCount개만 동기 프리로드 (await)
    final syncUrls = urls.take(syncCount).toList();
    final asyncUrls = urls.skip(syncCount).toList();

    if (syncUrls.isNotEmpty) {
      debugPrint('[HomeDataService] 이미지 ${syncUrls.length}개 동기 프리로드 시작');
      final syncFutures =
          syncUrls.map((url) {
            return precacheImage(
              ReadImageProvider.build(url: url, decodeWidth: cardMemCacheWidth),
              context,
            ).catchError((_) {
              debugPrint('[HomeDataService] 이미지 프리캐싱 실패: $url');
            });
          }).toList();

      try {
        await Future.wait(syncFutures, eagerError: false);
        debugPrint('[HomeDataService] ✅ 동기 프리로드 완료: ${syncUrls.length}개');
      } catch (e) {
        debugPrint('[HomeDataService] 동기 프리로드 중 오류: $e');
      }
    }

    // 🎯 나머지는 비동기로 백그라운드 처리 (모두 병렬)
    if (asyncUrls.isNotEmpty) {
      debugPrint('[HomeDataService] 이미지 ${asyncUrls.length}개 비동기 프리로드 시작');
      Future.microtask(() async {
        final futures =
            asyncUrls.map((url) {
              return precacheImage(
                ReadImageProvider.build(
                  url: url,
                  decodeWidth: cardMemCacheWidth,
                ),
                context,
              ).catchError((_) {
                debugPrint('[HomeDataService] 비동기 프리캐싱 실패: $url');
              });
            }).toList();

        try {
          await Future.wait(futures, eagerError: false);
          debugPrint('[HomeDataService] ✅ 비동기 프리로드 완료: ${asyncUrls.length}개');
        } catch (e) {
          debugPrint('[HomeDataService] 비동기 프리로드 중 오류: $e');
        }
      });
    }

    // 🎯 비디오 프리로드 (옵션)
    if (preloadVideos) {
      _preloadVideosAsync(posts);
    }
  }

  /// 비디오 비동기 프리로드
  void _preloadVideosAsync(List<PostData> posts) {
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
            .toSet()
            .toList();

    if (videosToCache.isEmpty) return;

    debugPrint('[HomeDataService] 비디오 ${videosToCache.length}개 배치 프리로드 시작');
    Future.microtask(() async {
      final videoCacheService = VideoCacheService();
      for (final videoUrl in videosToCache) {
        try {
          videoCacheService.getOrCreateController(videoUrl, namespace: 'home');
          debugPrint('[HomeDataService] 비디오 프리로드 시작: $videoUrl');
        } catch (e) {
          debugPrint('[HomeDataService] 비디오 프리로드 실패: $videoUrl - $e');
        }
      }
      debugPrint(
        '[HomeDataService] ✅ 비디오 배치 프리로드 요청 완료: ${videosToCache.length}개',
      );
    });
  }

  /// 스플래시에서 사용: 처음 몇 개 이미지만 비동기로 시작 (await 없이)
  void startPreloadingImagesInBackground(
    List<PostData> posts,
    BuildContext context, {
    int count = 5,
  }) {
    if (posts.isEmpty) return;

    final Set<String> urlsToCache = <String>{};
    for (final post in posts) {
      final url = post.thumbnailUrlForCache.trim();
      if (url.isEmpty) continue;
      final lower = url.toLowerCase();
      if (!lower.startsWith('http')) continue;
      final isVideo =
          lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.webm') ||
          lower.contains('/videos/');
      if (isVideo) continue;
      urlsToCache.add(url);
      if (urlsToCache.length >= count) break;
    }

    final urls = urlsToCache.toList();
    const int cardMemCacheWidth = 800; // PostCard의 memCacheWidth와 맞춤

    if (urls.isEmpty) return;

    debugPrint('[HomeDataService] 스플래시에서 이미지 ${urls.length}개 비동기 프리로드 시작');
    Future.microtask(() async {
      final futures =
          urls.map((url) {
            return precacheImage(
              ReadImageProvider.build(url: url, decodeWidth: cardMemCacheWidth),
              context,
            ).catchError((_) {
              debugPrint('[HomeDataService] 스플래시 프리캐싱 실패: $url');
            });
          }).toList();

      try {
        await Future.wait(futures, eagerError: false);
        debugPrint('[HomeDataService] ✅ 스플래시 비동기 프리로드 완료: ${urls.length}개');
      } catch (e) {
        debugPrint('[HomeDataService] 스플래시 프리로드 중 오류: $e');
      }
    });
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
    // 통합 API 사용
    final homeFeedData = await _blogService.getHomeFeedData(
      page: page,
      size: size,
    );
    return homeFeedData['friends'] ?? [];
  }

  /// 전체글 직접 로드
  Future<List<Map<String, dynamic>>> _loadAllPostsDirect({
    int page = 0,
    int size = 10,
  }) async {
    // 통합 API 사용
    final homeFeedData = await _blogService.getHomeFeedData(
      page: page,
      size: size,
    );
    return homeFeedData['all'] ?? [];
  }
}
