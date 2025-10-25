import 'dart:ui';

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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(182, 96, 96, 96),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close, color: Colors.white, size: 22),
        ),
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
      ),

      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 배경 블러 + 반투명
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              onVerticalDragEnd: (d) {
                if (d.primaryVelocity != null && d.primaryVelocity! > 400) {
                  Navigator.of(context).pop();
                }
              },
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(color: const Color.fromARGB(182, 96, 96, 96)),
              ),
            ),
          ),
          Column(
            children: [
              SizedBox(height: 20),
              if (_loading || _results.isNotEmpty)
                SizedBox(
                  height: 140,
                  child:
                      _loading
                          ? ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemBuilder: (_, i) => _LoadingCircleUser(),
                            separatorBuilder:
                                (_, __) => const SizedBox(width: 8),
                            itemCount: 6, // 로딩 중일 때 6개 표시
                          )
                          : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
              Expanded(
                child: Container(
                  child:
                      _selected.isNotEmpty
                          ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemBuilder:
                                  (_, i) => _SelectedRowChip(
                                    label: _selected[i].username,
                                    onRemove: () => _toggleSelect(_selected[i]),
                                  ),
                              separatorBuilder:
                                  (_, __) => const SizedBox(height: 8),
                              itemCount: _selected.length,
                            ),
                          )
                          : Container(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _selected.isEmpty
                            ? Colors.transparent
                            : _selected.length == 1
                            ? Theme.of(context).colorScheme.onSurface
                            : AppColors.darkTextPrimary,
                    foregroundColor:
                        _selected.isEmpty
                            ? Colors.transparent
                            : _selected.length == 1
                            ? Theme.of(context).colorScheme.surface
                            : AppColors.darkBackground,
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
            ],
          ),
        ],
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
    setState(() {
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(user);
      }
    });
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
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.darkSurfaceVariant,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.darkBorder,
                    width: selected ? 3.5 : 1,
                  ),
                ),
                child: CommonProfileAvatar(
                  username: user.username,
                  size: 100,
                  borderWidth: 1,

                  imageUrl: user.imageUrl,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 12,
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
          const Icon(Icons.alternate_email, color: Colors.white70, size: 16),

          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: Colors.white70, size: 16),
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
