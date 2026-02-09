import 'package:doppy/data/models/access_level.dart';
import 'package:flutter/material.dart';
import '../../data/services/blog_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/models/system_category_keys.dart';
import '../../utils/network_utils.dart';

// 카테고리 필터 타입
enum BaseFilter { all, private, friends, public }

/// 피드 Provider의 공통 기능을 담은 추상 부모 클래스
abstract class BaseFeedProvider extends ChangeNotifier {
  final BlogService blogService = BlogService();
  final AuthService authService = AuthService();

  // 현재 활성 사용자의 데이터 (UI에서 사용)
  final List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _userInfo;
  Map<String, List<Map<String, dynamic>>>? _systemCategoryMappings;

  // 네트워크 에러 상태
  NetworkError? _networkError;

  // 자식에서 사용할 내부 접근자 (mutable)
  List<Map<String, dynamic>> get postsInternal => _posts;
  Map<String, dynamic>? get userInfoInternal => _userInfo;

  // Protected getter for child classes
  @protected
  List<Map<String, dynamic>> get postsProtected => _posts;
  set userInfoInternal(Map<String, dynamic>? v) => _userInfo = v;
  Map<String, List<Map<String, dynamic>>>? get systemCategoryMappingsInternal =>
      _systemCategoryMappings;
  set systemCategoryMappingsInternal(
    Map<String, List<Map<String, dynamic>>>? v,
  ) => _systemCategoryMappings = v;

  // 공개 범위 필터 상태 관리
  BaseFilter _selectedBase = BaseFilter.all;
  bool _isReadOnly = false;

  // 서버 필터 상태 (리뉴얼 명세: phase/lifePhase는 서버에서 필터링)
  String? _serverPhase;
  String? _serverLifePhase;
  String? _serverAccessLevel;

  // 페이지네이션 (공통 설정)
  // 명세: 전용 탭은 size=100 권장
  int _pageSize = 100;
  int get pageSize => _pageSize;

  // 추상 getters - 자식 클래스에서 구현
  bool get isLoading;
  bool get isLoadingMore;
  bool get hasMore;
  String? get username;

  // Getters
  List<Map<String, dynamic>> get posts => List.unmodifiable(_posts);
  Map<String, dynamic>? get userInfo => _userInfo;
  Map<String, List<Map<String, dynamic>>>? get systemCategoryMappings =>
      _systemCategoryMappings;

  BaseFilter get selectedBase => _selectedBase;
  bool get isReadOnly => _isReadOnly;
  NetworkError? get networkError => _networkError;
  String? get serverPhase => _serverPhase;
  String? get serverLifePhase => _serverLifePhase;
  String? get serverAccessLevel => _serverAccessLevel;

  /// 데이터 클리어
  void clearData() {
    _posts.clear();
    _userInfo = null;
    _systemCategoryMappings = null;
    _networkError = null;
  }

  /// 서버에서 데이터 로드 (추상 메서드 - 자식 클래스에서 구현)
  Future<void> loadInitial({String? username, bool force = false});

  /// 더 많은 포스트 로드 (추상 메서드)
  Future<void> loadMore();

  /// 새로고침
  Future<void> refresh() async => loadInitial(force: true);

  /// 서버 필터 설정 (phase/lifePhase)
  /// - phase: preEnlistment, training, private, ...
  /// - lifePhase: LEAVE_OR_PRE_ENLISTMENT, MILITARY_LIFE, SUPPORT
  @protected
  void setServerFilter({
    String? phase,
    String? lifePhase,
    String? accessLevel,
  }) {
    _serverPhase = (phase != null && phase.isNotEmpty) ? phase : null;
    _serverLifePhase =
        (lifePhase != null && lifePhase.isNotEmpty) ? lifePhase : null;
    _serverAccessLevel =
        (accessLevel != null && accessLevel.isNotEmpty) ? accessLevel : null;
  }

  /// UI에서 사용하는 공개 API
  void configureServerFilter({
    String? phase,
    String? lifePhase,
    String? accessLevel,
  }) {
    setServerFilter(
      phase: phase,
      lifePhase: lifePhase,
      accessLevel: accessLevel,
    );
  }

  /// 네트워크 에러 설정
  void setNetworkError(NetworkError? error) {
    debugPrint('[BaseFeedProvider] setNetworkError 호출: $error');
    _networkError = error;
    // NetworkManager에 네트워크 상태 업데이트
    if (error != null) {
      // ✅ "진짜 오프라인"만 전역 오프라인으로 취급
      // - 프로필/피드에서 404, 500 등은 네트워크 연결 끊김이 아니므로 홈 오프라인 배너가 뜨면 안 됨
      final isOfflineLike =
          error.type == NetworkErrorType.noConnection ||
          error.type == NetworkErrorType.timeout;

      if (isOfflineLike) {
        debugPrint(
          '[BaseFeedProvider] NetworkManager.setNetworkError(true) 호출 (offline-like: ${error.type})',
        );
        NetworkManager.setNetworkError(true);
      } else {
        debugPrint(
          '[BaseFeedProvider] NetworkManager.setNetworkRecovered() 호출 (non-offline error: ${error.type})',
        );
        NetworkManager.setNetworkRecovered();
      }
    } else {
      debugPrint('[BaseFeedProvider] NetworkManager.setNetworkRecovered() 호출');
      NetworkManager.setNetworkRecovered();
    }
    debugPrint('[BaseFeedProvider] notifyListeners() 호출');
    notifyListeners();
  }

  /// 서버 응답 처리 (공통 로직)
  /// 새로운 통합 API 응답 처리: data.posts.posts에서 포스트 배열 가져오기
  void processServerResponse(Map<String, dynamic> feedResp) {
    final data = feedResp['data'];

    if (data == null) {
      debugPrint('[BaseFeedProvider] 서버 응답의 data가 null입니다');
      clearData();
      return;
    }

    // 사용자 정보 저장
    _userInfo = data['userInfo'];

    // 포스트 정보 저장 (data.posts.posts 배열에서 가져오기)
    _posts.clear();
    final postsData = data['posts'];
    if (postsData != null && postsData is Map<String, dynamic>) {
      final postsList = postsData['posts'] as List?;
      if (postsList != null) {
        try {
          final posts = postsList.cast<Map<String, dynamic>>();
          // 배열 순서가 globalIndex 순서 (서버에서 정렬되어 옴)
          _posts.addAll(posts);
        } catch (e) {
          debugPrint('[BaseFeedProvider] 포스트 데이터 캐스팅 실패: $e');
          for (final item in postsList) {
            if (item is Map<String, dynamic>) {
              _posts.add(item);
            }
          }
        }
      }
    }

    // 시스템 카테고리 매핑 저장 (본인 피드일 때만 있음)
    final systemCategoryMappingsData = data['systemCategoryMappings'];
    if (systemCategoryMappingsData != null &&
        systemCategoryMappingsData is Map<String, dynamic>) {
      _systemCategoryMappings = <String, List<Map<String, dynamic>>>{};
      for (final entry in systemCategoryMappingsData.entries) {
        if (entry.value is List) {
          final postIdMaps =
              (entry.value as List)
                  .map(
                    (postId) =>
                        postId is int ? {'postId': postId} : {'postId': postId},
                  )
                  .toList();
          _systemCategoryMappings![entry.key] = postIdMaps;
        }
      }
    }

    // 기본 선택 상태를 '전체'로 리셋
    _selectedBase = BaseFilter.all;
  }

  // 공개 범위 필터 메서드
  void selectBase(BaseFilter base) {
    if (_selectedBase == base) return;
    _selectedBase = base;
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
    // 그룹 기능 제거로 인해 groupsCount 제거
    return publicCount + privateCount + friendsCount;
  }

  int get privatePostCount {
    if (_systemCategoryMappings == null) return 0;
    final postIds =
        _systemCategoryMappings![SystemCategoryKeys.private] as List?;
    final count = postIds?.length ?? 0;
    debugPrint('[BaseFeedProvider] privatePostCount: $count');
    return count;
  }

  int get publicPostCount {
    if (_systemCategoryMappings == null) return 0;
    final postIds =
        _systemCategoryMappings![SystemCategoryKeys.public] as List?;
    final count = postIds?.length ?? 0;
    debugPrint('[BaseFeedProvider] publicPostCount: $count');
    return count;
  }

  // 그룹 기능 제거로 인해 groupsPostCount 제거

  int get friendsPostCount {
    if (_systemCategoryMappings == null) return 0;
    final postIds =
        _systemCategoryMappings![SystemCategoryKeys.friends] as List?;
    final count = postIds?.length ?? 0;
    debugPrint('[BaseFeedProvider] friendsPostCount: $count');
    return count;
  }

  String get selectedLabel {
    switch (_selectedBase) {
      case BaseFilter.all:
        return 'all';
      case BaseFilter.private:
        return 'private';
      case BaseFilter.friends:
        return 'friends';
      case BaseFilter.public:
        return 'public';
    }
  }

  /// 포스트 접근 레벨 업데이트 // my_profile_feed_provider.dart 에서만 사용
  void updatePostAccessLevelById(String postId, AccessLevel newLevel) {
    try {
      final idx = _posts.indexWhere((p) => '${p['id']}' == postId);
      if (idx != -1) {
        String level = SystemCategoryKeys.public;
        if (newLevel == AccessLevel.private) {
          level = SystemCategoryKeys.private;
        } else if (newLevel == AccessLevel.friends) {
          level = SystemCategoryKeys.friends;
        }
        _posts[idx]['accessLevel'] = level;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[BaseFeedProvider] accessLevel 업데이트 실패: $e');
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
  }) {
    try {
      bool hasUpdate = false;
      String? previousAccessLevel; // 🎯 변경 전 공개범위 저장

      final idx = _posts.indexWhere((p) => '${p['id']}' == postId);
      if (idx != -1) {
        // 🎯 변경 전 공개범위 저장 (systemCategoryMappings 업데이트용)
        if (accessLevel != null) {
          previousAccessLevel = _posts[idx]['accessLevel']?.toString();
        }

        // 변경된 필드만 업데이트
        if (thumbnailImageUrl != null) {
          _posts[idx]['thumbnailImageUrl'] = thumbnailImageUrl;
          hasUpdate = true;
        }
        if (title != null) {
          _posts[idx]['title'] = title;
          hasUpdate = true;
        }
        if (summary != null) {
          _posts[idx]['summary'] = summary;
          hasUpdate = true;
        }
        if (accessLevel != null) {
          _posts[idx]['accessLevel'] = accessLevel;
          hasUpdate = true;
        }

        // 🎯 systemCategoryMappings 업데이트: 공개범위가 변경된 경우
        if (accessLevel != null &&
            previousAccessLevel != null &&
            previousAccessLevel != accessLevel &&
            _systemCategoryMappings != null) {
          final postIdInt = int.tryParse(postId);
          if (postIdInt != null) {
            // 🎯 모든 공개범위 키에서 해당 포스트 제거 (중복 방지)
            final allSystemKeys = SystemCategoryKeys.allKeys;
            for (final key in allSystemKeys) {
              final list = _systemCategoryMappings![key] as List?;
              if (list != null) {
                final filteredList =
                    list
                        .where((item) {
                          if (item is Map) {
                            return item['postId']?.toString() != postId;
                          } else if (item is int) {
                            return item.toString() != postId;
                          }
                          return item?.toString() != postId;
                        })
                        .toList()
                        .cast<Map<String, dynamic>>();
                _systemCategoryMappings![key] = filteredList;
              }
            }

            // 🎯 새로운 공개범위에 추가
            final newKey = accessLevel.toUpperCase();
            if (!_systemCategoryMappings!.containsKey(newKey)) {
              _systemCategoryMappings![newKey] = <Map<String, dynamic>>[];
            }
            final newList =
                _systemCategoryMappings![newKey] as List<Map<String, dynamic>>;
            // 🎯 이미 존재하는지 확인 (모든 키에서 제거했으므로 false여야 함)
            final exists = newList.any((item) {
              return item['postId']?.toString() == postId;
            });
            if (!exists) {
              newList.add({'postId': postIdInt});
            }

            debugPrint(
              '✅ [BaseFeedProvider] systemCategoryMappings 업데이트: $postId (모든 키에서 제거 후 $newKey에 추가)',
            );
          }
        }

        if (hasUpdate) {
          notifyListeners();
          debugPrint('✅ [BaseFeedProvider] 포스트 $postId 메타데이터 선택적 업데이트 완료');
        }
      } else {
        debugPrint('⚠️ [BaseFeedProvider] 포스트 $postId를 찾을 수 없어 메타데이터 업데이트 불가');
      }
    } catch (e) {
      debugPrint('[BaseFeedProvider] 포스트 메타데이터 업데이트 실패: $e');
    }
  }

  // Abstract methods - to be implemented by child classes
  Future<void> reorderPosts(List<String> orderedPostIds);
  void reorderPostsLocally(List<String> orderedPostIds);

  /// 포스트 순서를 로컬에서 변경 (기본 구현)
  void reorderPostsLocallyImpl(List<String> orderedPostIds) {
    try {
      if (_posts.isEmpty) {
        debugPrint('[BaseFeedProvider] 포스트가 없음');
        return;
      }

      // 기존 포스트들을 ID 기준으로 맵핑
      final postMap = <String, Map<String, dynamic>>{};
      for (final post in _posts) {
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
      for (final post in _posts) {
        final id = '${post['id']}';
        if (!orderedPostIds.contains(id)) {
          reorderedPosts.add(post);
        }
      }

      _posts.clear();
      _posts.addAll(reorderedPosts);

      // globalIndex 업데이트
      for (int i = 0; i < _posts.length; i++) {
        _posts[i]['globalIndex'] = i;
      }

      notifyListeners();
      debugPrint('[BaseFeedProvider] 포스트 순서 로컬 변경 완료');
    } catch (e) {
      debugPrint('[BaseFeedProvider] 포스트 순서 로컬 변경 실패: $e');
    }
  }
}
