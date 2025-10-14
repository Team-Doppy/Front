import 'package:flutter/material.dart';
import '../data/services/blog_service.dart';
import '../data/services/auth_service.dart';
import '../data/models/post_data.dart';

// 카테고리 필터 타입
enum BaseFilter { all, private, groups, public }

class ProfileFeedProvider extends ChangeNotifier {
  final BlogService _blogService = BlogService();
  final AuthService _authService = AuthService();

  // 새로운 API 구조에 맞춘 데이터
  final List<Map<String, dynamic>> _categories = [];
  final Map<String, List<Map<String, dynamic>>> _postsByCategory = {};
  Map<String, dynamic>? _userInfo;
  Map<String, List<Map<String, dynamic>>>? _systemCategoryMappings;

  // 카테고리 선택 상태 관리
  BaseFilter _selectedBase = BaseFilter.all;
  String? _selectedCategoryId;
  bool _isReadOnly = false;

  List<Map<String, dynamic>> get categories => List.unmodifiable(_categories);
  Map<String, List<Map<String, dynamic>>> get postsByCategory =>
      Map.unmodifiable(_postsByCategory);
  Map<String, dynamic>? get userInfo => _userInfo;
  Map<String, List<Map<String, dynamic>>>? get systemCategoryMappings =>
      _systemCategoryMappings;

  // 카테고리 선택 상태 getters
  BaseFilter get selectedBase => _selectedBase;
  String? get selectedCategoryId => _selectedCategoryId;
  bool get isReadOnly => _isReadOnly;

  // 기존 호환성을 위한 posts getter
  List<Map<String, dynamic>> get posts {
    final allPosts = <Map<String, dynamic>>[];
    for (final categoryPosts in _postsByCategory.values) {
      allPosts.addAll(categoryPosts);
    }
    return List.unmodifiable(allPosts);
  }

  bool _loading = false;
  bool get isLoading => _loading;

  bool _loadingMore = false;
  bool get isLoadingMore => _loadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  // 페이지네이션 (posts 전용)
  int _currentPage = 0;
  int _totalPages = 0;
  int _pageSize = 20;

  // int _page = 0; // 새로운 API 구조에서는 사용하지 않음

  String? _username; // 조회 대상

  final Set<String> _inFlightUsers = <String>{};

  Future<void> loadInitial({String? username, bool force = false}) async {
    // 동일 사용자 대상의 중복 로딩 방지
    if (_loading && (_username == (username ?? _username))) return;
    // 대상 사용자 결정: 파라미터 > (항상) 토큰에서 username (기존 값 사용 안함)
    final String? resolved = username ?? await _authService.getUsername();
    final String? previous = _username;
    if (resolved != null && _inFlightUsers.contains(resolved)) return;
    if (resolved != null) _inFlightUsers.add(resolved);
    _username = resolved;

    if (_username == null) return;

    // 사용자 전환 시, 기존 리스트를 즉시 비워 잘못된 피드 표시 방지
    if (previous != null && previous != _username) {
      _clearData();
      notifyListeners();
    }

    _loading = true;
    // _page = 0; // 새로운 API 구조에서는 사용하지 않음
    _hasMore = true;
    notifyListeners();

    try {
      // 병렬 호출: 스키마 + 첫 페이지 포스트
      final results = await Future.wait([
        _blogService.getProfileSchema(_username!),
        _blogService.getProfilePosts(_username!, page: 0, size: _pageSize),
      ]);

      final schemaResp = results[0];
      final postsResp = results[1];

      if (schemaResp['success'] == true) {
        final data = schemaResp['data'];

        if (data == null) {
          print('[ProfileFeedProvider] 서버 응답의 data가 null입니다');
          _clearData();
          return;
        }

        print('[ProfileFeedProvider] 서버 응답 데이터 타입 확인: ${data.runtimeType}');
        print('[ProfileFeedProvider] data 키들: ${data.keys.toList()}');

        // 사용자 정보 저장
        _userInfo = data['userInfo'];

        // 카테고리 정보 저장
        _categories.clear();
        final categoriesData = data['categories'];
        if (categoriesData != null && categoriesData is List) {
          try {
            _categories.addAll(categoriesData.cast<Map<String, dynamic>>());
          } catch (e) {
            print('[ProfileFeedProvider] 카테고리 데이터 캐스팅 실패: $e');
            // 안전한 방식으로 변환
            for (final item in categoriesData) {
              if (item is Map<String, dynamic>) {
                _categories.add(item);
              }
            }
          }
        }

        // 카테고리별 포스트 저장
        _postsByCategory.clear();
        final postsByCategoryData = data['postsByCategory'];
        if (postsByCategoryData != null &&
            postsByCategoryData is Map<String, dynamic>) {
          for (final entry in postsByCategoryData.entries) {
            if (entry.value is List) {
              try {
                _postsByCategory[entry.key] =
                    (entry.value as List).cast<Map<String, dynamic>>();
              } catch (e) {
                print(
                  '[ProfileFeedProvider] 포스트 데이터 캐스팅 실패 (카테고리 ${entry.key}): $e',
                );
                // 안전한 방식으로 변환
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

        // 시스템 카테고리 매핑 저장 (생성은 포스트 병합 후 실행)
        final systemCategoryMappingsData = data['systemCategoryMappings'];
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
        } else {
          print(
            '[ProfileFeedProvider] systemCategoryMappings가 서버 응답에 없음 - 시스템 카테고리 생성 건너뜀',
          );
        }

        // 포스트 페이지네이션 메타 저장
        final postsData = postsResp['data'] as Map<String, dynamic>?;
        final postsList =
            (postsData?['posts'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        print('[ProfileFeedProvider] posts 페이지 개수: ${postsList.length}');
        _currentPage = (postsData?['currentPage'] as int?) ?? 0;
        _totalPages = (postsData?['totalPages'] as int?) ?? 0;
        _hasMore =
            (postsData?['hasNext'] as bool?) ??
            (_currentPage + 1 < _totalPages);

        // posts를 빠른 조회용 맵으로 구성 (id -> post)
        final Map<int, Map<String, dynamic>> idToPost = {
          for (final p in postsList)
            if (p['id'] != null) (p['id'] as int): p,
        };

        // postsByCategory에 있는 각 항목이 {'id': 35, 'order': 1} 형태이므로,
        // postsList의 실제 포스트와 병합하여 title/thumbnail 등 채움
        final keys = List<String>.from(_postsByCategory.keys);
        print('[ProfileFeedProvider] 병합 전 카테고리 키: $keys');
        for (final key in keys) {
          final original =
              _postsByCategory[key] ?? const <Map<String, dynamic>>[];
          final merged = <Map<String, dynamic>>[];
          for (final item in original) {
            final pid = item['id'];
            if (pid is int && idToPost.containsKey(pid)) {
              final full = Map<String, dynamic>.from(idToPost[pid]!);
              // order/position 정보가 있으면 유지
              if (item.containsKey('order')) full['order'] = item['order'];
              merged.add(full);
            } else {
              // posts 페이지에 아직 없는 포스트는 최소 정보만 유지
              merged.add(item);
            }
          }
          _postsByCategory[key] = merged;
          final sample = merged.isNotEmpty ? merged.first : null;
          print(
            '[ProfileFeedProvider] 병합 결과 카테고리 ' +
                key +
                ': ' +
                merged.length.toString() +
                '개, 샘플=' +
                (sample != null
                    ? '{id:' +
                        (sample['id']?.toString() ?? 'null') +
                        ', title:' +
                        (sample['title']?.toString() ?? 'null') +
                        ', thumb:' +
                        (sample['thumbnailUrl']?.toString() ??
                            sample['thumbnailImageUrl']?.toString() ??
                            'null') +
                        '}'
                    : '없음'),
          );
        }

        // 기본 선택 상태를 '전체'로 리셋 (UI 초기에 hasSelection=false 유지)
        _selectedCategoryId = null;
        _selectedBase = BaseFilter.all;

        // 병합 직후 1차 갱신 (미분류만 먼저라도 표시되도록)
        notifyListeners();

        // 시스템 카테고리 생성은 병합 이후 호출 (full posts 기반)
        if (_userInfo?['isOwnProfile'] == true) {
          _createSystemCategories();
          // 시스템 카테고리 반영 후 2차 갱신
          notifyListeners();
        }
        print(
          '[ProfileFeedProvider] 데이터 로드 성공: ${_categories.length}개 카테고리, ${_postsByCategory.length}개 카테고리별 포스트',
        );
        _debugDumpState('after-merge');
      } else {
        print('[ProfileFeedProvider] 서버 응답 실패: ${postsResp['message']}');
        _clearData();
      }
    } catch (e) {
      print('[ProfileFeedProvider] 프로필 피드 로드 실패: $e');
      _clearData();
    } finally {
      _loading = false;
      if (_username != null) _inFlightUsers.remove(_username!);
      notifyListeners();
    }
  }

  void _clearData() {
    _categories.clear();
    _postsByCategory.clear();
    _userInfo = null;
    _systemCategoryMappings = null;
    // _page = 0; // 새로운 API 구조에서는 사용하지 않음
    _hasMore = false;
  }

  /// 시스템 카테고리 생성 및 포스트 매핑
  void _createSystemCategories() {
    if (_systemCategoryMappings == null) return;

    // 시스템 카테고리 정의
    final systemCategories = [
      {
        'id': -1,
        'name': '전체공개',
        'displayOrder': -3,
        'postCount': 0,
        'isPrivate': false,
        'isSystem': true,
        'description': '모든 사용자가 볼 수 있는 포스트',
      },
      {
        'id': -2,
        'name': '나만보기',
        'displayOrder': -2,
        'postCount': 0,
        'isPrivate': true,
        'isSystem': true,
        'description': '본인만 볼 수 있는 포스트',
      },
      {
        'id': -3,
        'name': '그룹공유',
        'displayOrder': -1,
        'postCount': 0,
        'isPrivate': false,
        'isSystem': true,
        'description': '그룹 멤버만 볼 수 있는 포스트',
      },
    ];

    // 시스템 카테고리는 전체 탭의 '카테고리 목록'에 포함하지 않는다.
    // 대신 postsByCategory에만 추가하여, 시스템 필터 선택 시에만 사용한다.
    for (final systemCategory in systemCategories) {
      final categoryName = systemCategory['name'] as String;
      final mapping = _systemCategoryMappings![categoryName];

      if (mapping != null) {
        // 이제 mapping은 [{'postId': 35}, {'postId': 34}, ...] 형태
        final postIds = <int>[];
        for (final item in mapping) {
          postIds.add(item['postId'] as int);
        }
        // postId를 내림차순으로 정렬
        postIds.sort((a, b) => b.compareTo(a));

        // 실제 포스트 데이터에서 해당 postId들을 찾아서 매핑
        final systemPosts = <Map<String, dynamic>>[];
        for (final postId in postIds) {
          // 모든 카테고리에서 해당 postId를 가진 포스트 찾기
          for (final categoryPosts in _postsByCategory.values) {
            final postIndex = categoryPosts.indexWhere(
              (p) => p['id'] == postId,
            );
            if (postIndex != -1) {
              systemPosts.add(categoryPosts[postIndex]);
              break; // 찾았으면 다른 카테고리에서는 찾지 않음
            }
          }
        }

        // 시스템 카테고리 포스트 수 업데이트
        systemCategory['postCount'] = systemPosts.length;

        // 포스트만 저장(카테고리 리스트에는 추가하지 않음)
        _postsByCategory[systemCategory['id'].toString()] = systemPosts;

        print(
          '[ProfileFeedProvider] 시스템 카테고리 생성: $categoryName (${systemPosts.length}개 포스트)',
        );
      }
    }

    // 사용자 정의 카테고리만 정렬(시스템 카테고리는 목록에 없음)
    _categories.sort((a, b) {
      final ai = (a['displayOrder'] as int? ?? 0);
      final bi = (b['displayOrder'] as int? ?? 0);
      return ai.compareTo(bi);
    });

    print('[ProfileFeedProvider] 시스템 카테고리 생성 완료');
    _debugDumpState('after-system-categories');
  }

  Future<void> refresh() async => loadInitial(force: true);

  /// 즉시 화면에서 기존 목록을 비우고 강제 재로딩
  Future<void> hardRefresh({String? username}) async {
    // 기존 사용자 정보도 초기화
    _username = null;

    // 피드 즉시 초기화
    _clearData();

    // UI 즉시 업데이트 (이전 피드가 보이지 않도록)
    notifyListeners();

    // 새 데이터 로드
    await loadInitial(username: username, force: true);
  }

  Future<void> loadMore() async {
    // 새로운 API 구조에서는 loadMore가 필요 없을 수 있음
    // 필요시 카테고리별 페이지네이션으로 구현
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();

    try {
      // TODO: 카테고리별 추가 로딩 구현 필요시
      _hasMore = false;
    } catch (e) {
      _hasMore = false;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// 특정 포스트의 공개 범위를 즉시 갱신하고 UI를 재그룹핑하도록 알림
  void updatePostAccessLevelById(String postId, AccessLevel newLevel) {
    try {
      // 새로운 구조에서는 카테고리별로 포스트를 관리
      for (final categoryId in _postsByCategory.keys) {
        final posts = _postsByCategory[categoryId]!;
        final idx = posts.indexWhere((p) => '${p['id']}' == postId);
        if (idx != -1) {
          // 서버 스키마는 대문자 문자열 사용: PUBLIC / PRIVATE / GROUPS
          String level = 'PUBLIC';
          if (newLevel == AccessLevel.private) level = 'PRIVATE';
          if (newLevel == AccessLevel.groups) level = 'GROUPS';
          posts[idx]['accessLevel'] = level;
          notifyListeners();
          print('[ProfileFeedProvider] accessLevel 업데이트: id=$postId -> $level');
          return;
        }
      }
    } catch (e) {
      print('[ProfileFeedProvider] accessLevel 업데이트 실패: $e');
    }
  }

  /// 동일 공개 범주 내에서 가로 순서 변경 (로컬 UI 반영용)
  void moveWithinAccessLevel(String postId, AccessLevel level, int newIndex) {
    try {
      // 새로운 구조에서는 카테고리별로 관리하므로 이 메서드는 사용하지 않음
      // TODO: 카테고리별 포스트 순서 변경으로 대체 필요
      print('[ProfileFeedProvider] moveWithinAccessLevel은 새로운 구조에서 사용하지 않음');
    } catch (e) {
      print('[ProfileFeedProvider] 순서 변경 실패: $e');
    }
  }

  /// 다른 공개 범주로 이동 + 해당 범주 내 특정 인덱스에 삽입
  void moveToAccessLevelAtIndex(
    String postId,
    AccessLevel newLevel,
    int targetIndex,
  ) {
    try {
      // 새로운 구조에서는 카테고리별로 관리하므로 이 메서드는 사용하지 않음
      // TODO: 카테고리별 포스트 이동으로 대체 필요
      print('[ProfileFeedProvider] moveToAccessLevelAtIndex은 새로운 구조에서 사용하지 않음');
    } catch (e) {
      print('[ProfileFeedProvider] 이동+삽입 실패: $e');
    }
  }

  /// 로그아웃 시 모든 피드 데이터 초기화
  void logout() {
    _clearData();
    _loading = false;
    _loadingMore = false;
    _hasMore = true;
    // _page = 0; // 새로운 API 구조에서는 사용하지 않음
    _username = null;
    _inFlightUsers.clear();
    notifyListeners();
    print('[ProfileFeedProvider] 로그아웃 - 피드 데이터 초기화 완료');
  }

  /// 화면을 나갈 때 UI 상의 목록만 즉시 정리 (캐시/메타 정보 유지)
  void clearInMemory() {
    _clearData();
    _loading = false;
    _loadingMore = false;
    notifyListeners();
    // _username, _hasMore, _page 등은 유지하여 다음 진입 시 빠르게 재요청 가능
  }

  /// 포스트를 로컬에서 카테고리 간 이동 (서버 호출 후 로컬 업데이트용)
  void movePostLocally(
    String postId,
    int targetCategoryId,
    int? targetPosition,
  ) {
    try {
      // 1. 기존 카테고리에서 포스트 찾기 및 제거
      Map<String, dynamic>? postToMove;
      String? sourceCategoryId;

      for (final categoryId in _postsByCategory.keys) {
        final posts = _postsByCategory[categoryId]!;
        final idx = posts.indexWhere((p) => '${p['id']}' == postId);
        if (idx != -1) {
          postToMove = posts.removeAt(idx);
          sourceCategoryId = categoryId;
          break;
        }
      }

      if (postToMove == null) {
        print('[ProfileFeedProvider] 이동할 포스트를 찾을 수 없음: $postId');
        return;
      }

      // 2. 타겟 카테고리에 포스트 추가
      final targetCategoryKey = targetCategoryId.toString();
      if (!_postsByCategory.containsKey(targetCategoryKey)) {
        _postsByCategory[targetCategoryKey] = [];
      }

      final targetPosts = _postsByCategory[targetCategoryKey]!;

      if (targetPosition != null &&
          targetPosition >= 0 &&
          targetPosition <= targetPosts.length) {
        // 특정 위치에 삽입
        targetPosts.insert(targetPosition, postToMove);
      } else {
        // 맨 뒤에 추가
        targetPosts.add(postToMove);
      }

      // 3. 카테고리별 포스트 수 업데이트
      _updateCategoryPostCounts();

      // 4. 자동 필터 전환 금지: 선택 상태 변경하지 않음

      notifyListeners();
      print(
        '[ProfileFeedProvider] 포스트 로컬 이동 완료: $postId ($sourceCategoryId -> $targetCategoryId)',
      );
    } catch (e) {
      print('[ProfileFeedProvider] 포스트 로컬 이동 실패: $e');
    }
  }

  /// 카테고리별 포스트 수 업데이트
  void _updateCategoryPostCounts() {
    for (final category in _categories) {
      final categoryId = category['id'].toString();
      final postCount = _postsByCategory[categoryId]?.length ?? 0;
      category['post_count'] = postCount;
    }
  }

  /// 카테고리 순서를 로컬에서 재정렬하고 알림
  void reorderCategoriesLocally(List<int> orderedIds) {
    try {
      final Set<int> orderSet = orderedIds.toSet();
      final List<Map<String, dynamic>> ordered = [];

      // orderedIds 순서대로 추가
      for (final id in orderedIds) {
        final idx = _categories.indexWhere((c) => (c['id'] as int?) == id);
        if (idx != -1) ordered.add(_categories[idx]);
      }

      // 나머지(orderedIds에 없는 항목) 유지 순서로 뒤에 추가
      for (final cat in _categories) {
        final cid = cat['id'] as int?;
        if (cid == null || !orderSet.contains(cid)) {
          ordered.add(cat);
        }
      }

      _categories
        ..clear()
        ..addAll(ordered);
      notifyListeners();
      print('[ProfileFeedProvider] 카테고리 로컬 재정렬 완료: $orderedIds');
    } catch (e) {
      print('[ProfileFeedProvider] 카테고리 로컬 재정렬 실패: $e');
    }
  }

  /// 섹션(카테고리) 순서 변경 - 낙관적 로컬 반영 후 서버 저장, 실패 시 롤백
  Future<void> reorderAllSections(List<String> newOrderIds) async {
    // 문자열 ID -> int 변환 (0 포함 그대로 유지)
    final orderedIntIds = <int>[];
    for (final idStr in newOrderIds) {
      if (idStr == 'system_doppy_uncategorized') {
        orderedIntIds.add(0);
        continue;
      }
      final id = int.tryParse(idStr);
      if (id != null) orderedIntIds.add(id);
    }

    if (orderedIntIds.isEmpty) {
      print('[ProfileFeedProvider] reorderAllSections: 유효한 ID 없음');
      return;
    }

    // 1) 현재 순서를 백업
    final prevOrder = _categories.map<int>((c) => (c['id'] as int)).toList();

    // 2) 낙관적 로컬 반영 (요청된 순서 그대로, 0 포함)
    reorderCategoriesLocally(orderedIntIds);
    print('[ProfileFeedProvider] 서버 전송 orderedIds=$orderedIntIds');

    // 3) 서버 저장 시도 (0 포함 그대로)
    try {
      await _blogService.reorderCategories(orderedIntIds);
      print('[ProfileFeedProvider] 서버 저장 완료');
    } catch (e) {
      // 4) 실패 시 롤백
      print('[ProfileFeedProvider] reorderAllSections 서버 실패, 롤백: $e');
      reorderCategoriesLocally(prevOrder);
      rethrow;
    }
  }

  /// 내부 상태 요약 덤프 (디버깅 전용)
  void _debugDumpState(String tag) {
    try {
      final totalPosts = posts.length;
      print(
        '[ProfileFeedProvider][$tag] user=${_userInfo?['username']?.toString() ?? 'null'}, categories=${_categories.length}, postsTotal=$totalPosts',
      );
      for (final cat in _categories) {
        final id = cat['id'].toString();
        final name = (cat['name'] ?? '').toString();
        final c = _postsByCategory[id]?.length ?? 0;
        final first =
            (_postsByCategory[id]?.isNotEmpty ?? false)
                ? _postsByCategory[id]!.first
                : null;
        print(
          '  - [$id] $name: $c개, 샘플=${first != null ? '{id:${first['id']?.toString() ?? 'null'}, title:${first['title']?.toString() ?? 'null'}}' : '없음'}',
        );
      }
    } catch (e) {
      print('[ProfileFeedProvider][' + tag + '] dump 실패: $e');
    }
  }

  // 카테고리 선택 메서드들
  void selectBase(BaseFilter base) {
    if (_selectedBase == base && _selectedCategoryId == null) return;
    _selectedCategoryId = null;
    _selectedBase = base;
    print('[ProfileFeedProvider] selectBase -> $_selectedBase');
    notifyListeners();
  }

  void selectCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    print('[ProfileFeedProvider] selectCategory -> $categoryId');
    notifyListeners();
  }

  void setReadOnly(bool readOnly) {
    if (_isReadOnly == readOnly) return;
    _isReadOnly = readOnly;
    notifyListeners();
  }

  String get selectedLabel {
    if (_selectedCategoryId != null) {
      final cat = _categories.firstWhere(
        (c) => c['id'].toString() == _selectedCategoryId,
        orElse: () => {'id': '', 'name': ''},
      );
      if (cat['id'].toString().isNotEmpty) return cat['name'];
    }
    switch (_selectedBase) {
      case BaseFilter.all:
        return '전체';
      case BaseFilter.private:
        return '나만보기';
      case BaseFilter.groups:
        return '그룹공유';
      case BaseFilter.public:
        return '전체공개';
    }
  }
}
