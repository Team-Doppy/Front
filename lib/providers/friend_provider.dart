import 'package:flutter/material.dart';
import '../data/models/friend_model.dart';
import '../data/models/user_model.dart';
import '../data/services/friend_service.dart';
import 'group_provider.dart';

// 친구 요청 상태를 나타내는 enum
enum FriendRequestStatus { none, requested, accepted, pending, blocked }

class FriendProvider with ChangeNotifier {
  final FriendService _friendService = FriendService();

  // --- 상태 변수 ---

  // '이웃 관리' 화면용 데이터
  List<Friend> _acceptedFriends = [];
  List<Friend> _receivedRequests = [];
  List<Friend> _sentRequests = [];
  bool _isLoading = false; // 목록 로딩 상태
  String? _errorMessage;

  // 🎯 페이지네이션 상태
  int _acceptedFriendsPage = 0;
  bool _hasMoreAcceptedFriends = true;
  bool _isLoadingMoreAcceptedFriends = false;

  int _receivedRequestsPage = 0;
  bool _hasMoreReceivedRequests = true;
  bool _isLoadingMoreReceivedRequests = false;

  int _sentRequestsPage = 0;
  bool _hasMoreSentRequests = true;
  bool _isLoadingMoreSentRequests = false;

  // 🎯 타이밍 기반 캐시
  DateTime? _lastFetchTime;
  static const Duration _cacheValidDuration = Duration(
    minutes: 1,
  ); // 캐시 유효 시간 (1분)

  // ✨ 사용자 검색을 위한 상태 변수 추가
  List<User> _searchedUsers = [];
  bool _isSearching = false;
  String? _searchError;

  // '다른 사용자 프로필' 화면용 데이터
  FriendRequestStatus _friendStatus = FriendRequestStatus.none;
  bool _isLoadingStatus = false; // 개별 친구 상태 로딩

  // --- Getter ---
  List<Friend> get acceptedFriends => _acceptedFriends;
  List<Friend> get receivedRequests => _receivedRequests;
  List<Friend> get sentRequests => _sentRequests;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // 🎯 페이지네이션 getters
  bool get hasMoreAcceptedFriends => _hasMoreAcceptedFriends;
  bool get isLoadingMoreAcceptedFriends => _isLoadingMoreAcceptedFriends;
  bool get hasMoreReceivedRequests => _hasMoreReceivedRequests;
  bool get isLoadingMoreReceivedRequests => _isLoadingMoreReceivedRequests;
  bool get hasMoreSentRequests => _hasMoreSentRequests;
  bool get isLoadingMoreSentRequests => _isLoadingMoreSentRequests;

  List<User> get searchedUsers => _searchedUsers;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  FriendRequestStatus get friendStatus => _friendStatus;
  bool get isLoadingStatus => _isLoadingStatus;

  // --- API 호출 메소드 ---

  /// ✨ [추가] '이웃 관리' 화면에 필요한 모든 데이터를 한번에 불러옵니다.
  /// 타이밍 기반 캐시 사용: forceRefresh가 false이고 캐시가 유효하면 서버 조회 스킵
  Future<void> fetchAllFriendData({bool forceRefresh = false}) async {
    // 🎯 타이밍 기반 캐시 체크
    final now = DateTime.now();
    final isCacheValid =
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < _cacheValidDuration;

    if (!forceRefresh && isCacheValid) {
      print(
        '[FriendProvider] 캐시 유효 - 서버 조회 스킵 (${now.difference(_lastFetchTime!).inSeconds}초 전 조회)',
      );
      return; // 캐시가 유효하면 서버 조회 스킵
    }

    _isLoading = true;
    _errorMessage = null;

    // 🎯 페이지네이션 초기화
    _acceptedFriendsPage = 0;
    _receivedRequestsPage = 0;
    _sentRequestsPage = 0;
    _hasMoreAcceptedFriends = true;
    _hasMoreReceivedRequests = true;
    _hasMoreSentRequests = true;

    notifyListeners();
    try {
      final results = await Future.wait([
        _friendService.getAcceptedFriends(page: 0, size: 20),
        _friendService.getReceivedFriendRequests(page: 0, size: 20),
        _friendService.getSentFriendRequests(page: 0, size: 20),
      ]);
      _acceptedFriends = results[0];
      _receivedRequests = results[1];
      _sentRequests = results[2];

      // 🎯 더 불러올 데이터가 있는지 확인
      _hasMoreAcceptedFriends = results[0].length >= 20;
      _hasMoreReceivedRequests = results[1].length >= 20;
      _hasMoreSentRequests = results[2].length >= 20;

      // 🎯 페이지 번호 증가
      if (_hasMoreAcceptedFriends) _acceptedFriendsPage = 1;
      if (_hasMoreReceivedRequests) _receivedRequestsPage = 1;
      if (_hasMoreSentRequests) _sentRequestsPage = 1;

      // 🎯 조회 시간 저장
      _lastFetchTime = DateTime.now();
      print('[FriendProvider] 서버에서 데이터 새로고침 완료');
    } catch (e) {
      _errorMessage = "데이터 로딩에 실패했습니다: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 🎯 수락된 친구 목록 더 불러오기 (무한 스크롤)
  Future<void> loadMoreAcceptedFriends() async {
    if (_isLoadingMoreAcceptedFriends || !_hasMoreAcceptedFriends) return;

    _isLoadingMoreAcceptedFriends = true;
    notifyListeners();

    try {
      final newFriends = await _friendService.getAcceptedFriends(
        page: _acceptedFriendsPage,
        size: 20,
      );

      _acceptedFriends.addAll(newFriends);
      _hasMoreAcceptedFriends = newFriends.length >= 20;
      if (_hasMoreAcceptedFriends) {
        _acceptedFriendsPage++;
      }
    } catch (e) {
      print('[FriendProvider] 수락된 친구 목록 더 불러오기 실패: $e');
      _hasMoreAcceptedFriends = false;
    } finally {
      _isLoadingMoreAcceptedFriends = false;
      notifyListeners();
    }
  }

  /// 🎯 받은 친구 요청 목록 더 불러오기 (무한 스크롤)
  Future<void> loadMoreReceivedRequests() async {
    if (_isLoadingMoreReceivedRequests || !_hasMoreReceivedRequests) return;

    _isLoadingMoreReceivedRequests = true;
    notifyListeners();

    try {
      final newRequests = await _friendService.getReceivedFriendRequests(
        page: _receivedRequestsPage,
        size: 20,
      );

      _receivedRequests.addAll(newRequests);
      _hasMoreReceivedRequests = newRequests.length >= 20;
      if (_hasMoreReceivedRequests) {
        _receivedRequestsPage++;
      }
    } catch (e) {
      print('[FriendProvider] 받은 친구 요청 목록 더 불러오기 실패: $e');
      _hasMoreReceivedRequests = false;
    } finally {
      _isLoadingMoreReceivedRequests = false;
      notifyListeners();
    }
  }

  /// 🎯 보낸 친구 요청 목록 더 불러오기 (무한 스크롤)
  Future<void> loadMoreSentRequests() async {
    if (_isLoadingMoreSentRequests || !_hasMoreSentRequests) return;

    _isLoadingMoreSentRequests = true;
    notifyListeners();

    try {
      final newRequests = await _friendService.getSentFriendRequests(
        page: _sentRequestsPage,
        size: 20,
      );

      _sentRequests.addAll(newRequests);
      _hasMoreSentRequests = newRequests.length >= 20;
      if (_hasMoreSentRequests) {
        _sentRequestsPage++;
      }
    } catch (e) {
      print('[FriendProvider] 보낸 친구 요청 목록 더 불러오기 실패: $e');
      _hasMoreSentRequests = false;
    } finally {
      _isLoadingMoreSentRequests = false;
      notifyListeners();
    }
  }

  /// ✨ [추가] 친구 요청을 수락합니다.
  /// 반환값: true = 성공, false = 일반 실패, null = 요청이 이미 취소됨
  Future<bool?> acceptFriendRequest(
    String requesterUsername, {
    GroupProvider? groupProvider,
  }) async {
    try {
      await _friendService.acceptFriendRequest(requesterUsername);
      // 성공 시, 받은 요청 → 수락으로 이동 (글로벌 로딩 없이 국소 업데이트)
      final int idx = _receivedRequests.indexWhere(
        (f) => f.username == requesterUsername,
      );
      if (idx != -1) {
        final moved = _receivedRequests.removeAt(idx);
        _acceptedFriends.add(moved);
      }

      // 🎯 allFriends 그룹의 memberCount 업데이트 (선택적 업데이트)
      if (groupProvider != null) {
        groupProvider.updateAllFriendsMemberCount(1);
      }

      notifyListeners();
      return true;
    } catch (e) {
      print("친구 요청 수락 실패: $e");
      // 🎯 이미 취소된 요청인 경우 null 반환 (UI에서 구분 가능)
      if (e.toString().contains('이미 취소되었거나 존재하지 않습니다') ||
          e.toString().contains('FriendRequestNotFoundException')) {
        // 데이터 새로고침하여 UI 업데이트
        await fetchAllFriendData(forceRefresh: true);
        return null; // null = 요청이 이미 취소됨
      }
      return false; // 일반 실패
    }
  }

  /// 로딩 스피너(전체 쉬머) 없이 낙관적 갱신으로 처리
  Future<bool> acceptFriendRequestOptimistic(
    String requesterUsername, {
    GroupProvider? groupProvider,
  }) async {
    try {
      await _friendService.acceptFriendRequest(requesterUsername);
      // 받은 요청 목록에서 제거하고, 수락된 친구 목록에 추가
      final int idx = _receivedRequests.indexWhere(
        (f) => f.username == requesterUsername,
      );
      if (idx != -1) {
        final friend = _receivedRequests.removeAt(idx);
        _acceptedFriends.add(friend);
      }

      // 🎯 allFriends 그룹의 memberCount 업데이트 (선택적 업데이트)
      if (groupProvider != null) {
        groupProvider.updateAllFriendsMemberCount(1);
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('acceptFriendRequestOptimistic failed: $e');
      return false;
    }
  }

  Future<bool> cancelSentRequest(String targetUsername) async {
    try {
      await _friendService.cancelFriendRequest(targetUsername);
      _sentRequests.removeWhere((f) => f.username == targetUsername);
      notifyListeners();
      return true;
    } catch (e) {
      print("친구 요청 취소 실패: $e");
      return false;
    }
  }

  /// 로딩 스피너(전체 쉬머) 없이 낙관적 취소 처리
  Future<bool> cancelSentRequestOptimistic(String targetUsername) async {
    try {
      await _friendService.cancelFriendRequest(targetUsername);
      _sentRequests.removeWhere((f) => f.username == targetUsername);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('cancelSentRequestOptimistic failed: $e');
      return false;
    }
  }

  /// 이웃(친구) 해제
  Future<bool> deleteFriend(
    String targetUsername, {
    GroupProvider? groupProvider,
  }) async {
    _isLoadingStatus = true;
    notifyListeners();
    try {
      await _friendService.deleteFriend(targetUsername);
      // 목록/상태 국소 업데이트
      final wasAccepted = _acceptedFriends.any(
        (f) => f.username == targetUsername,
      );
      _acceptedFriends.removeWhere((f) => f.username == targetUsername);
      _receivedRequests.removeWhere((f) => f.username == targetUsername);
      _sentRequests.removeWhere((f) => f.username == targetUsername);
      _friendStatus = FriendRequestStatus.none;

      // 🎯 allFriends 그룹의 memberCount 업데이트 (선택적 업데이트)
      if (groupProvider != null && wasAccepted) {
        groupProvider.updateAllFriendsMemberCount(-1);
      }

      return true;
    } catch (e) {
      debugPrint('이웃 해제 실패: $e');
      return false;
    } finally {
      _isLoadingStatus = false;
      notifyListeners();
    }
  }

  /// 여러 이웃(친구) 일괄 해제
  Future<bool> deleteFriendsBatch(
    List<String> usernames, {
    GroupProvider? groupProvider,
  }) async {
    try {
      print('🔄 [FriendProvider] 친구 일괄 해제: ${usernames.length}명');
      await _friendService.deleteFriendsBatch(usernames);

      // 목록에서 일괄 제거
      int acceptedCount = 0;
      for (final username in usernames) {
        if (_acceptedFriends.any((f) => f.username == username)) {
          acceptedCount++;
        }
        _acceptedFriends.removeWhere((f) => f.username == username);
        _receivedRequests.removeWhere((f) => f.username == username);
        _sentRequests.removeWhere((f) => f.username == username);
      }

      // 🎯 allFriends 그룹의 memberCount 업데이트 (선택적 업데이트)
      if (groupProvider != null && acceptedCount > 0) {
        groupProvider.updateAllFriendsMemberCount(-acceptedCount);
      }

      notifyListeners();
      print('✅ [FriendProvider] 친구 일괄 해제 완료');
      return true;
    } catch (e) {
      print('❌ [FriendProvider] 친구 일괄 해제 실패: $e');
      return false;
    }
  }

  /// 특정 사용자와의 친구 상태 확인
  Future<void> checkFriendStatus(String targetUsername) async {
    _isLoadingStatus = true;
    // initState에서 호출될 수 있으므로 notifyListeners() 제거
    // notifyListeners();
    try {
      final results = await Future.wait([
        _friendService.getSentFriendRequests(page: 0, size: 20),
        _friendService.getAcceptedFriends(page: 0, size: 20),
        _friendService.getBlockedUsers(), // 🎯 차단 목록 조회
      ]);
      final sentRequests = results[0] as List<Friend>;
      final acceptedFriends = results[1] as List<Friend>;
      final blockedUsers = results[2] as List<User>;

      // 🎯 차단된 사용자인지 먼저 확인
      if (blockedUsers.any((u) => u.username == targetUsername)) {
        _friendStatus = FriendRequestStatus.blocked;
      } else if (acceptedFriends.any((f) => f.username == targetUsername)) {
        _friendStatus = FriendRequestStatus.accepted;
      } else if (sentRequests.any((r) => r.username == targetUsername)) {
        _friendStatus = FriendRequestStatus.requested;
      } else {
        _friendStatus = FriendRequestStatus.none;
      }
    } finally {
      _isLoadingStatus = false;
      notifyListeners();
    }
  }

  /// 친구 신청 보내기
  Future<bool> sendFriendRequest(String targetUsername) async {
    _isLoadingStatus = true;
    notifyListeners();
    try {
      final String username = targetUsername.trim();
      if (username.isEmpty) {
        print("친구 신청 실패: targetUsername 비어있음");
        _isLoadingStatus = false;
        notifyListeners();
        return false;
      }
      if (_friendStatus != FriendRequestStatus.none) {
        // 이미 요청했거나 수락된 상태는 중복 요청 방지
        _isLoadingStatus = false;
        notifyListeners();
        return false;
      }

      await _friendService.sendFriendRequest(username);
      _friendStatus = FriendRequestStatus.requested; // UI 즉시 반영
      return true;
    } catch (e) {
      print("친구 신청 실패: $e");
      return false;
    } finally {
      _isLoadingStatus = false;
      notifyListeners();
    }
  }

  /// 사용자 검색
  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _searchedUsers.clear();
      _searchError = null;
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      _searchedUsers = await _friendService.searchUsers(query.trim());
    } catch (e) {
      _searchError = "검색에 실패했습니다: $e";
      _searchedUsers.clear();
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// 검색 결과 초기화
  void clearSearchResults() {
    _searchedUsers.clear();
    _searchError = null;
    notifyListeners();
  }

  /// 로그아웃 시 모든 친구 데이터 초기화
  void logout() {
    _acceptedFriends.clear();
    _receivedRequests.clear();
    _sentRequests.clear();
    _isLoading = false;
    _errorMessage = null;
    _lastFetchTime = null; // 🎯 캐시 시간도 초기화

    // 🎯 페이지네이션 상태 초기화
    _acceptedFriendsPage = 0;
    _receivedRequestsPage = 0;
    _sentRequestsPage = 0;
    _hasMoreAcceptedFriends = true;
    _hasMoreReceivedRequests = true;
    _hasMoreSentRequests = true;
    _isLoadingMoreAcceptedFriends = false;
    _isLoadingMoreReceivedRequests = false;
    _isLoadingMoreSentRequests = false;

    _searchedUsers.clear();
    _isSearching = false;
    _searchError = null;
    _friendStatus = FriendRequestStatus.none;
    _isLoadingStatus = false;
    notifyListeners();
    print('[FriendProvider] 로그아웃 - 친구 데이터 초기화 완료');
  }
}
