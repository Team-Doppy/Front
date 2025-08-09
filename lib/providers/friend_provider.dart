import 'package:flutter/material.dart';
import '../data/models/friend_model.dart';
import '../data/services/friend_service.dart';

class FriendProvider with ChangeNotifier {
  final FriendService _friendService = FriendService();

  List<Friend> _friends = [];
  List<Friend> get friends => _friends;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> fetchFriends() async {
    _isLoading = true;
    notifyListeners();

    try {
      _friends = await _friendService.getAcceptedFriends();
    } catch (e) {
      // 에러 처리
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}