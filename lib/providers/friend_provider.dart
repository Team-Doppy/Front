import 'package:flutter/material.dart';
import '../data/models/friend_model.dart';
import '../data/services/friend_service.dart';

class FriendProvider with ChangeNotifier {
  final FriendService _friendService = FriendService();

  List<Friend> _acceptedFriends = [];
  List<Friend> _receivedRequests = [];

  bool _isLoading = false;
  String? _errorMessage;

  // --- Getter ---
  List<Friend> get acceptedFriends => _acceptedFriends;
  List<Friend> get receivedRequests => _receivedRequests; // ✨ 새 Getter
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // --- API 호출 메소드 ---

  // ✨ 두 API를 한 번에 호출하는 통합 메소드
  Future<void> fetchAllNeighborData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 두 API를 동시에 요청하여 시간 절약 (Future.wait)
      final results = await Future.wait([
        _friendService.getAcceptedFriends(),
        _friendService.getReceivedFriendRequests(),
      ]);
      // 결과 할당
      _acceptedFriends = results[0] as List<Friend>;
      _receivedRequests = results[1] as List<Friend>;

    } catch (e) {
      _errorMessage = "데이터를 불러오는데 실패했습니다: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ✨ 친구 요청 수락 API 호출 메소드
  Future<bool> acceptFriendRequest(String requesterUsername) async {
    try {
      await _friendService.acceptFriendRequest(requesterUsername);
      // 성공 시, 화면을 즉시 갱신하여 '수락됨'으로 보이게 함
      // 1. 요청 목록에서 해당 유저 제거
      _receivedRequests.removeWhere((req) => req.username == requesterUsername);
      // 2. 친구 목록에 추가 (이 부분은 선택적. 전체 목록을 다시 fetch해도 됨)
      // fetchAllNeighborData(); // 혹은 간단히 전체 데이터를 다시 불러옴
      notifyListeners();
      return true;
    } catch (e) {
      print("친구 요청 수락 실패: $e");
      return false;
    }
  }
}