import 'package:flutter/material.dart';
import '../data/services/blog_service.dart';
import '../data/services/auth_service.dart';

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

  DateTime? _lastLoadedAt;
  Duration ttl = const Duration(hours: 12);

  String? _username; // 조회 대상

  final Map<String, List<Map<String, dynamic>>> _userPosts = {};
  final Map<String, DateTime> _userLastLoadedAt = {};
  final Map<String, int> _userPage = {};
  final Map<String, bool> _userHasMore = {};
  // 대상 사용자별 인플라이트 로딩 가드
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
      _lastLoadedAt = DateTime.now();
      // 캐시 비활성화: 저장하지 않음
    } catch (e) {
      // 실패(예: 404) 시 빈 피드로 표시는 유지. 캐시는 사용하지 않음
      _posts.clear();
      _hasMore = false;
      _lastLoadedAt = DateTime.now();
      _userPosts.remove(_username!);
      _userLastLoadedAt.remove(_username!);
      _userPage.remove(_username!);
      _userHasMore[_username!] = false;
    } finally {
      _loading = false;
      if (_username != null) _inFlightUsers.remove(_username!);
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadInitial(force: true);
  }

  /// 사용자 요청에 의한 풀 리프레시(끌어내려 새로고침):
  /// 즉시 화면에서 기존 목록을 비우고 강제 재로딩
  Future<void> hardRefresh({String? username}) async {
    _posts.clear();
    _page = 0;
    _hasMore = true;
    notifyListeners();
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

  void invalidate() {
    _lastLoadedAt = null;
    if (_username != null) {
      _userLastLoadedAt.remove(_username!);
    }
  }

  // 내 글이 변경되었다는 이벤트를 외부에서 호출할 때 사용
  void onMyPostsChanged() {
    invalidate();
    // 화면에 즉시 반영되도록 캐시 클리어는 하지 않고, 다음 진입/다시 보기에서 재로딩
    notifyListeners();
  }
}
