import 'package:flutter/material.dart';
import '../data/services/blog_service.dart';
import '../data/services/auth_service.dart';
import '../data/models/post_data.dart';

class ProfileFeedProvider extends ChangeNotifier {
  final BlogService _blogService = BlogService();
  final AuthService _authService = AuthService();

  final List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> get posts => List.unmodifiable(_posts);

  bool _loading = false;
  bool get isLoading => _loading;

  bool _loadingMore = false;
  bool get isLoadingMore => _loadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _page = 0;

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
      _posts.clear();
      _page = 0;
      _hasMore = true;
      notifyListeners();
    }

    // 캐시 사용 중지: 항상 새로 로드
    final String? myUsername = await _authService.getUsername();
    final bool isOwn = myUsername != null && myUsername == _username;

    _loading = true;
    _page = 0;
    _hasMore = true;
    notifyListeners();
    try {
      // isOwn은 위에서 계산됨
      final fetched =
          isOwn
              ? await _blogService.getMyPosts(page: _page, size: 10)
              : await _blogService.getUserPosts(
                username: _username!,
                page: _page,
                size: 10,
              );
      _posts
        ..clear()
        ..addAll(fetched);
      _hasMore = fetched.length == 10;
      if (_hasMore) _page += 1;
      // 로드 타임스탬프는 사용하지 않음
      // 캐시 비활성화: 저장하지 않음
    } catch (e) {
      // 실패(예: 404) 시 빈 피드로 표시는 유지. 캐시는 사용하지 않음
      _posts.clear();
      _hasMore = false;
      // 캐시 사용 안함
    } finally {
      _loading = false;
      if (_username != null) _inFlightUsers.remove(_username!);
      notifyListeners();
    }
  }

  Future<void> refresh() async => loadInitial(force: true);

  /// 즉시 화면에서 기존 목록을 비우고 강제 재로딩
  Future<void> hardRefresh({String? username}) async {
    // 기존 사용자 정보도 초기화
    _username = null;

    // 피드 즉시 초기화
    _posts.clear();
    _page = 0;
    _hasMore = true;

    // UI 즉시 업데이트 (이전 피드가 보이지 않도록)
    notifyListeners();

    // 새 데이터 로드
    await loadInitial(username: username, force: true);
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final String? myUsername = await _authService.getUsername();
      final bool isOwn = myUsername != null && myUsername == _username;
      final fetched =
          isOwn
              ? await _blogService.getMyPosts(page: _page, size: 10)
              : await _blogService.getUserPosts(
                username: _username!,
                page: _page,
                size: 10,
              );
      _posts.addAll(fetched);
      _hasMore = fetched.length == 10;
      if (_hasMore) _page += 1;
      // 캐시 비활성화
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
      final idx = _posts.indexWhere((p) => '${p['id']}' == postId);
      if (idx == -1) return;
      // 서버 스키마는 대문자 문자열 사용: PUBLIC / PRIVATE / GROUPS
      String level = 'PUBLIC';
      if (newLevel == AccessLevel.private) level = 'PRIVATE';
      if (newLevel == AccessLevel.groups) level = 'GROUPS';
      _posts[idx]['accessLevel'] = level;
      notifyListeners();
      print('[ProfileFeedProvider] accessLevel 업데이트: id=$postId -> $level');
    } catch (e) {
      print('[ProfileFeedProvider] accessLevel 업데이트 실패: $e');
    }
  }

  /// 동일 공개 범주 내에서 가로 순서 변경 (로컬 UI 반영용)
  void moveWithinAccessLevel(String postId, AccessLevel level, int newIndex) {
    try {
      // 해당 레벨의 모든 전역 인덱스 수집
      final levelKey =
          level == AccessLevel.private
              ? 'PRIVATE'
              : level == AccessLevel.groups
              ? 'GROUPS'
              : 'PUBLIC';

      final levelGlobalIndices = <int>[];
      for (int i = 0; i < _posts.length; i++) {
        if ('${_posts[i]['accessLevel']}' == levelKey) {
          levelGlobalIndices.add(i);
        }
      }
      if (levelGlobalIndices.isEmpty) return;

      // 이동할 아이템의 전역 인덱스와 레벨 내 인덱스 계산
      final currentGlobalIndex = _posts.indexWhere(
        (p) => '${p['id']}' == postId,
      );
      if (currentGlobalIndex == -1) return;
      final currentLevelIndex = levelGlobalIndices.indexOf(currentGlobalIndex);
      if (currentLevelIndex == -1) return;

      // 타겟 레벨 인덱스를 경계 내로 보정하고 전역 인덱스로 변환
      final clampedLevelIndex = newIndex.clamp(
        0,
        levelGlobalIndices.length - 1,
      );
      final targetGlobalIndex = levelGlobalIndices[clampedLevelIndex];

      if (currentGlobalIndex == targetGlobalIndex) return;

      // 아이템 추출 후 목표 위치에 삽입
      final item = _posts.removeAt(currentGlobalIndex);

      // 제거로 인해 인덱스 변화 보정
      final adjustedTarget =
          currentGlobalIndex < targetGlobalIndex
              ? targetGlobalIndex - 1
              : targetGlobalIndex;

      _posts.insert(adjustedTarget, item);
      notifyListeners();
      print(
        '[ProfileFeedProvider] 순서 변경: level=$levelKey id=$postId -> idx=$clampedLevelIndex',
      );
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
      // 1) 기존 위치에서 항목 추출
      final currentGlobalIndex = _posts.indexWhere(
        (p) => '${p['id']}' == postId,
      );
      if (currentGlobalIndex == -1) return;
      final item = _posts.removeAt(currentGlobalIndex);

      // 2) accessLevel 업데이트 (서버 스키마: 대문자)
      String levelKey = 'PUBLIC';
      if (newLevel == AccessLevel.private) levelKey = 'PRIVATE';
      if (newLevel == AccessLevel.groups) levelKey = 'GROUPS';
      item['accessLevel'] = levelKey;

      // 3) 새 레벨의 전역 인덱스 리스트 계산
      final levelGlobalIndices = <int>[];
      for (int i = 0; i < _posts.length; i++) {
        if ('${_posts[i]['accessLevel']}' == levelKey) {
          levelGlobalIndices.add(i);
        }
      }

      // 4) 목표 전역 인덱스 계산 (리스트 끝 삽입 허용)
      final clampedLevelIndex = targetIndex.clamp(0, levelGlobalIndices.length);
      // 전역 인덱스로 변환: 해당 레벨 블록의 시작 지점 산출
      int targetGlobalIndex;
      if (levelGlobalIndices.isEmpty) {
        // 해당 레벨 항목이 하나도 없으면, 같은 레벨 중 첫 위치를 찾아 삽입
        // 기본 정책: 리스트 맨 끝에 삽입
        targetGlobalIndex = _posts.length;
      } else if (clampedLevelIndex == levelGlobalIndices.length) {
        // 해당 레벨 블록의 마지막 이후에 삽입
        targetGlobalIndex = levelGlobalIndices.last + 1;
      } else {
        targetGlobalIndex = levelGlobalIndices[clampedLevelIndex];
      }

      // 5) 항목 삽입 및 알림
      _posts.insert(targetGlobalIndex, item);
      notifyListeners();
      print(
        '[ProfileFeedProvider] 이동+삽입: id=$postId -> $levelKey index=$clampedLevelIndex',
      );
    } catch (e) {
      print('[ProfileFeedProvider] 이동+삽입 실패: $e');
    }
  }

  /// 로그아웃 시 모든 피드 데이터 초기화
  void logout() {
    _posts.clear();
    _loading = false;
    _loadingMore = false;
    _hasMore = true;
    _page = 0;
    _username = null;
    _inFlightUsers.clear();
    notifyListeners();
    print('[ProfileFeedProvider] 로그아웃 - 피드 데이터 초기화 완료');
  }

  /// 화면을 나갈 때 UI 상의 목록만 즉시 정리 (캐시/메타 정보 유지)
  void clearInMemory() {
    _posts.clear();
    _loading = false;
    _loadingMore = false;
    notifyListeners();
    // _username, _hasMore, _page 등은 유지하여 다음 진입 시 빠르게 재요청 가능
  }
}
