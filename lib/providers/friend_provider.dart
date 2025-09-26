import 'package:flutter/material.dart';
import '../data/models/friend_model.dart';
import '../data/models/user_model.dart';
import '../data/services/friend_service.dart';

// 친구 요청 상태를 나타내는 enum
enum FriendRequestStatus { none, requested, accepted }

class FriendProvider with ChangeNotifier {
  final FriendService _friendService = FriendService();

  // --- 상태 변수 ---

  // '이웃 관리' 화면용 데이터
  List<Friend> _acceptedFriends = [];
  List<Friend> _receivedRequests = [];
  List<Friend> _sentRequests = [];
  bool _isLoading = false; // 목록 로딩 상태
  String? _errorMessage;

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

  List<User> get searchedUsers => _searchedUsers;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  FriendRequestStatus get friendStatus => _friendStatus;
  bool get isLoadingStatus => _isLoadingStatus;

  // --- API 호출 메소드 ---

  /// ✨ [추가] '이웃 관리' 화면에 필요한 모든 데이터를 한번에 불러옵니다.
  Future<void> fetchAllFriendData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _friendService.getAcceptedFriends(),
        _friendService.getReceivedFriendRequests(),
        _friendService.getSentFriendRequests(),
      ]);
      _acceptedFriends = results[0];
      _receivedRequests = results[1];
      _sentRequests = results[2];
    } catch (e) {
      _errorMessage = "데이터 로딩에 실패했습니다: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ✨ [추가] 친구 요청을 수락합니다.
  Future<bool> acceptFriendRequest(String requesterUsername) async {
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
      notifyListeners();
      return true;
    } catch (e) {
      print("친구 요청 수락 실패: $e");
      // TODO: UI에 에러 메시지 표시 (예: 스낵바)
      return false;
    }
  }

  /// 로딩 스피너(전체 쉬머) 없이 낙관적 갱신으로 처리
  Future<bool> acceptFriendRequestOptimistic(String requesterUsername) async {
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
  Future<bool> deleteFriend(String targetUsername) async {
    try {
      await _friendService.deleteFriend(targetUsername);
      // 목록/상태 국소 업데이트
      _acceptedFriends.removeWhere((f) => f.username == targetUsername);
      _receivedRequests.removeWhere((f) => f.username == targetUsername);
      _sentRequests.removeWhere((f) => f.username == targetUsername);
      _friendStatus = FriendRequestStatus.none;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('이웃 해제 실패: $e');
      return false;
    }
  }

  /// 특정 사용자와의 친구 상태 확인
  Future<void> checkFriendStatus(String targetUsername) async {
    _isLoadingStatus = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _friendService.getSentFriendRequests(),
        _friendService.getAcceptedFriends(),
      ]);
      final sentRequests = results[0];
      final acceptedFriends = results[1];

      if (acceptedFriends.any((f) => f.username == targetUsername)) {
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
    try {
      final String username = targetUsername.trim();
      if (username.isEmpty) {
        print("친구 신청 실패: targetUsername 비어있음");
        return false;
      }
      if (_friendStatus != FriendRequestStatus.none) {
        // 이미 요청했거나 수락된 상태는 중복 요청 방지
        return false;
      }

      await _friendService.sendFriendRequest(username);
      _friendStatus = FriendRequestStatus.requested; // UI 즉시 반영
      notifyListeners();
      return true;
    } catch (e) {
      print("친구 신청 실패: $e");
      return false;
    }
  }
}
