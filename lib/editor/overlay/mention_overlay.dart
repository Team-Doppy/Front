import 'dart:ui';

import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/data/services/search_service.dart';

import 'dart:convert';
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

class MentionOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final void Function(String username)? onSelect; // 단건 선택 (호환)
  final void Function(List<String> usernames)? onSubmit; // 누적 제출

  const MentionOverlay({super.key, this.onClose, this.onSelect, this.onSubmit});

  @override
  State<MentionOverlay> createState() => _MentionOverlayState();
}

class _MentionOverlayState extends State<MentionOverlay> {
  final TextEditingController _controller = TextEditingController(text: '');
  final FocusNode _focusNode = FocusNode();

  // 서비스 참조
  late final MentionService _mentionService;
  late final SearchService _searchService;

  List<_UserChip> _results = const [];
  final List<_UserChip> _selected = <_UserChip>[];
  bool _loading = false;
  DateTime? _lastQueryAt;

  // 드래그 관련 상태
  double _dragStartY = 0.0;
  double _dragStartX = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();

    // 서비스 초기화
    _mentionService = MentionService();
    _searchService = SearchService();

    // 언급 서비스 초기화 및 최근 언급 대상 로드
    _initializeServices();

    // 키보드 자동 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _initializeServices() async {
    await _mentionService.initialize();
    _loadRecentMentions();
  }

  void _loadRecentMentions() {
    final recentUsers = _mentionService.mentionHistoryAsUsers;
    _results =
        recentUsers
            .map(
              (user) => _UserChip(
                username: user.username,
                imageUrl: user.profileImageUrl,
                alias: user.alias,
              ),
            )
            .toList();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = _controller.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D).withOpacity(0.9),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,

        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: TextField(
            cursorColor: AppColors.darkTextPrimary,
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,

            style: TextStyle(color: AppColors.darkTextPrimary, fontSize: 18),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              hintText: '누구를 언급할까요?',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              suffixIcon:
                  _controller.text.isNotEmpty
                      ? IconButton(
                        tooltip: '검색',
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                        },
                        icon: Icon(
                          Icons.search,
                          color: Colors.white.withOpacity(0.8),
                          size: 22,
                        ),
                      )
                      : Icon(
                        Icons.search,
                        color: Colors.white.withOpacity(0.6),
                        size: 22,
                      ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
              isDense: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide.none,
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(
              Icons.close,
              color: Colors.white.withOpacity(0.7),
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),

      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onPanStart: (details) {
          _dragStartY = details.globalPosition.dy;
          _dragStartX = details.globalPosition.dx;
          _isDragging = true;
        },
        onPanUpdate: (details) {
          if (!_isDragging) return;

          final currentY = details.globalPosition.dy;
          final currentX = details.globalPosition.dx;
          final deltaY = currentY - _dragStartY;
          final deltaX = (currentX - _dragStartX).abs();

          // 아래로 50px 이상 드래그하면 바로 닫기
          if (deltaY > 50) {
            _isDragging = false;
            Navigator.of(context).pop();
            return;
          }

          // 좌우로 50px 이상 드래그하면 바로 닫기
          if (deltaX > 50) {
            _isDragging = false;
            Navigator.of(context).pop();
            return;
          }
        },
        onPanEnd: (details) {
          if (!_isDragging) return;

          // 드래그 속도에 따라 오버레이 닫기
          final velocity = details.velocity.pixelsPerSecond;
          if (velocity.dy.abs() > velocity.dx.abs()) {
            // 세로 드래그 (아래로)
            if (velocity.dy > 200) {
              Navigator.of(context).pop();
            }
          } else {
            // 가로 드래그 (좌우)
            if (velocity.dx.abs() > 200) {
              Navigator.of(context).pop();
            }
          }
          _isDragging = false;
        },
        child: Stack(
          children: [
            // 배경 블러 + 반투명
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    color: const Color(0xFF2D2D2D).withOpacity(0.9),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                SizedBox(height: 20),
                if (hasQuery)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 140,
                        child:
                            _loading
                                ? ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemBuilder: (_, i) => _LoadingCircleUser(),
                                  separatorBuilder:
                                      (_, __) => const SizedBox(width: 8),
                                  itemCount: 6,
                                )
                                : (_results.isNotEmpty
                                    ? ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      itemBuilder: (_, i) {
                                        final item = _results[i];
                                        final bool selected = _selected.any(
                                          (s) => s.username == item.username,
                                        );
                                        return _CircleUser(
                                          user: item,
                                          selected: selected,
                                          isRecentMention: false,
                                          onTap: () => _toggleSelect(item),
                                        );
                                      },
                                      separatorBuilder:
                                          (_, __) => const SizedBox(width: 8),
                                      itemCount: _results.length,
                                    )
                                    : Center(
                                      child: Text(
                                        context.tr('no_search_results'),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    )),
                      ),
                    ],
                  )
                else if (!hasQuery &&
                    _selected.isEmpty &&
                    (_loading || _results.isNotEmpty))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 140,
                        child:
                            _loading
                                ? ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemBuilder: (_, i) => _LoadingCircleUser(),
                                  separatorBuilder:
                                      (_, __) => const SizedBox(width: 8),
                                  itemCount: 6,
                                )
                                : ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemBuilder: (_, i) {
                                    final item = _results[i];
                                    final bool selected = _selected.any(
                                      (s) => s.username == item.username,
                                    );
                                    final bool isRecentMention =
                                        _controller.text.isEmpty;
                                    return _CircleUser(
                                      user: item,
                                      selected: selected,
                                      isRecentMention: isRecentMention,
                                      onTap: () => _toggleSelect(item),
                                      onRemove:
                                          isRecentMention
                                              ? () => _removeFromRecent(item)
                                              : null,
                                    );
                                  },
                                  separatorBuilder:
                                      (_, __) => const SizedBox(width: 8),
                                  itemCount: _results.length,
                                ),
                      ),
                    ],
                  ),
                Expanded(
                  child: Container(
                    child:
                        !hasQuery && _selected.isNotEmpty
                            ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemBuilder:
                                          (_, i) => _SelectedRowChip(
                                            label: _selected[i].username,
                                            onRemove:
                                                () =>
                                                    _toggleSelect(_selected[i]),
                                          ),
                                      separatorBuilder:
                                          (_, __) => const SizedBox(height: 8),
                                      itemCount: _selected.length,
                                    ),
                                  ),
                                ),
                              ],
                            )
                            : Container(),
                  ),
                ),
                // 선택된 사람이 있을 때만 버튼 표시
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        minimumSize: Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: _submit,
                      child: const Text(
                        '언급하기',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                SizedBox(height: 5),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onQueryChanged(String q) {
    setState(() => _loading = true);
    final now = DateTime.now();
    _lastQueryAt = now;

    Future.delayed(const Duration(milliseconds: 220), () async {
      if (_lastQueryAt != now) return; // 최신 쿼리만 반영

      final String qq = q.trim().toLowerCase();
      List<_UserChip> next;

      if (qq.isEmpty) {
        // 검색어가 비어있으면 최근 언급 대상 표시
        next =
            _mentionService.mentionHistoryAsUsers
                .map(
                  (user) => _UserChip(
                    username: user.username,
                    imageUrl: user.profileImageUrl,
                    alias: user.alias,
                  ),
                )
                .toList();
      } else {
        // 실제 검색 수행
        _searchService.onSearchChanged(qq);
        await Future.delayed(const Duration(milliseconds: 300)); // 검색 완료 대기
        final searchResults = _searchService.searchingAccounts;

        // 검색 결과를 _UserChip 형태로 변환
        next =
            searchResults
                .map(
                  (item) => _UserChip(
                    username: item.username ?? '',
                    imageUrl: item.profileImageUrl ?? '',
                    alias: item.alias ?? item.username ?? '',
                  ),
                )
                .toList();
      }

      if (mounted) {
        setState(() {
          _results = next;
          _loading = false;
        });
      }
    });
  }

  void _toggleSelect(_UserChip user) {
    final idx = _selected.indexWhere((s) => s.username == user.username);
    final bool wasSelected = idx >= 0;
    setState(() {
      if (wasSelected) {
        _selected.removeAt(idx);
      } else {
        _selected.add(user);
      }
    });

    // 새로 추가된 경우: 검색을 종료하고 "이미 추가한 사람" 섹션으로 전환
    if (!wasSelected) {
      _controller.clear();
      _onQueryChanged('');
      // 포커스 유지로 추가를 연속할 수 있게 함
      _focusNode.requestFocus();
    }
  }

  void _submit() {
    if (_selected.isEmpty) return;

    // 선택된 사용자들을 언급 기록에 추가
    for (final user in _selected) {
      _mentionService.addToHistory(
        MentionUser(
          username: user.username,
          alias: user.alias ?? user.username,
          profileImageUrl: user.imageUrl ?? '',
        ),
      );
    }

    widget.onSubmit?.call(_selected.map((e) => e.username).toList());
    for (final u in _selected) {
      widget.onSelect?.call(u.username);
    }
    Navigator.of(context).maybePop();
  }

  void _removeFromRecent(_UserChip user) {
    _mentionService.removeFromHistory(user.username);
    _loadRecentMentions();
  }
}

// (old _MentionChip removed in favor of _CircleUser)

class _UserChip {
  final String username;
  final String? imageUrl;
  final String? alias;
  const _UserChip({required this.username, this.imageUrl, this.alias});
}

// (old horizontal chip no longer used; replaced by _SelectedRowChip)

class _CircleUser extends StatelessWidget {
  final _UserChip user;
  final bool selected;
  final bool isRecentMention;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _CircleUser({
    required this.user,
    required this.selected,
    required this.isRecentMention,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: selected ? AppColors.primary : Colors.transparent,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: CommonProfileAvatar(
                    username: user.username,
                    size: 80,
                    borderWidth: 1,
                    borderColor:
                        selected ? AppColors.primary : Colors.transparent,
                    imageUrl: user.imageUrl,
                  ),
                ),
              ),
              // 최근 언급 대상일 때만 X 버튼 표시
              if (isRecentMention && onRemove != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Icon(
                        Icons.close,
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withOpacity(0.4),
                        size: 17,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 80,
            child: Text(
              user.alias ?? user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.darkTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedRowChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _SelectedRowChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),

      child: Row(
        children: [
          Icon(Icons.alternate_email, color: Colors.white, size: 20),

          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
              child: Text(
                '취소',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCircleUser extends StatefulWidget {
  const _LoadingCircleUser();

  @override
  State<_LoadingCircleUser> createState() => _LoadingCircleUserState();
}

class _LoadingCircleUserState extends State<_LoadingCircleUser>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.darkSurfaceVariant.withOpacity(
                  _animation.value,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceVariant.withOpacity(
                  _animation.value,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        );
      },
    );
  }
}
