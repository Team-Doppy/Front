import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 언급 관련 비즈니스 로직을 담당하는 서비스
class MentionService extends ChangeNotifier {
  static final MentionService _instance = MentionService._internal();
  factory MentionService() => _instance;
  MentionService._internal();

  // 언급 기록 (사용자 객체 기반)
  List<_MentionHistoryEntry> _mentionHistory = [];
  static const int _maxHistorySize = 10;
  static const String _mentionHistoryKey = 'mention_history';

  // Getters
  List<_MentionHistoryEntry> get mentionHistory => List.from(_mentionHistory);

  /// 언급 기록을 사용자 객체 형태로 변환
  List<MentionUser> get mentionHistoryAsUsers {
    final seen = <String>{};
    final result = <MentionUser>[];
    for (final e in _mentionHistory) {
      if (seen.add(e.username)) {
        result.add(
          MentionUser(
            username: e.username,
            alias: e.alias?.isNotEmpty == true ? e.alias! : e.username,
            profileImageUrl: e.profileImageUrl ?? '',
          ),
        );
      }
    }
    return result;
  }

  /// 초기화 - SharedPreferences에서 언급 기록 로드
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_mentionHistoryKey);

      if (historyJson != null) {
        final List<dynamic> historyList = json.decode(historyJson);
        _mentionHistory =
            historyList
                .map((json) => _MentionHistoryEntry.fromJson(json))
                .toList();
      } else {
        _mentionHistory = [];
      }

      debugPrint(
        '[MentionService] Loaded ${_mentionHistory.length} mention history entries',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[MentionService] Error loading mention history: $e');
      _mentionHistory = [];
    }
  }

  /// 사용자를 언급 기록에 추가
  void addToHistory(MentionUser user) {
    try {
      // 이미 존재하는지 확인
      final existingIndex = _mentionHistory.indexWhere(
        (entry) => entry.username == user.username,
      );

      if (existingIndex >= 0) {
        // 이미 존재하면 맨 앞으로 이동
        final entry = _mentionHistory.removeAt(existingIndex);
        _mentionHistory.insert(0, entry);
      } else {
        // 새로 추가
        final entry = _MentionHistoryEntry(
          username: user.username,
          alias: user.alias,
          profileImageUrl: user.profileImageUrl,
          timestamp: DateTime.now(),
        );
        _mentionHistory.insert(0, entry);
      }

      // 최대 크기 제한
      if (_mentionHistory.length > _maxHistorySize) {
        _mentionHistory = _mentionHistory.take(_maxHistorySize).toList();
      }

      // SharedPreferences에 저장
      _saveToPreferences();
      notifyListeners();

      debugPrint('[MentionService] Added ${user.username} to mention history');
    } catch (e) {
      debugPrint('[MentionService] Error adding to history: $e');
    }
  }

  /// 사용자를 언급 기록에서 제거
  void removeFromHistory(String username) {
    try {
      _mentionHistory.removeWhere((entry) => entry.username == username);
      _saveToPreferences();
      notifyListeners();

      debugPrint('[MentionService] Removed $username from mention history');
    } catch (e) {
      debugPrint('[MentionService] Error removing from history: $e');
    }
  }

  /// 언급 기록 전체 삭제
  void clearHistory() {
    try {
      _mentionHistory.clear();
      _saveToPreferences();
      notifyListeners();

      debugPrint('[MentionService] Cleared all mention history');
    } catch (e) {
      debugPrint('[MentionService] Error clearing history: $e');
    }
  }

  /// SharedPreferences에 저장
  Future<void> _saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = json.encode(
        _mentionHistory.map((entry) => entry.toJson()).toList(),
      );
      await prefs.setString(_mentionHistoryKey, historyJson);
    } catch (e) {
      debugPrint('[MentionService] Error saving to preferences: $e');
    }
  }
}

/// 언급 기록 엔트리
class _MentionHistoryEntry {
  final String username;
  final String? alias;
  final String? profileImageUrl;
  final DateTime timestamp;

  const _MentionHistoryEntry({
    required this.username,
    this.alias,
    this.profileImageUrl,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'alias': alias,
      'profileImageUrl': profileImageUrl,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory _MentionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return _MentionHistoryEntry(
      username: json['username'] ?? '',
      alias: json['alias'],
      profileImageUrl: json['profileImageUrl'],
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

/// 언급 사용자 모델
class MentionUser {
  final String username;
  final String alias;
  final String profileImageUrl;

  const MentionUser({
    required this.username,
    required this.alias,
    required this.profileImageUrl,
  });
}
