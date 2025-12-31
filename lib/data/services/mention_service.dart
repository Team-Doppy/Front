import 'dart:convert';

import 'package:doppy/data/models/mention_user.dart';
import 'package:doppy/utils/time_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ✅ 멘션(언급) 히스토리를 관리하는 서비스
/// - UI(overlay)와 분리된 순수 비즈니스 로직
/// - 저장소: SharedPreferences('mention_history')
class MentionService extends ChangeNotifier {
  static final MentionService _instance = MentionService._internal();
  factory MentionService() => _instance;
  MentionService._internal();

  List<_MentionHistoryEntry> _mentionHistory = [];
  static const int _maxHistorySize = 10;
  static const String _mentionHistoryKey = 'mention_history';

  List<_MentionHistoryEntry> get mentionHistory => List.from(_mentionHistory);

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

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_mentionHistoryKey);

      if (historyJson != null) {
        final List<dynamic> historyList = json.decode(historyJson);
        _mentionHistory =
            historyList
                .whereType<Map>()
                .map(
                  (m) =>
                      _MentionHistoryEntry.fromJson(m.cast<String, dynamic>()),
                )
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

  void addToHistory(MentionUser user) {
    try {
      final existingIndex = _mentionHistory.indexWhere(
        (entry) => entry.username == user.username,
      );

      if (existingIndex >= 0) {
        final entry = _mentionHistory.removeAt(existingIndex);
        _mentionHistory.insert(0, entry);
      } else {
        final entry = _MentionHistoryEntry(
          username: user.username,
          alias: user.alias,
          profileImageUrl: user.profileImageUrl,
          timestamp: DateTime.now(),
        );
        _mentionHistory.insert(0, entry);
      }

      if (_mentionHistory.length > _maxHistorySize) {
        _mentionHistory = _mentionHistory.take(_maxHistorySize).toList();
      }

      _saveToPreferences();
      notifyListeners();

      debugPrint('[MentionService] Added ${user.username} to mention history');
    } catch (e) {
      debugPrint('[MentionService] Error adding to history: $e');
    }
  }

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
      username: (json['username'] ?? '').toString(),
      alias: json['alias']?.toString(),
      profileImageUrl: json['profileImageUrl']?.toString(),
      timestamp: TimeUtils.toLocalTime(
        (json['timestamp'] ?? DateTime.now().toIso8601String()).toString(),
      ),
    );
  }
}

