import 'package:flutter/material.dart';
import '../data/models/friend_model.dart';
import '../data/services/friend_service.dart';

// 친구 요청 상태를 나타내는 enum
enum FriendRequestStatus { none, requested, accepted }

class FriendProvider with ChangeNotifier {
  final FriendService _friendService = FriendService();

  // --- 상태 변수 ---

  // '이웃 관리' 화면용 데이터
  List<Friend> _acceptedFriends = [];
  List<Friend> _receivedRequests = [];
  bool _isLoading = false; // 목록 로딩 상태
  String? _errorMessage;

  // '다른 사용자 프로필' 화면용 데이터
  FriendRequestStatus _friendStatus = FriendRequestStatus.none;
  bool _isLoadingStatus = false; // 개별 친구 상태 로딩

  // --- Getter ---
  List<Friend> get acceptedFriends => _acceptedFriends;
  List<Friend> get receivedRequests => _receivedRequests;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

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
      ]);
      _acceptedFriends = results[0];
      _receivedRequests = results[1];
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
      // 성공 시, 목록을 새로고침하여 UI에 즉시 반영
      await fetchAllFriendData();
      return true;
    } catch (e) {
      print("친구 요청 수락 실패: $e");
      // TODO: UI에 에러 메시지 표시 (예: 스낵바)
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
      await _friendService.sendFriendRequest(targetUsername);
      _friendStatus = FriendRequestStatus.requested; // UI 즉시 반영
      notifyListeners();
      return true;
    } catch (e) {
      print("친구 신청 실패: $e");
      return false;
    }
  }
}