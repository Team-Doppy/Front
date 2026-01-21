import 'package:flutter/material.dart';

import 'base_feed_provider.dart';
import '../../utils/network_utils.dart';

/// 다른 사람 피드 전용 Provider (캐시 없음, 항상 서버에서 로드)
class OtherProfileFeedProvider extends BaseFeedProvider {
  // 싱글톤 패턴
  static final OtherProfileFeedProvider _instance =
      OtherProfileFeedProvider._internal();
  factory OtherProfileFeedProvider() => _instance;
  OtherProfileFeedProvider._internal();

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
      debugPrint('[OtherProfileFeedProvider] username이 null입니다');
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
      _totalPages = postsData?['totalPages'] ?? 0;
      _hasMore = postsData?['hasNext'] ?? false;

      debugPrint('[OtherProfileFeedProvider] 서버 로드 완료: $_username');
    } catch (e) {
      debugPrint('[OtherProfileFeedProvider] 서버 로드 실패: $e');

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
      // getProfileFeed는 이미 { success, data, message }에서 data만 추출해서 반환
      final feedData = await blogService.getProfileFeed(
        _username!,
        page: _currentPage + 1,
        size: pageSize,
      );

      // feedData는 이미 data 필드의 내용 (ProfileFeedSchemaAndPostsResponse)
      final postsData = feedData['posts'] as Map<String, dynamic>?;
      final List<dynamic> newPosts = postsData?['posts'] ?? [];
      final totalPages = postsData?['totalPages'] ?? 0;
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
        _totalPages = totalPages;
        _hasMore = hasNext;
      }
    } catch (e) {
      debugPrint('[OtherProfileFeedProvider] loadMore 실패: $e');
      _hasMore = false;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// 기존 데이터를 유지하면서 새로운 데이터로 교체
  Future<void> hardRefresh({String? username}) async {
    // 기존 사용자 정보도 초기화
    _username = null;
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
    // 선택 상태도 초기화
    selectBase(BaseFilter.all);
    notifyListeners();
    debugPrint('[OtherProfileFeedProvider] 로그아웃 - 모든 데이터 초기화 완료');
  }

  @override
  void clearInMemory() {
    clearData();
    _loading = false;
    _loadingMore = false;
    // 화면 dispose 중에는 알림을 보내지 않음 (프레임 락 방지)
  }

  @override
  void reorderPostsLocally(List<String> orderedPostIds) {
    // no-op (읽기 전용)
  }

  @override
  Future<void> reorderPosts(List<String> postIds) async {
    throw UnsupportedError(
      'OtherProfileFeedProvider does not support post reordering.',
    );
  }
}
