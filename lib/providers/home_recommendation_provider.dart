import 'dart:async';

import 'package:flutter/material.dart';
import '../data/models/home_recommendation_model.dart';
import '../data/services/blog_service.dart';

class HomeRecommendationProvider with ChangeNotifier {
  final BlogService _blogService = BlogService();

  List<RecCardForHomeResponse> _recommendations = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RecCardForHomeResponse> get recommendations => _recommendations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 홈용 추천 카드 로드
  Future<void> loadHomeRecommendations() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await _blogService.getHomeRecommendations();
      final recommendations =
          data.map((json) => RecCardForHomeResponse.fromJson(json)).toList();

      setState(() {
        _recommendations = recommendations;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[HomeRecommendationProvider] 추천 카드 로드 실패: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 타입별 추천 카드 필터링
  List<RecCardForHomeResponse> getRecommendationsByType(RecCardType type) {
    return _recommendations.where((rec) => rec.recType == type).toList();
  }

  /// 상태 업데이트 헬퍼
  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  /// 초기화
  void clear() {
    _recommendations = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
