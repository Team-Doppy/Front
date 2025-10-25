import 'package:doppy/data/models/post_data.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/utils/network_utils.dart';
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
      print('[SmartFeedCache] LRU: 오래된 캐시 제거 - $oldestKey');
    }

    _cache[key] = CachedFeedData(
      posts: posts,
      cachedAt: DateTime.now(),
      page: page,
    );

    print('[SmartFeedCache] 캐시 저장: $key (${posts.length}개 포스트)');
  }

  /// 캐시된 피드 데이터 조회
  List<PostData>? getCachedFeedData(String type, int page, int size) {
    final key = _generateKey(type, page, size);
    final cached = _cache[key];

    if (cached == null) {
      print('[SmartFeedCache] 캐시 미스: $key');
      return null;
    }

    if (cached.isExpired) {
      _cache.remove(key);
      print('[SmartFeedCache] 캐시 만료: $key');
      return null;
    }

    print('[SmartFeedCache] 캐시 히트: $key (${cached.posts.length}개 포스트)');
    return cached.posts;
  }

  /// 특정 타입의 캐시 무효화
  void invalidateCache(String type) {
    final keysToRemove =
        _cache.keys.where((key) => key.startsWith(type)).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
    print('[SmartFeedCache] 캐시 무효화: $type (${keysToRemove.length}개 항목)');
  }

  /// 전체 캐시 클리어
  void clearAll() {
    final count = _cache.length;
    _cache.clear();
    print('[SmartFeedCache] 전체 캐시 클리어: ${count}개 항목');
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
  Future<HomeData> preloadAllSections({int page = 0, int size = 10}) async {
    print('[HomeDataService] 전체 섹션 프리로드 시작');

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

      print(
        '[HomeDataService] 전체 섹션 프리로드 완료: 친구글 ${friendsPosts.length}개, 전체글 ${allPosts.length}개',
      );
      return feedData;
    } catch (e) {
      print('[HomeDataService] 전체 섹션 프리로드 실패: $e');
      // 에러를 그대로 전파해서 홈화면에서 적절한 에러 UI 표시
      rethrow;
    }
  }

  /// 친구글 로드 (캐시 우선)
  Future<List<PostData>> loadFriendsPosts({
    int page = 0,
    int size = 10,
    bool refresh = false,
  }) async {
    print('[HomeDataService] 친구글 로드: page=$page, size=$size, refresh=$refresh');

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

      print('[HomeDataService] 친구글 로드 완료: ${posts.length}개');
      return posts;
    } catch (e) {
      print('[HomeDataService] 친구글 로드 실패: $e');
      rethrow;
    }
  }

  /// 전체글 로드 (캐시 우선)
  Future<List<PostData>> loadAllPosts({
    int page = 0,
    int size = 10,
    bool refresh = false,
  }) async {
    print('[HomeDataService] 전체글 로드: page=$page, size=$size, refresh=$refresh');

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

      print('[HomeDataService] 전체글 로드 완료: ${posts.length}개');
      return posts;
    } catch (e) {
      print('[HomeDataService] 전체글 로드 실패: $e');
      rethrow;
    }
  }

  /// 이미지 프리캐싱 (최적화된 버전)
  Future<void> precacheImages(
    List<PostData> posts,
    BuildContext context,
  ) async {
    if (posts.isEmpty) return;

    final imagesToCache =
        posts
            .take(3) // 최대 3개만
            .where((post) => post.thumbnailImageUrl.isNotEmpty)
            .map((post) => post.thumbnailImageUrl)
            .toSet() // 중복 제거
            .toList();

    if (imagesToCache.isEmpty) return;

    print('[FeedDataService] 이미지 프리캐싱 시작: ${imagesToCache.length}개');

    final futures =
        imagesToCache.map((url) {
          return precacheImage(NetworkImage(url), context).catchError((error) {
            print('[FeedDataService] 이미지 프리캐싱 실패: $url - $error');
          });
        }).toList();

    try {
      await Future.wait(futures, eagerError: false);
      print('[FeedDataService] 이미지 프리캐싱 완료');
    } catch (e) {
      print('[FeedDataService] 이미지 프리캐싱 부분 실패: $e');
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
    print('[HomeDataService] 친구글 직접 로드: page=$page, size=$size');
    return _blogService.getFriendsPosts(page: page, size: size);
  }

  /// 전체글 직접 로드
  Future<List<Map<String, dynamic>>> _loadAllPostsDirect({
    int page = 0,
    int size = 10,
  }) async {
    print('[HomeDataService] 전체글 직접 로드: page=$page, size=$size');
    return _blogService.getRecommendedPosts(page: page, size: size);
  }
}
