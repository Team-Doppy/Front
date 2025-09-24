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

  Future<void> loadInitial({String? username, bool force = false}) async {
    if (_loading) return;
    // 대상 사용자 결정: 파라미터 > 저장된 > 토큰에서 username
    if (username != null) {
      _username = username;
    }
    _username ??= await _authService.getUsername();

    if (_username == null) return;

    // TTL 체크: 강제 갱신이 아니고, 최근 로드가 TTL 내라면 스킵
    if (!force &&
        _lastLoadedAt != null &&
        DateTime.now().difference(_lastLoadedAt!) < ttl &&
        _posts.isNotEmpty) {
      return;
    }

    _loading = true;
    _page = 0;
    _hasMore = true;
    notifyListeners();
    try {
      final fetched = await _blogService.getMyPosts(page: _page, size: 10);
      _posts
        ..clear()
        ..addAll(fetched);
      _hasMore = fetched.length == 10;
      if (_hasMore) _page += 1;
      _lastLoadedAt = DateTime.now();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadInitial(force: true);
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final fetched = await _blogService.getMyPosts(page: _page, size: 10);
      _posts.addAll(fetched);
      _hasMore = fetched.length == 10;
      if (_hasMore) _page += 1;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  void invalidate() {
    _lastLoadedAt = null;
  }

  // 내 글이 변경되었다는 이벤트를 외부에서 호출할 때 사용
  void onMyPostsChanged() {
    invalidate();
    // 화면에 즉시 반영되도록 캐시 클리어는 하지 않고, 다음 진입/다시 보기에서 재로딩
    notifyListeners();
  }
}
