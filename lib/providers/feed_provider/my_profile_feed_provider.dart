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
  Map<String, dynamic>? _cachedUserInfo;
  List<Map<String, dynamic>>? _cachedPosts;
  Map<String, List<Map<String, dynamic>>>? _cachedSystemCategoryMappings;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5); // 5분 캐시

  // Getters 구현
  @override
  String? get username => _username;
  @override
  bool get isLoading => _loading;
  @override
  bool get isLoadingMore => _loadingMore;
  @override
  bool get hasMore => _hasMore;

  bool get _isCacheValid {
    if (_lastCacheTime == null) return false;
    return DateTime.now().difference(_lastCacheTime!) < _cacheValidDuration;
  }

  @override
  Future<void> loadInitial({String? username, bool force = false}) async {
    // 내 피드는 항상 현재 로그인한 사용자
    if (_loading) return;

    final String? myUsername = await authService.getUsername();
    if (myUsername == null) return;

    _username = myUsername;

    // 캐시 확인 (force가 아닌 경우)
    if (!force && _isCacheValid && _cachedUserInfo != null) {
      debugPrint('[MyProfileFeedProvider] 캐시에서 로드');
      _loadFromCache();
      notifyListeners();
      return;
    }

    debugPrint('[MyProfileFeedProvider] 서버에서 로드 시작: $_username');

    _loading = true;
    _hasMore = true;
    notifyListeners();

    try {
      // 통합 API 호출: 스키마 + 포스트
      // getProfileFeed는 이미 { success, data, message }에서 data만 추출해서 반환
      final feedData = await blogService.getProfileFeed(
        _username!,
        page: 0,
        size: pageSize,
      );

      // feedData는 이미 data 필드의 내용 (ProfileFeedSchemaAndPostsResponse)
      // processServerResponse에 전달하기 위해 { data: feedData } 형태로 래핑
      final feedResp = {'data': feedData};

      // 부모 클래스의 공통 처리 로직 사용
      processServerResponse(feedResp);
      setNetworkError(null); // 성공 시 에러 클리어

      // 페이지네이션 처리
      final postsData = feedData['posts'] as Map<String, dynamic>?;
      _currentPage = 0;
      _hasMore = postsData?['hasNext'] ?? false;

      // 캐시에 저장
      _saveToCache();

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
  void _loadFromCache() {
    if (_cachedUserInfo != null)
      userInfoInternal = Map<String, dynamic>.from(_cachedUserInfo!);

    if (_cachedPosts != null) {
      postsInternal.clear();
      postsInternal.addAll(
        _cachedPosts!.map((e) => Map<String, dynamic>.from(e)),
      );
    }

    if (_cachedSystemCategoryMappings != null) {
      systemCategoryMappingsInternal = _cachedSystemCategoryMappings!.map(
        (key, value) => MapEntry(
          key,
          value.map((e) => Map<String, dynamic>.from(e)).toList(),
        ),
      );
    }
  }

  /// 캐시에 데이터 저장
  void _saveToCache() {
    _cachedUserInfo =
        userInfoInternal != null
            ? Map<String, dynamic>.from(userInfoInternal!)
            : null;
    _cachedPosts =
        postsInternal.map((e) => Map<String, dynamic>.from(e)).toList();
    _cachedSystemCategoryMappings = systemCategoryMappingsInternal?.map(
      (key, value) => MapEntry(
        key,
        value.map((e) => Map<String, dynamic>.from(e)).toList(),
      ),
    );
    _lastCacheTime = DateTime.now();

    debugPrint('[MyProfileFeedProvider] 캐시 저장 완료');
  }

  /// 캐시 무효화
  void invalidateCache() {
    _cachedUserInfo = null;
    _cachedPosts = null;
    _cachedSystemCategoryMappings = null;
    _lastCacheTime = null;
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
      if (_cachedUserInfo != null) {
        _cachedUserInfo!['profileImageUrl'] = imageUrl;
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
        if (_cachedUserInfo != null) {
          _cachedUserInfo!['profileImageUrl'] = '';
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

    // 캐시 데이터도 업데이트
    if (_cachedPosts != null) {
      final cachedIdx = _cachedPosts!.indexWhere(
        (p) => p['id']?.toString() == postId,
      );
      if (cachedIdx != -1) {
        final existingCachedPost = _cachedPosts![cachedIdx];
        _cachedPosts![cachedIdx] = Map<String, dynamic>.from({
          ...existingCachedPost,
          ...updatedPost,
        });
      } else {
        // 캐시에도 없으면 추가
        _cachedPosts!.insert(0, Map<String, dynamic>.from(updatedPost));
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
    if (_cachedPosts != null) {
      _cachedPosts!.removeWhere((p) => p['id']?.toString() == postId);
    }

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
      if (_cachedPosts != null) {
        final cachedIdx = _cachedPosts!.indexWhere(
          (p) => (p['id'] as int?) == postIdInt,
        );
        if (cachedIdx != -1) {
          final cachedPost = _cachedPosts![cachedIdx];
          _cachedPosts!.removeAt(cachedIdx);
          _cachedPosts!.insert(0, cachedPost);
          // 캐시의 globalIndex도 업데이트
          for (int i = 0; i < _cachedPosts!.length; i++) {
            _cachedPosts![i]['globalIndex'] = i;
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
      final feedData = await blogService.getProfileFeed(
        _username!,
        page: _currentPage + 1,
        size: pageSize,
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
        _saveToCache();
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
        _saveToCache();
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
