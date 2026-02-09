import 'package:flutter/material.dart';
import '../data/services/letter_service.dart';

/// 받은 편지 데이터 관리 Provider
class LetterProvider with ChangeNotifier {
  final LetterService _letterService = LetterService();

  // 상태 변수
  List<Map<String, dynamic>> _recentLetters = [];
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastFetchTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5); // 5분 캐시

  // Getters
  List<Map<String, dynamic>> get recentLetters => _recentLetters;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasRecentLetters => _recentLetters.isNotEmpty;

  /// 최근 편지 로드 (최근 7일간)
  Future<void> loadRecentLetters({bool force = false, String? region}) async {
    // 캐시 확인 (force가 아닌 경우)
    if (!force && _isCacheValid()) {
      debugPrint('[LetterProvider] 캐시에서 최근 편지 로드');
      notifyListeners();
      return;
    }

    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('[LetterProvider] 최근 편지 서버에서 로드 시작');
      final data = await _letterService.getRecentLetters(region: region);

      // 응답 형식: { "letters": [...] }
      final letters = data['letters'] as List? ?? [];
      _recentLetters =
          letters.map((item) => item as Map<String, dynamic>).toList();

      _lastFetchTime = DateTime.now();
      _errorMessage = null;

      debugPrint('[LetterProvider] 최근 편지 로드 완료: ${_recentLetters.length}개');
    } catch (e) {
      debugPrint('[LetterProvider] 최근 편지 로드 실패: $e');
      _errorMessage = e.toString();
      // 에러 발생 시에도 기존 데이터는 유지
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 캐시 유효성 확인
  bool _isCacheValid() {
    if (_lastFetchTime == null || _recentLetters.isEmpty) return false;
    return DateTime.now().difference(_lastFetchTime!) < _cacheValidDuration;
  }

  /// 데이터 초기화
  void clearData() {
    _recentLetters.clear();
    _lastFetchTime = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// 로그아웃 시 모든 데이터 초기화
  void logout() {
    clearData();
    debugPrint('[LetterProvider] 로그아웃 - 모든 데이터 초기화 완료');
  }
}
