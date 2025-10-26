import 'base_feed_provider.dart';
import '../../utils/network_utils.dart';

/// 다른 사람 피드 전용 Provider (캐시 없음, 항상 서버에서 로드)
class OtherProfileFeedProvider extends BaseFeedProvider {
  // 독립적인 상태 관리
  String? _username;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  int _totalPages = 0;

  // Getters 구현
  @override
  String? get username => _username;
  @override
  bool get isLoading => _loading;
  @override
  bool get isLoadingMore => _loadingMore;
  @override
  bool get hasMore => _hasMore;

  @override
  Future<void> loadInitial({String? username, bool force = false}) async {
    // 다른 사람 피드는 반드시 username이 필요
    if (username == null) {
      print('[OtherProfileFeedProvider] username이 null입니다');
      return;
    }

    // 동일 사용자 대상의 중복 로딩 방지
    if (_loading && (_username == username)) return;

    final String? previous = _username;
    _username = username;

    // 사용자 전환 시, 기존 UI 데이터 즉시 클리어
    if (previous != null && previous != _username) {
      clearData();
      notifyListeners();
    }

    _loading = true;
    _hasMore = true;
    notifyListeners();

    try {
      // 병렬 호출: 스키마 + 첫 페이지 포스트
      final results = await Future.wait([
        blogService.getProfileSchema(_username!),
        blogService.getProfilePosts(_username!, page: 0, size: pageSize),
      ]);

      final schemaResp = results[0];
      final postsResp = results[1];

      if (schemaResp['success'] == true && postsResp['success'] == true) {
        // 부모 클래스의 공통 처리 로직 사용
        processServerResponse(schemaResp, postsResp);
        setNetworkError(null); // 성공 시 에러 클리어

        // 페이지네이션 처리
        final postsData = postsResp['data'];
        _currentPage = 0;
        _totalPages = postsData['totalPages'] ?? 0;
        _hasMore = _currentPage < _totalPages;

        print('[OtherProfileFeedProvider] 서버 로드 완료: $_username');
      } else {
        print('[OtherProfileFeedProvider] 서버 응답 실패: ${postsResp['message']}');
        clearData();
      }
    } catch (e) {
      print('[OtherProfileFeedProvider] 서버 로드 실패: $e');

      // 네트워크 에러 처리
      final networkError = NetworkUtils.parseError(e);
      setNetworkError(networkError);

      // clearData()를 호출하지 않음 (networkError는 유지)
      // 네트워크 오류 시에는 데이터를 유지하여 에러 상태 표시 가능
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _username == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      final postsResp = await blogService.getProfilePosts(
        _username!,
        page: _currentPage + 1,
        size: pageSize,
      );

      if (postsResp['success'] == true) {
        final List<dynamic> newPosts = postsResp['data']['posts'] ?? [];
        final totalPages = postsResp['data']['totalPages'] ?? 0;

        if (newPosts.isEmpty) {
          _hasMore = false;
        } else {
          // 새 포스트를 카테고리별로 병합
          for (final postData in newPosts) {
            if (postData is! Map<String, dynamic>) continue;

            final categoryId = (postData['categoryId'] ?? 0).toString();
            if (!postsByCategoryInternal.containsKey(categoryId)) {
              postsByCategoryInternal[categoryId] = [];
            }
            postsByCategoryInternal[categoryId]!.add(postData);
          }

          _currentPage++;
          _totalPages = totalPages;
          _hasMore = _currentPage < _totalPages;
        }
      } else {
        _hasMore = false;
      }
    } catch (e) {
      print('[OtherProfileFeedProvider] loadMore 실패: $e');
      _hasMore = false;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// 즉시 화면에서 기존 목록을 비우고 강제 재로딩
  Future<void> hardRefresh({String? username}) async {
    // 기존 사용자 정보도 초기화
    _username = null;

    // 피드 즉시 초기화
    clearData();

    // UI 즉시 업데이트 (이전 피드가 보이지 않도록)
    notifyListeners();

    // 새 데이터 로드
    await loadInitial(username: username, force: true);
  }

  @override
  void logout() {
    clearData();
    _loading = false;
    _loadingMore = false;
    _hasMore = true;
    _username = null;
    _currentPage = 0;
    _totalPages = 0;
    notifyListeners();
  }

  @override
  void clearInMemory() {
    clearData();
    _loading = false;
    _loadingMore = false;
    // 화면 dispose 중에는 알림을 보내지 않음 (프레임 락 방지)
  }

  @override
  Future<void> reorderAllSections(List<String> newOrderIds) async {
    throw UnsupportedError(
      'OtherProfileFeedProvider does not support reordering.',
    );
  }

  @override
  void reorderCategoriesLocally(List<int> orderedIntIds) {
    // no-op (읽기 전용)
  }

  @override
  void reorderPostsLocally(int categoryId, List<String> orderedPostIds) {
    // no-op (읽기 전용)
  }

  @override
  Future<void> reorderPostsInCategory(
    int categoryId,
    List<String> postIds,
  ) async {
    throw UnsupportedError(
      'OtherProfileFeedProvider does not support post reordering.',
    );
  }
}
