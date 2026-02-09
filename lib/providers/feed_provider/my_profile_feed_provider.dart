import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'base_feed_provider.dart';
import '../user_provider.dart';
import '../../utils/network_utils.dart';

/// 내 피드 전용 Provider (캐시 포함)
class MyProfileFeedProvider extends BaseFeedProvider {
  // 싱글톤 패턴
  static final MyProfileFeedProvider _instance =
      MyProfileFeedProvider._internal();
  factory MyProfileFeedProvider() => _instance;
  MyProfileFeedProvider._internal();

  // 독립적인 상태 관리
  String? _username;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  bool _hasUserReordered = false;

  bool get hasUserReordered => _hasUserReordered;

  // 내 피드 캐시
  final Map<String, _FeedCacheEntry> _cacheByFilterKey = {};
  static const Duration _cacheValidDuration = Duration(minutes: 5); // 5분 캐시
  String _activeFilterKey = '';

  // Getters 구현
  @override
  String? get username => _username;
  @override
  bool get isLoading => _loading;
  @override
  bool get isLoadingMore => _loadingMore;
  @override
  bool get hasMore => _hasMore;

  bool _isCacheValid(String filterKey) {
    final entry = _cacheByFilterKey[filterKey];
    if (entry == null) return false;
    return DateTime.now().difference(entry.cachedAt) < _cacheValidDuration;
  }

  @override
  Future<void> loadInitial({String? username, bool force = false}) async {
    // 내 피드는 항상 현재 로그인한 사용자
    if (_loading) return;

    final String? myUsername = await authService.getUsername();
    if (myUsername == null) return;

    _username = myUsername;

    final filterKey =
        '${serverPhase ?? ''}|${serverLifePhase ?? ''}|${serverAccessLevel ?? ''}|$pageSize';
    _activeFilterKey = filterKey;

    // 캐시 확인 (force가 아닌 경우) + 동일 필터일 때만
    if (!force && _isCacheValid(filterKey)) {
      debugPrint('[MyProfileFeedProvider] 캐시에서 로드');
      _loadFromCache(filterKey);
      notifyListeners();
      return;
    }

    debugPrint('[MyProfileFeedProvider] 서버에서 로드 시작: $_username');

    _loading = true;
    _hasMore = true;
    notifyListeners();

    try {
      // 통합 API 호출: 스키마 + 포스트
      // ✅ API 명세: 서버에서 phase와 accessLevel 모두 필터링
      // getProfileFeed는 이미 { success, data, message }에서 data만 추출해서 반환
      debugPrint(
        '[MyProfileFeedProvider] 서버 요청: username=$_username, '
        'phase=$serverPhase, lifePhase=$serverLifePhase, '
        'accessLevel=$serverAccessLevel, pageSize=$pageSize',
      );
      final feedData = await blogService.getProfileFeed(
        _username!,
        page: 0,
        size: pageSize,
        phase: serverPhase,
        lifePhase: serverLifePhase,
        accessLevel: serverAccessLevel, // ✅ API 명세에 따라 서버에 accessLevel 전달
      );

      // feedData는 이미 data 필드의 내용 (ProfileFeedSchemaAndPostsResponse)
      // processServerResponse에 전달하기 위해 { data: feedData } 형태로 래핑
      final feedResp = {'data': feedData};

      // 부모 클래스의 공통 처리 로직 사용
      processServerResponse(feedResp);
      setNetworkError(null); // 성공 시 에러 클리어

      // 페이지네이션 처리
      final postsData = feedData['posts'] as Map<String, dynamic>?;
      final postsList = postsData?['posts'] as List?;
      _currentPage = 0;
      _hasMore = postsData?['hasNext'] ?? false;

      debugPrint(
        '[MyProfileFeedProvider] 서버 응답 처리 완료: '
        'totalElements=${postsData?['totalElements']}, '
        'posts.length=${postsList?.length ?? 0}, '
        'hasNext=$_hasMore',
      );

      // 캐시에 저장
      _saveToCache(filterKey);

      debugPrint('[MyProfileFeedProvider] 서버 로드 완료');
    } catch (e) {
      debugPrint('[MyProfileFeedProvider] 서버 로드 실패: $e');
      debugPrint('[MyProfileFeedProvider] 에러 타입: ${e.runtimeType}');
      debugPrint('[MyProfileFeedProvider] 에러 내용: ${e.toString()}');

      // 네트워크 에러 처리
      final networkError = NetworkUtils.parseError(e);
      debugPrint(
        '[MyProfileFeedProvider] 변환된 NetworkError: ${networkError.type} - ${networkError.userMessage}',
      );
      setNetworkError(networkError);
      debugPrint('[MyProfileFeedProvider] networkError 설정 완료');

      // clearData()를 호출하지 않음 (networkError는 유지)
      // 네트워크 오류 시에는 데이터를 유지하여 에러 상태 표시 가능
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 캐시에서 데이터 로드
  void _loadFromCache(String filterKey) {
    final entry = _cacheByFilterKey[filterKey];
    if (entry == null) return;

    userInfoInternal =
        entry.userInfo != null
            ? Map<String, dynamic>.from(entry.userInfo!)
            : null;

    postsInternal
      ..clear()
      ..addAll(entry.posts.map((e) => Map<String, dynamic>.from(e)));

    systemCategoryMappingsInternal = entry.systemCategoryMappings?.map(
      (key, value) => MapEntry(
        key,
        value.map((e) => Map<String, dynamic>.from(e)).toList(),
      ),
    );

    _currentPage = entry.currentPage;
    _hasMore = entry.hasMore;
  }

  /// 캐시에 데이터 저장
  void _saveToCache(String filterKey) {
    _cacheByFilterKey[filterKey] = _FeedCacheEntry(
      cachedAt: DateTime.now(),
      userInfo:
          userInfoInternal != null
              ? Map<String, dynamic>.from(userInfoInternal!)
              : null,
      posts: postsInternal.map((e) => Map<String, dynamic>.from(e)).toList(),
      systemCategoryMappings: systemCategoryMappingsInternal?.map(
        (key, value) => MapEntry(
          key,
          value.map((e) => Map<String, dynamic>.from(e)).toList(),
        ),
      ),
      currentPage: _currentPage,
      hasMore: _hasMore,
    );

    debugPrint('[MyProfileFeedProvider] 캐시 저장 완료: filterKey=$filterKey');
  }

  /// 캐시 무효화
  void invalidateCache() {
    _cacheByFilterKey.clear();
    _activeFilterKey = '';
    debugPrint('[MyProfileFeedProvider] 캐시 무효화');
  }

  /// 프로필 이미지 업로드 후 업데이트
  Future<void> updateProfileImageAfterUpload(
    String imageUrl,
    BuildContext context,
  ) async {
    try {
      await context.read<UserProvider>().updateProfileImage(imageUrl: imageUrl);

      // 현재 userInfo와 캐시 업데이트
      if (userInfoInternal != null) {
        userInfoInternal!['profileImageUrl'] = imageUrl;
      }
      for (final entry in _cacheByFilterKey.values) {
        if (entry.userInfo != null) {
          entry.userInfo!['profileImageUrl'] = imageUrl;
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint(
        '[MyProfileFeedProvider] updateProfileImageAfterUpload 실패: $e',
      );
      rethrow;
    }
  }

  /// 프로필 이미지 삭제 후 업데이트
  Future<bool> deleteProfileImageAndUpdateCache(BuildContext context) async {
    try {
      final success = await context.read<UserProvider>().deleteProfileImage(
        context,
      );

      if (success) {
        // 현재 userInfo와 캐시 업데이트
        if (userInfoInternal != null) {
          userInfoInternal!['profileImageUrl'] = '';
        }
        for (final entry in _cacheByFilterKey.values) {
          if (entry.userInfo != null) {
            entry.userInfo!['profileImageUrl'] = '';
          }
        }

        notifyListeners();
      }

      return success;
    } catch (e) {
      debugPrint(
        '[MyProfileFeedProvider] deleteProfileImageAndUpdateCache 실패: $e',
      );
      return false;
    }
  }

  /// 포스트 추가/수정 시 캐시 업데이트
  void updatePostInCache(Map<String, dynamic> updatedPost) {
    final postId = updatedPost['id']?.toString();
    if (postId == null) return;

    // 현재 데이터 업데이트
    final idx = postsInternal.indexWhere((p) => p['id']?.toString() == postId);
    if (idx != -1) {
      // 기존 포스트 데이터와 병합 (모든 필드 업데이트)
      final existingPost = postsInternal[idx];
      postsInternal[idx] = {...existingPost, ...updatedPost};
    } else {
      // 포스트가 없으면 추가 (새로 발행된 경우)
      postsInternal.insert(0, updatedPost);
    }

    // 캐시 데이터도 업데이트 (현재 탭/필터 기준)
    final activeCache = _cacheByFilterKey[_activeFilterKey];
    if (activeCache != null) {
      final cachedIdx = activeCache.posts.indexWhere(
        (p) => p['id']?.toString() == postId,
      );
      if (cachedIdx != -1) {
        final existingCachedPost = activeCache.posts[cachedIdx];
        activeCache.posts[cachedIdx] = Map<String, dynamic>.from({
          ...existingCachedPost,
          ...updatedPost,
        });
      } else {
        // 캐시에도 없으면 추가
        activeCache.posts.insert(0, Map<String, dynamic>.from(updatedPost));
      }
    }

    notifyListeners();
    debugPrint('[MyProfileFeedProvider] ✅ 포스트 캐시 업데이트 완료: $postId');
  }

  /// 포스트 삭제 시 캐시 업데이트
  void removePostFromCache(String postId) {
    // 현재 데이터에서 제거
    postsInternal.removeWhere((p) => p['id']?.toString() == postId);

    // 캐시 데이터에서도 제거
    final activeCache = _cacheByFilterKey[_activeFilterKey];
    activeCache?.posts.removeWhere((p) => p['id']?.toString() == postId);

    notifyListeners();
  }

  /// 🎯 새로 발행한 글을 맨 앞에 배치
  /// 기존 순서는 유지하고 새 글만 맨 앞으로 이동
  /// 서버와도 순서 동기화를 수행합니다.
  Future<void> moveNewPostToFront(String postId) async {
    try {
      final postIdInt = int.tryParse(postId);
      if (postIdInt == null) {
        debugPrint(
          '[MyProfileFeedProvider] moveNewPostToFront: 유효하지 않은 postId: $postId',
        );
        return;
      }

      // 현재 데이터에서 찾기
      final idx = postsInternal.indexWhere(
        (p) => (p['id'] as int?) == postIdInt,
      );
      if (idx == -1) {
        debugPrint(
          '[MyProfileFeedProvider] moveNewPostToFront: 포스트를 찾을 수 없음: $postId',
        );
        return;
      }

      // 이미 맨 앞에 있으면 아무것도 하지 않음
      if (idx == 0) {
        debugPrint(
          '[MyProfileFeedProvider] moveNewPostToFront: 이미 맨 앞에 있음: $postId',
        );
        return;
      }

      // 🎯 로컬에서 먼저 맨 앞으로 이동 (낙관적 업데이트)
      final foundPost = postsInternal[idx];
      postsInternal.removeAt(idx);
      postsInternal.insert(0, foundPost);

      // globalIndex 업데이트
      for (int i = 0; i < postsInternal.length; i++) {
        postsInternal[i]['globalIndex'] = i;
      }

      // 캐시도 업데이트
      final activeCache = _cacheByFilterKey[_activeFilterKey];
      if (activeCache != null) {
        final cachedIdx = activeCache.posts.indexWhere(
          (p) => (p['id'] as int?) == postIdInt,
        );
        if (cachedIdx != -1) {
          final cachedPost = activeCache.posts[cachedIdx];
          activeCache.posts.removeAt(cachedIdx);
          activeCache.posts.insert(0, cachedPost);
          // 캐시의 globalIndex도 업데이트
          for (int i = 0; i < activeCache.posts.length; i++) {
            activeCache.posts[i]['globalIndex'] = i;
          }
        }
      }

      notifyListeners();
      debugPrint('[MyProfileFeedProvider] ✅ 새 글을 맨 앞에 배치 완료 (로컬): $postId');

      // 🎯 서버와 순서 동기화 (실패해도 시스템이 뻑나지 않도록 안전하게 처리)
      try {
        final orderedPostIds =
            postsInternal.map((post) => '${post['id']}').toList();
        await reorderPosts(orderedPostIds);
        debugPrint('[MyProfileFeedProvider] ✅ 새 글 순서 서버 동기화 완료: $postId');
      } catch (e, stackTrace) {
        // 서버 동기화 실패해도 로컬 순서는 유지 (사용자 경험 우선)
        debugPrint(
          '[MyProfileFeedProvider] ⚠️ 새 글 순서 서버 동기화 실패 (로컬 순서는 유지됨): $e',
        );
        debugPrint('[MyProfileFeedProvider] 스택 트레이스: $stackTrace');
        // 에러를 다시 throw하지 않음 - 로컬 상태는 이미 변경되었으므로 그대로 유지
      }
    } catch (e, stackTrace) {
      // 예상치 못한 에러 발생 시에도 시스템이 뻑나지 않도록 안전하게 처리
      debugPrint('[MyProfileFeedProvider] ⚠️ moveNewPostToFront 예상치 못한 에러: $e');
      debugPrint('[MyProfileFeedProvider] 스택 트레이스: $stackTrace');
      // 에러를 다시 throw하지 않음 - 시스템 안정성 우선
    }
  }

  @override
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _username == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      // getProfileFeed는 이미 { success, data, message }에서 data만 추출해서 반환
      // 전용 탭에서는 phase/lifePhase 필터를 유지해야 함
      final feedData = await blogService.getProfileFeed(
        _username!,
        page: _currentPage + 1,
        size: pageSize,
        phase: serverPhase,
        lifePhase: serverLifePhase,
        accessLevel: serverAccessLevel,
      );

      // feedData는 이미 data 필드의 내용 (ProfileFeedSchemaAndPostsResponse)
      final postsData = feedData['posts'] as Map<String, dynamic>?;
      final List<dynamic> newPosts = postsData?['posts'] ?? [];
      final hasNext = postsData?['hasNext'] ?? false;

      if (newPosts.isEmpty) {
        _hasMore = false;
      } else {
        // 새 포스트를 배열 순서대로 추가 (서버에서 이미 정렬되어 옴)
        for (final postData in newPosts) {
          if (postData is Map<String, dynamic>) {
            postsInternal.add(postData);
          }
        }

        _currentPage++;
        _hasMore = hasNext;

        // 캐시 업데이트
        _saveToCache(_activeFilterKey);
      }
    } catch (e) {
      debugPrint('[MyProfileFeedProvider] loadMore 실패: $e');
      _hasMore = false;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  @override
  void logout() {
    clearData();
    _loading = false;
    _loadingMore = false;
    _hasMore = true;
    _username = null;
    _currentPage = 0;
    invalidateCache();
    // 선택 상태도 초기화
    selectBase(BaseFilter.all);
    notifyListeners();
    debugPrint('[MyProfileFeedProvider] 로그아웃 - 모든 데이터 초기화 완료');
  }

  @override
  void clearInMemory() {
    clearData();
    _loading = false;
    _loadingMore = false;
    // 캐시는 유지 (메모리 정리 시에는 캐시 보존)
    // 화면 dispose 중에는 알림을 보내지 않음 (프레임 락 방지)
  }

  /// 주어진 순서를 로컬에 즉시 반영
  @override
  void reorderPostsLocally(List<String> orderedPostIds) {
    reorderPostsLocallyImpl(orderedPostIds);
  }

  @override
  Future<void> reorderPosts(List<String> postIds) async {
    try {
      // 문자열 ID를 정수로 변환
      final orderedIntIds =
          postIds
              .map((id) => int.tryParse(id))
              .where((id) => id != null)
              .cast<int>()
              .toList();

      if (orderedIntIds.isEmpty) {
        debugPrint('[MyProfileFeedProvider] 유효한 포스트 ID가 없음');
        return;
      }

      // 낙관적 업데이트: 먼저 로컬에서 순서 변경
      final prevPosts = List<Map<String, dynamic>>.from(postsProtected);
      reorderPostsLocally(postIds);

      try {
        // 서버에 순서 변경 요청
        await blogService.reorderPosts(orderedIntIds);
        debugPrint('[MyProfileFeedProvider] 포스트 순서 서버 저장 성공');

        // 캐시 업데이트
        _saveToCache(_activeFilterKey);
      } catch (e) {
        debugPrint('⚠️ [MyProfileFeedProvider] 서버 포스트 순서 변경 실패, 롤백: $e');

        // 실패 시 롤백
        postsProtected.clear();
        postsProtected.addAll(prevPosts);
        notifyListeners();
        rethrow;
      }
    } catch (e) {
      debugPrint('[MyProfileFeedProvider] 포스트 순서 변경 실패: $e');
      rethrow;
    }
  }
}

class _FeedCacheEntry {
  _FeedCacheEntry({
    required this.cachedAt,
    required this.userInfo,
    required this.posts,
    required this.systemCategoryMappings,
    required this.currentPage,
    required this.hasMore,
  });

  final DateTime cachedAt;
  final Map<String, dynamic>? userInfo;
  final List<Map<String, dynamic>> posts;
  final Map<String, List<Map<String, dynamic>>>? systemCategoryMappings;
  final int currentPage;
  final bool hasMore;
}
