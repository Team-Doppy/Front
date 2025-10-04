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
