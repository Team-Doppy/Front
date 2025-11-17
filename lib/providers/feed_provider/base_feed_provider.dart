import 'package:flutter/material.dart';
import '../../data/services/blog_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/models/post_data.dart';
import '../../data/models/system_category_keys.dart';
import '../../utils/network_utils.dart';

// 카테고리 필터 타입
enum BaseFilter { all, private, friends, groups, public }

/// 피드 Provider의 공통 기능을 담은 추상 부모 클래스
abstract class BaseFeedProvider extends ChangeNotifier {
  final BlogService blogService = BlogService();
  final AuthService authService = AuthService();

  // 현재 활성 사용자의 데이터 (UI에서 사용)
  final List<Map<String, dynamic>> _categories = [];
  final Map<String, List<Map<String, dynamic>>> _postsByCategory = {};
  Map<String, dynamic>? _userInfo;
  Map<String, List<Map<String, dynamic>>>? _systemCategoryMappings;

  // 네트워크 에러 상태
  NetworkError? _networkError;

  // 자식에서 사용할 내부 접근자 (mutable)
  List<Map<String, dynamic>> get categoriesInternal => _categories;
  Map<String, List<Map<String, dynamic>>> get postsByCategoryInternal =>
      _postsByCategory;
  Map<String, dynamic>? get userInfoInternal => _userInfo;

  // Protected getter for child classes
  @protected
  Map<String, List<Map<String, dynamic>>> get postsByCategoryProtected =>
      _postsByCategory;
  set userInfoInternal(Map<String, dynamic>? v) => _userInfo = v;
  Map<String, List<Map<String, dynamic>>>? get systemCategoryMappingsInternal =>
      _systemCategoryMappings;
  set systemCategoryMappingsInternal(
    Map<String, List<Map<String, dynamic>>>? v,
  ) => _systemCategoryMappings = v;

  // 카테고리 선택 상태 관리
  BaseFilter _selectedBase = BaseFilter.all;
  String? _selectedCategoryId;
  bool _isReadOnly = false;

  // 페이지네이션 (공통 설정)
  int _pageSize = 20;
  int get pageSize => _pageSize;

  // 추상 getters - 자식 클래스에서 구현
  bool get isLoading;
  bool get isLoadingMore;
  bool get hasMore;
  String? get username;

  // Getters
  List<Map<String, dynamic>> get categories => List.unmodifiable(_categories);
  Map<String, List<Map<String, dynamic>>> get postsByCategory =>
      Map.unmodifiable(_postsByCategory);
  Map<String, dynamic>? get userInfo => _userInfo;
  Map<String, List<Map<String, dynamic>>>? get systemCategoryMappings =>
      _systemCategoryMappings;

  BaseFilter get selectedBase => _selectedBase;
  String? get selectedCategoryId => _selectedCategoryId;
  bool get isReadOnly => _isReadOnly;
  NetworkError? get networkError => _networkError;

  // 기존 호환성을 위한 posts getter
  List<Map<String, dynamic>> get posts {
    final allPosts = <Map<String, dynamic>>[];
    for (final categoryPosts in _postsByCategory.values) {
      allPosts.addAll(categoryPosts);
    }
    return List.unmodifiable(allPosts);
  }

  /// 데이터 클리어
  void clearData() {
    _categories.clear();
    _postsByCategory.clear();
    _userInfo = null;
    _systemCategoryMappings = null;
    _networkError = null;
  }

  /// 서버에서 데이터 로드 (추상 메서드 - 자식 클래스에서 구현)
  Future<void> loadInitial({String? username, bool force = false});

  /// 더 많은 포스트 로드 (추상 메서드)
  Future<void> loadMore();

  /// 특정 포스트 중심 오프셋 조회
  /// 이미 로드된 포스트는 재사용하고, 누락된 포스트만 API로 조회합니다.
  Future<void> loadPostsAround(String postId, {int size = 20}) async {
    if (username == null) {
      print('[BaseFeedProvider] loadPostsAround: username이 null입니다');
      return;
    }

    try {
      // 1. 스키마에서 globalIndex 확인
      final schemaResp = await blogService.getProfileSchema(username!);
      if (schemaResp['success'] != true) {
        print('[BaseFeedProvider] loadPostsAround: 스키마 조회 실패');
        return;
      }

      final schemaData = schemaResp['data'] as Map<String, dynamic>?;
      if (schemaData == null) {
        print('[BaseFeedProvider] loadPostsAround: 스키마 데이터가 null입니다');
        return;
      }

      // 2. 스키마에서 포스트 ID의 globalIndex 찾기
      final postsByCategoryData =
          schemaData['postsByCategory'] as Map<String, dynamic>?;
      if (postsByCategoryData == null) {
        print('[BaseFeedProvider] loadPostsAround: postsByCategory가 null입니다');
        return;
      }

      Map<String, dynamic>? targetPostOrder;
      for (final postOrders in postsByCategoryData.values) {
        if (postOrders is List) {
          for (final postOrder in postOrders) {
            if (postOrder is Map<String, dynamic>) {
              final postIdValue = postOrder['id'];
              if (postIdValue != null &&
                  postIdValue.toString() == postId.toString()) {
                targetPostOrder = postOrder;
                break;
              }
            }
          }
          if (targetPostOrder != null) break;
        }
      }

      if (targetPostOrder == null) {
        print(
          '[BaseFeedProvider] loadPostsAround: 포스트 ID $postId를 스키마에서 찾을 수 없습니다',
        );
        return;
      }

      final targetGlobalIndex = targetPostOrder['globalIndex'] as int?;
      if (targetGlobalIndex == null) {
        print(
          '[BaseFeedProvider] loadPostsAround: 포스트 ID $postId의 globalIndex가 null입니다',
        );
        return;
      }

      // 3. 이미 로드된 포스트 확인 (선택적 최적화)
      // 오프셋 조회 API는 항상 호출하여 최신 데이터를 받아오되,
      // 결과 병합 시 중복을 제거합니다.
      // 참고: 서버가 이미 필요한 포스트를 정렬된 순서로 반환하므로,
      // 클라이언트에서 미리 계산할 필요 없음

      // 4. 오프셋 조회 API 호출
      print(
        '[BaseFeedProvider] loadPostsAround: 포스트 ID $postId (globalIndex: $targetGlobalIndex) 중심으로 오프셋 조회',
      );
      final postsResp = await blogService.getProfilePostsAround(
        username!,
        postId,
        size: size,
      );

      if (postsResp['success'] == true) {
        final postsData = postsResp['data'] as Map<String, dynamic>?;
        if (postsData != null) {
          final List<dynamic> newPosts = postsData['posts'] ?? [];

          // 9. 기존 데이터와 병합 (중복 제거)
          final existingPostIds = <int, Map<String, dynamic>>{};
          for (final categoryPosts in _postsByCategory.values) {
            for (final post in categoryPosts) {
              final postIdValue = post['id'] as int?;
              if (postIdValue != null) {
                existingPostIds[postIdValue] = post;
              }
            }
          }

          // 10. 새 포스트를 카테고리별로 병합
          for (final newPost in newPosts) {
            if (newPost is! Map<String, dynamic>) continue;

            final postIdValue = newPost['id'] as int?;
            if (postIdValue == null) continue;

            final categoryId = (newPost['categoryId'] ?? 0).toString();

            if (existingPostIds.containsKey(postIdValue)) {
              // 이미 있는 포스트 → 업데이트 (더 최신 데이터 사용)
              final existingPost = existingPostIds[postIdValue]!;
              final updatedPost = {
                ...existingPost,
                ...newPost, // 새 데이터로 덮어쓰기
                'order': existingPost['order'], // order는 유지
              };

              // 기존 위치에서 교체
              final categoryPosts = _postsByCategory[categoryId] ?? [];
              final index = categoryPosts.indexWhere(
                (p) => (p['id'] as int?) == postIdValue,
              );
              if (index != -1) {
                categoryPosts[index] = updatedPost;
              }
            } else {
              // 새로운 포스트 → globalIndex 순서대로 삽입
              if (!_postsByCategory.containsKey(categoryId)) {
                _postsByCategory[categoryId] = [];
              }
              final categoryPosts = _postsByCategory[categoryId]!;
              final newPostGlobalIndex = newPost['globalIndex'] as int?;

              if (newPostGlobalIndex != null) {
                // globalIndex 기준으로 삽입 위치 찾기
                int insertIndex = categoryPosts.length;
                for (int i = 0; i < categoryPosts.length; i++) {
                  final existingGlobalIndex =
                      categoryPosts[i]['globalIndex'] as int?;
                  if (existingGlobalIndex != null &&
                      existingGlobalIndex > newPostGlobalIndex) {
                    insertIndex = i;
                    break;
                  }
                }
                categoryPosts.insert(insertIndex, newPost);
              } else {
                // globalIndex가 없으면 맨 뒤에 추가
                categoryPosts.add(newPost);
              }
            }
          }

          notifyListeners();
          print(
            '[BaseFeedProvider] loadPostsAround: 오프셋 조회 완료 - ${newPosts.length}개 포스트 병합',
          );
        }
      }
    } catch (e) {
      print('[BaseFeedProvider] loadPostsAround 실패: $e');
      rethrow;
    }
  }

  /// 새로고침
  Future<void> refresh() async => loadInitial(force: true);

  /// 네트워크 에러 설정
  void setNetworkError(NetworkError? error) {
    print('[BaseFeedProvider] setNetworkError 호출: $error');
    _networkError = error;
    // NetworkManager에 네트워크 상태 업데이트
    if (error != null) {
      print('[BaseFeedProvider] NetworkManager.setNetworkError(true) 호출');
      NetworkManager.setNetworkError(true);
    } else {
      print('[BaseFeedProvider] NetworkManager.setNetworkRecovered() 호출');
      NetworkManager.setNetworkRecovered();
    }
    print('[BaseFeedProvider] notifyListeners() 호출');
    notifyListeners();
  }

  /// 서버 응답 처리 (공통 로직)
  void processServerResponse(
    Map<String, dynamic> schemaResp,
    Map<String, dynamic> postsResp,
  ) {
    final schemaData = schemaResp['data'];
    final postsData = postsResp['data'];

    if (schemaData == null || postsData == null) {
      print('[BaseFeedProvider] 서버 응답의 data가 null입니다');
      clearData();
      return;
    }

    // 사용자 정보 저장
    _userInfo = schemaData['userInfo'];

    // 카테고리 정보 저장
    _categories.clear();
    final categoriesData = schemaData['categories'];
    if (categoriesData != null && categoriesData is List) {
      try {
        _categories.addAll(categoriesData.cast<Map<String, dynamic>>());
      } catch (e) {
        print('[BaseFeedProvider] 카테고리 데이터 캐스팅 실패: $e');
        for (final item in categoriesData) {
          if (item is Map<String, dynamic>) {
            _categories.add(item);
          }
        }
      }
    }

    // 카테고리별 포스트 저장
    _postsByCategory.clear();
    final postsByCategoryData = schemaData['postsByCategory'];
    if (postsByCategoryData != null &&
        postsByCategoryData is Map<String, dynamic>) {
      for (final entry in postsByCategoryData.entries) {
        if (entry.value is List) {
          try {
            _postsByCategory[entry.key] =
                (entry.value as List).cast<Map<String, dynamic>>();
          } catch (e) {
            print('[BaseFeedProvider] 포스트 데이터 캐스팅 실패 (카테고리 ${entry.key}): $e');
            final safePosts = <Map<String, dynamic>>[];
            for (final item in entry.value as List) {
              if (item is Map<String, dynamic>) {
                safePosts.add(item);
              }
            }
            _postsByCategory[entry.key] = safePosts;
          }
        }
      }
    }

    // 시스템 카테고리 매핑 저장
    final systemCategoryMappingsData = schemaData['systemCategoryMappings'];
    if (systemCategoryMappingsData != null &&
        systemCategoryMappingsData is Map<String, dynamic>) {
      _systemCategoryMappings = <String, List<Map<String, dynamic>>>{};
      for (final entry in systemCategoryMappingsData.entries) {
        if (entry.value is List) {
          final postIdMaps =
              (entry.value as List)
                  .map((postId) => {'postId': postId})
                  .toList();
          _systemCategoryMappings![entry.key] = postIdMaps;
        }
      }
    }

    // 포스트 데이터 병합
    final List<dynamic> newPosts = postsData['posts'] ?? [];

    // posts를 빠른 조회용 맵으로 구성
    final Map<int, Map<String, dynamic>> idToPost = {
      for (final p in newPosts)
        if (p['id'] != null) (p['id'] as int): p,
    };

    // postsByCategory 병합
    final keys = List<String>.from(_postsByCategory.keys);
    for (final key in keys) {
      final original = _postsByCategory[key] ?? const <Map<String, dynamic>>[];
      final merged = <Map<String, dynamic>>[];
      for (final item in original) {
        final pid = item['id'];
        if (pid is int && idToPost.containsKey(pid)) {
          final full = Map<String, dynamic>.from(idToPost[pid]!);
          // 스키마에서 order와 globalIndex 유지
          if (item.containsKey('order')) full['order'] = item['order'];
          if (item.containsKey('globalIndex')) {
            full['globalIndex'] = item['globalIndex'];
          }
          // 🎯 sharedGroupIds가 스키마에만 있고 posts에는 없는 경우를 대비해 명시적으로 보존
          // (일반적으로 posts에 있지만, 혹시 모를 경우를 대비)
          if (item.containsKey('sharedGroupIds') &&
              !full.containsKey('sharedGroupIds')) {
            full['sharedGroupIds'] = item['sharedGroupIds'];
          }
          // 🎯 디버깅: sharedGroupIds 확인
          if (full.containsKey('sharedGroupIds') &&
              full['accessLevel'] == 'GROUPS') {
            print(
              '[BaseFeedProvider] 포스트 ID ${pid}: sharedGroupIds = ${full['sharedGroupIds']}',
            );
          }
          merged.add(full);
        } else {
          merged.add(item);
        }
      }
      _postsByCategory[key] = merged;
    }

    // 페이지네이션은 자식 클래스에서 처리

    // 기본 선택 상태를 '전체'로 리셋
    _selectedCategoryId = null;
    _selectedBase = BaseFilter.all;
  }

  // 카테고리 선택 메서드들
  void selectBase(BaseFilter base) {
    if (_selectedBase == base && _selectedCategoryId == null) return;
    _selectedCategoryId = null;
    _selectedBase = base;
    notifyListeners();
  }

  void selectCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
  }

  void setReadOnly(bool readOnly) {
    if (_isReadOnly == readOnly) return;
    _isReadOnly = readOnly;
    notifyListeners();
  }

  /// 로그아웃 시 데이터 초기화 (추상 메서드)
  void logout();

  /// 화면을 나갈 때 데이터 초기화 (추상 메서드)
  void clearInMemory();

  /// 포스트 수 관련 getters
  int get totalPostCount {
    final publicCount = publicPostCount;
    final privateCount = privatePostCount;
    final friendsCount = friendsPostCount;
    final groupsCount = groupsPostCount;
    return publicCount + privateCount + friendsCount + groupsCount;
  }

  int get privatePostCount {
    if (_systemCategoryMappings == null) return 0;
    final postIds =
        _systemCategoryMappings![SystemCategoryKeys.private] as List?;
    final count = postIds?.length ?? 0;
    print('[BaseFeedProvider] privatePostCount: $count');
    return count;
  }

  int get publicPostCount {
    if (_systemCategoryMappings == null) return 0;
    final postIds =
        _systemCategoryMappings![SystemCategoryKeys.public] as List?;
    final count = postIds?.length ?? 0;
    print('[BaseFeedProvider] publicPostCount: $count');
    return count;
  }

  int get groupsPostCount {
    if (_systemCategoryMappings == null) return 0;
    final postIds =
        _systemCategoryMappings![SystemCategoryKeys.groups] as List?;
    final count = postIds?.length ?? 0;
    print('[BaseFeedProvider] groupsPostCount: $count');
    return count;
  }

  int get friendsPostCount {
    if (_systemCategoryMappings == null) return 0;
    final postIds =
        _systemCategoryMappings![SystemCategoryKeys.friends] as List?;
    final count = postIds?.length ?? 0;
    print('[BaseFeedProvider] friendsPostCount: $count');
    return count;
  }

  String get selectedLabel {
    if (_selectedCategoryId != null) {
      final category = _categories.firstWhere(
        (c) => c['id'].toString() == _selectedCategoryId,
        orElse: () => {'name': 'all'},
      );
      return category['name'] ?? 'all';
    }

    switch (_selectedBase) {
      case BaseFilter.all:
        return 'all';
      case BaseFilter.private:
        return 'private';
      case BaseFilter.friends:
        return 'friends';
      case BaseFilter.groups:
        return 'group';
      case BaseFilter.public:
        return 'public';
    }
  }

  /// 포스트 접근 레벨 업데이트 // my_profile_feed_provider.dart 에서만 사용
  void updatePostAccessLevelById(String postId, AccessLevel newLevel) {
    try {
      for (final categoryId in _postsByCategory.keys) {
        final posts = _postsByCategory[categoryId]!;
        final idx = posts.indexWhere((p) => '${p['id']}' == postId);
        if (idx != -1) {
          String level = 'PUBLIC';
          if (newLevel == AccessLevel.private) {
            level = 'PRIVATE';
          } else if (newLevel == AccessLevel.friends) {
            level = 'FRIENDS';
          } else if (newLevel == AccessLevel.groups) {
            level = 'GROUPS';
          }
          posts[idx]['accessLevel'] = level;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      print('[BaseFeedProvider] accessLevel 업데이트 실패: $e');
    }
  }

  /// 🎯 선택적 업데이트: 특정 포스트의 메타데이터만 업데이트 (서버 재조회 없음)
  /// 공개범위/썸네일/제목/요약 변경 시 전체 새로고침 대신 사용
  void updatePostMetadata(
    String postId, {
    String? thumbnailImageUrl,
    String? title,
    String? summary,
    String? accessLevel,
    List<int>? sharedGroupIds,
  }) {
    try {
      bool hasUpdate = false;
      for (final categoryId in _postsByCategory.keys) {
        final posts = _postsByCategory[categoryId]!;
        final idx = posts.indexWhere((p) => '${p['id']}' == postId);
        if (idx != -1) {
          // 변경된 필드만 업데이트
          if (thumbnailImageUrl != null) {
            posts[idx]['thumbnailImageUrl'] = thumbnailImageUrl;
            hasUpdate = true;
          }
          if (title != null) {
            posts[idx]['title'] = title;
            hasUpdate = true;
          }
          if (summary != null) {
            posts[idx]['summary'] = summary;
            hasUpdate = true;
          }
          if (accessLevel != null) {
            posts[idx]['accessLevel'] = accessLevel;
            hasUpdate = true;
          }
          if (sharedGroupIds != null) {
            if (sharedGroupIds.isEmpty) {
              posts[idx].remove('sharedGroupIds');
            } else {
              posts[idx]['sharedGroupIds'] = sharedGroupIds;
            }
            hasUpdate = true;
          }

          if (hasUpdate) {
            notifyListeners();
            print('✅ [BaseFeedProvider] 포스트 $postId 메타데이터 선택적 업데이트 완료');
          }
          return;
        }
      }
      print('⚠️ [BaseFeedProvider] 포스트 $postId를 찾을 수 없어 메타데이터 업데이트 불가');
    } catch (e) {
      print('[BaseFeedProvider] 포스트 메타데이터 업데이트 실패: $e');
    }
  }

  /// 포스트를 로컬에서 카테고리 간 이동 // my_profile_feed_provider.dart 에서만 사용
  void movePostLocally(
    String postId,
    int targetCategoryId, [
    int? targetPosition,
  ]) {
    try {
      Map<String, dynamic>? foundPost;
      String? sourceCategory;
      int? sourceIndex;

      // 원본 포스트 찾기
      for (final categoryId in _postsByCategory.keys) {
        final posts = _postsByCategory[categoryId]!;
        final idx = posts.indexWhere((p) => '${p['id']}' == postId);
        if (idx != -1) {
          foundPost = posts[idx];
          sourceCategory = categoryId;
          sourceIndex = idx;
          break;
        }
      }

      if (foundPost == null || sourceCategory == null || sourceIndex == null) {
        print('[BaseFeedProvider] 이동할 포스트를 찾을 수 없음: $postId');
        return;
      }

      // 원본에서 제거
      _postsByCategory[sourceCategory]!.removeAt(sourceIndex);

      // 대상 카테고리에 추가
      final targetCategoryStr = targetCategoryId.toString();
      if (!_postsByCategory.containsKey(targetCategoryStr)) {
        _postsByCategory[targetCategoryStr] = [];
      }

      final targetPosts = _postsByCategory[targetCategoryStr]!;
      if (targetPosition != null &&
          targetPosition >= 0 &&
          targetPosition <= targetPosts.length) {
        targetPosts.insert(targetPosition, foundPost);
      } else {
        targetPosts.add(foundPost);
      }

      notifyListeners();
      print('[BaseFeedProvider] 포스트 로컬 이동 완료: $postId -> $targetCategoryId');
    } catch (e) {
      print('[BaseFeedProvider] 포스트 로컬 이동 실패: $e');
    }
  }

  // Abstract methods - to be implemented by child classes
  Future<void> reorderPostsInCategory(int categoryId, List<String> postIds);
  void reorderPostsLocally(int categoryId, List<String> orderedPostIds);
  void reorderCategoriesLocally(List<int> orderedIntIds);
  Future<void> reorderAllSections(List<String> newOrderIds);

  /// 카테고리 내부 포스트 순서를 로컬에서 변경 (기본 구현)
  void reorderPostsLocallyImpl(int categoryId, List<String> orderedPostIds) {
    try {
      final categoryStr = categoryId.toString();
      final posts = _postsByCategory[categoryStr];
      if (posts == null || posts.isEmpty) {
        print('[BaseFeedProvider] 카테고리 $categoryId에 포스트가 없음');
        return;
      }

      // 기존 포스트들을 ID 기준으로 맵핑
      final postMap = <String, Map<String, dynamic>>{};
      for (final post in posts) {
        final id = '${post['id']}';
        postMap[id] = post;
      }

      // 새로운 순서로 재정렬
      final reorderedPosts = <Map<String, dynamic>>[];
      for (final postId in orderedPostIds) {
        final post = postMap[postId];
        if (post != null) {
          reorderedPosts.add(post);
        }
      }

      // 누락된 포스트들 추가 (혹시 모를 경우를 대비)
      for (final post in posts) {
        final id = '${post['id']}';
        if (!orderedPostIds.contains(id)) {
          reorderedPosts.add(post);
        }
      }

      _postsByCategory[categoryStr] = reorderedPosts;
      notifyListeners();
      print('[BaseFeedProvider] 카테고리 $categoryId 포스트 순서 로컬 변경 완료');
    } catch (e) {
      print('[BaseFeedProvider] 카테고리 내 포스트 순서 로컬 변경 실패: $e');
    }
  }

  /// 카테고리 ID로 카테고리 찾기
  Map<String, dynamic>? findCategoryById(int id) {
    for (final c in categoriesInternal) {
      if (c['id'] == id) return c;
    }
    return null;
  }
}
