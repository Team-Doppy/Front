import 'package:doppy/providers/feed_provider/base_feed_provider.dart';
import 'package:doppy/providers/feed_provider/profile_feed_filter.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/data/models/profile_access_level.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 공개범위 필터 관리
class CategoryFilterManager extends ValueNotifier<String?> {
  static final CategoryFilterManager _instance =
      CategoryFilterManager._internal();
  factory CategoryFilterManager() => _instance;
  CategoryFilterManager._internal() : super(null);

  void setCategory(String? category) {
    value = category;
  }

  void clearFilter() {
    value = null;
  }

  bool get isFiltered => value != null;
}

class CategoryDropDown {
  VoidCallback? _onCategoryChanged;

  /// 공개범위 변경 콜백 설정
  void setOnCategoryChanged(VoidCallback? callback) {
    _onCategoryChanged = callback;
  }

  /// 리소스 정리
  void dispose() {
    // 리소스 정리 (현재 사용하지 않음)
  }

  /// 공개범위 + Phase 필터 드롭다운 표시 (BottomSheet)
  void showCategoryDropdown(
    BuildContext context,
    GlobalKey buttonKey,
    BaseFeedProvider feedProvider, {
    Function(String? phaseKey)? onPhaseSelected,
    String? currentPhaseKey,
    Map<String, List<Map<String, dynamic>>>? systemCategoryMappings,
    String? currentAccessLevelKey,
    Function(String? accessLevelKey)? onAccessLevelSelected,
    List<Map<String, dynamic>>? sections,
    Function(String? phaseKey, String? accessLevelKey)? onFilterApplied,
  }) async {
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _CategorySheetContent(
          feedProvider: feedProvider,
          onPhaseSelected: onPhaseSelected,
          currentPhaseKey: currentPhaseKey,
          systemCategoryMappings: systemCategoryMappings,
          currentAccessLevelKey: currentAccessLevelKey,
          onAccessLevelSelected: onAccessLevelSelected,
          onCategoryChanged: _onCategoryChanged,
          sections: sections,
          onFilterApplied: onFilterApplied,
        );
      },
    );
  }
}

class _CategorySheetContent extends StatefulWidget {
  final BaseFeedProvider feedProvider;
  final Function(String? phaseKey)? onPhaseSelected;
  final String? currentPhaseKey;
  final Map<String, List<Map<String, dynamic>>>? systemCategoryMappings;
  final String? currentAccessLevelKey;
  final Function(String? accessLevelKey)? onAccessLevelSelected;
  final VoidCallback? onCategoryChanged;
  final List<Map<String, dynamic>>? sections;
  final Function(String? phaseKey, String? accessLevelKey)? onFilterApplied;

  const _CategorySheetContent({
    required this.feedProvider,
    this.onPhaseSelected,
    this.currentPhaseKey,
    this.systemCategoryMappings,
    this.currentAccessLevelKey,
    this.onAccessLevelSelected,
    this.onCategoryChanged,
    this.sections,
    this.onFilterApplied,
  });

  @override
  State<_CategorySheetContent> createState() => _CategorySheetContentState();
}

class _CategorySheetContentState extends State<_CategorySheetContent> {
  late String? _selectedPhaseKey;
  late String? _selectedAccessLevelKey;
  late FixedExtentScrollController _phaseController;
  late FixedExtentScrollController _accessLevelController;

  bool get _shouldHidePhasePicker {
    final sections = widget.sections;
    if (sections == null || sections.isEmpty) return false;
    if (sections.length != 1) return false;
    final phase = sections.first['phase'] as String?;
    return phase == 'all';
  }

  @override
  void initState() {
    super.initState();
    _selectedPhaseKey = widget.currentPhaseKey;
    _selectedAccessLevelKey = widget.currentAccessLevelKey;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    final militaryInfo = currentUser?.militaryInfo;
    final isGirlfriend = militaryInfo?.userType == UserType.girlfriend;

    // Phase 컨트롤러 초기화
    final availableFilters = _getAvailablePhaseFilters(isGirlfriend);
    int phaseIndex = 0;
    for (int i = 0; i < availableFilters.length; i++) {
      final filter = availableFilters[i];
      final phaseKey =
          filter == ProfileFeedFilter.all
              ? null
              : (filter == ProfileFeedFilter.leave
                  ? 'leave'
                  : (filter == ProfileFeedFilter.preEnlistmentMemory
                      ? 'preEnlistmentMemory'
                      : filter.phaseCode));
      if (phaseKey == widget.currentPhaseKey) {
        phaseIndex = i;
        break;
      }
    }
    _phaseController = FixedExtentScrollController(initialItem: phaseIndex);

    // AccessLevel 컨트롤러 초기화
    // ✅ 서버에서 오는 키를 ProfileAccessLevel.tabOrder 순서로 정렬
    final keys = <String?>[null];
    if (widget.systemCategoryMappings != null) {
      // 서버에서 실제로 데이터가 있는 키만 수집
      final availableKeys = <String>[];
      for (final k in widget.systemCategoryMappings!.keys) {
        if (ProfileAccessLevel.isValid(k)) {
          final list = widget.systemCategoryMappings![k];
          if (list != null && list.isNotEmpty) {
            availableKeys.add(k);
          }
        }
      }
      // tabOrder 순서로 정렬 (PUBLIC → FRIENDS → PRIVATE)
      availableKeys.sort((a, b) {
        final order = ProfileAccessLevel.tabOrder;
        final i = order.indexOf(a);
        final j = order.indexOf(b);
        if (i == -1 && j == -1) return a.compareTo(b);
        if (i == -1) return 1;
        if (j == -1) return -1;
        return i.compareTo(j);
      });
      keys.addAll(availableKeys);
    }
    int accessLevelIndex = 0;
    for (int i = 0; i < keys.length; i++) {
      final k = keys[i];
      final isSelected =
          (k == null &&
              (widget.currentAccessLevelKey == null ||
                  widget.currentAccessLevelKey!.isEmpty)) ||
          (k != null && k == widget.currentAccessLevelKey);
      if (isSelected) {
        accessLevelIndex = i;
        break;
      }
    }
    _accessLevelController = FixedExtentScrollController(
      initialItem: accessLevelIndex,
    );
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _accessLevelController.dispose();
    super.dispose();
  }

  /// systemCategoryMappings와 sections에 있는 phase만 필터링
  List<ProfileFeedFilter> _getAvailablePhaseFilters(bool isGirlfriend) {
    // sections에서 실제 있는 phase 추출
    final availablePhases = <String>{};
    if (widget.sections != null) {
      for (final section in widget.sections!) {
        final phase = section['phase'] as String?;
        if (phase != null && phase.isNotEmpty) {
          availablePhases.add(phase);
        }
      }
    }

    // 모든 가능한 필터 목록
    final allFilters =
        isGirlfriend
            ? [
              ProfileFeedFilter.all,
              ProfileFeedFilter.preEnlistment,
              ProfileFeedFilter.training,
              ProfileFeedFilter.private,
              ProfileFeedFilter.privateFirstClass,
              ProfileFeedFilter.corporal,
              ProfileFeedFilter.sergeant,
            ]
            : [
              ProfileFeedFilter.all,
              ProfileFeedFilter.preEnlistmentMemory,
              ProfileFeedFilter.training,
              ProfileFeedFilter.private,
              ProfileFeedFilter.privateFirstClass,
              ProfileFeedFilter.corporal,
              ProfileFeedFilter.sergeant,
              ProfileFeedFilter.leave,
            ];

    // '전체'는 항상 포함, 나머지는 availablePhases에 있는 것만 포함
    return allFilters.where((filter) {
      if (filter == ProfileFeedFilter.all) return true;

      final phaseCode =
          filter == ProfileFeedFilter.leave
              ? 'leave'
              : (filter == ProfileFeedFilter.preEnlistmentMemory
                  ? 'preEnlistmentMemory'
                  : filter.phaseCode);

      return phaseCode != null && availablePhases.contains(phaseCode);
    }).toList();
  }

  /// 필터가 활성화되어 있는지 확인
  bool _isPhaseFilterEnabled(ProfileFeedFilter filter) {
    if (filter == ProfileFeedFilter.all) return true;

    if (widget.sections == null || widget.sections!.isEmpty) return false;

    final phaseCode =
        filter == ProfileFeedFilter.leave
            ? 'leave'
            : (filter == ProfileFeedFilter.preEnlistmentMemory
                ? 'preEnlistmentMemory'
                : filter.phaseCode);

    if (phaseCode == null) return false;

    return widget.sections!.any((section) {
      final phase = section['phase'] as String?;
      return phase == phaseCode;
    });
  }

  Future<void> _applySelection() async {
    // ✅ 선택한 필터 조합에 데이터가 있는지 확인
    bool hasData = false;

    // Phase 필터 확인
    final hasPhaseData =
        _selectedPhaseKey == null
            ? (widget.sections != null && widget.sections!.isNotEmpty)
            : (widget.sections?.any((section) {
                  final phase = section['phase'] as String?;
                  return phase == _selectedPhaseKey;
                }) ??
                false);

    // AccessLevel 필터 확인
    final hasAccessLevelData =
        _selectedAccessLevelKey == null
            ? (widget.systemCategoryMappings != null &&
                widget.systemCategoryMappings!.values.any(
                  (list) => list.isNotEmpty,
                ))
            : (widget.systemCategoryMappings?[_selectedAccessLevelKey] !=
                    null &&
                (widget
                        .systemCategoryMappings![_selectedAccessLevelKey]
                        ?.isNotEmpty ??
                    false));

    // 필터 조합에 데이터가 있는지 확인
    if (_selectedPhaseKey == null && _selectedAccessLevelKey == null) {
      // 둘 다 전체: sections에 데이터가 있으면 OK
      hasData = hasPhaseData;
    } else if (_selectedPhaseKey != null && _selectedAccessLevelKey != null) {
      // 둘 다 선택: 둘 다 데이터가 있어야 함 (서버에서 교집합 필터링)
      hasData = hasPhaseData && hasAccessLevelData;
    } else if (_selectedPhaseKey != null) {
      // phase만 선택: sections에 해당 phase가 있으면 OK
      hasData = hasPhaseData;
    } else {
      // accessLevel만 선택: systemCategoryMappings에 해당 키가 있으면 OK
      hasData = hasAccessLevelData;
    }

    // 데이터가 없으면 경고 표시
    if (!hasData) {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('선택할 수 없습니다'),
              content: const Text('해당 필터에 맞는 글이 없습니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('확인'),
                ),
              ],
            ),
      );
      return;
    }

    // ✅ 데이터가 있으면 먼저 모달 닫기
    widget.onCategoryChanged?.call();
    Navigator.of(context).pop();

    // ✅ 모달 닫은 후 필터 적용 및 provider에서 데이터 가져오기 (비동기로 실행)
    if (widget.onFilterApplied != null) {
      // phase와 accessLevel을 동시에 설정하는 콜백 사용
      widget.onFilterApplied!(_selectedPhaseKey, _selectedAccessLevelKey);
    } else {
      // 기존 방식 (하위 호환성)
      if (widget.onPhaseSelected != null) {
        widget.onPhaseSelected!(_selectedPhaseKey);
      }
      if (widget.onAccessLevelSelected != null) {
        widget.onAccessLevelSelected!(_selectedAccessLevelKey);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    final militaryInfo = currentUser?.militaryInfo;
    final isGirlfriend = militaryInfo?.userType == UserType.girlfriend;

    final availableFilters = _getAvailablePhaseFilters(isGirlfriend);
    // ✅ 서버에서 오는 키를 ProfileAccessLevel.tabOrder 순서로 정렬
    final keys = <String?>[null];
    if (widget.systemCategoryMappings != null) {
      // 서버에서 실제로 데이터가 있는 키만 수집
      final availableKeys = <String>[];
      for (final k in widget.systemCategoryMappings!.keys) {
        if (ProfileAccessLevel.isValid(k)) {
          final list = widget.systemCategoryMappings![k];
          if (list != null && list.isNotEmpty) {
            availableKeys.add(k);
          }
        }
      }
      // tabOrder 순서로 정렬 (PUBLIC → FRIENDS → PRIVATE)
      availableKeys.sort((a, b) {
        final order = ProfileAccessLevel.tabOrder;
        final i = order.indexOf(a);
        final j = order.indexOf(b);
        if (i == -1 && j == -1) return a.compareTo(b);
        if (i == -1) return 1;
        if (j == -1) return -1;
        return i.compareTo(j);
      });
      keys.addAll(availableKeys);
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들 바
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // 가로 배치: 복무 단계 - 공개 범위
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  // 복무 단계 (통짜 타임라인(phase=all)일 땐 숨김)
                  if (militaryInfo != null &&
                      !isGirlfriend &&
                      !_shouldHidePhasePicker) ...[
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: _phaseController,
                        itemExtent: 40,
                        onSelectedItemChanged: (index) {
                          final filter = availableFilters[index];
                          // 비활성화된 필터는 선택 불가
                          if (!_isPhaseFilterEnabled(filter)) return;

                          setState(() {
                            _selectedPhaseKey =
                                filter == ProfileFeedFilter.all
                                    ? null
                                    : (filter == ProfileFeedFilter.leave
                                        ? 'leave'
                                        : (filter ==
                                                ProfileFeedFilter
                                                    .preEnlistmentMemory
                                            ? 'preEnlistmentMemory'
                                            : filter.phaseCode));
                          });
                        },
                        children:
                            availableFilters.map((filter) {
                              final isEnabled = _isPhaseFilterEnabled(filter);
                              return Center(
                                child: Text(
                                  filter.displayName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color:
                                        isEnabled
                                            ? CupertinoColors.label
                                            : CupertinoColors.systemGrey,
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // 공개 범위
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: _accessLevelController,
                      itemExtent: 40,
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedAccessLevelKey = keys[index];
                        });
                      },
                      children:
                          keys.map((k) {
                            final title =
                                k == null
                                    ? context.tr('all')
                                    : ProfileAccessLevel.toDisplayLabel(k);
                            return Center(
                              child: Text(
                                title,
                                style: const TextStyle(fontSize: 16),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // 적용하기 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _applySelection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    '적용하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
