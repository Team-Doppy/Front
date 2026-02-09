import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/pages/components/military_user_search_chip.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/onbording/steps/military_girlfriend_confirmation_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

/// 선택된 사용자 정보
class _SelectedUserInfo {
  final String username;
  final String? profileImageUrl;
  final String? alias;
  final UserType? userType;

  _SelectedUserInfo({
    required this.username,
    this.profileImageUrl,
    this.alias,
    this.userType,
  });
}

/// 군인 정보 입력 - 유저 검색 단계 (곰신/가족 모드)
class MilitaryUserSearchStep extends StatefulWidget {
  final UserType userType;
  final List<String> initialUserIds;
  final Function(List<String>) onUserIdsSelected;
  final VoidCallback? onBack;
  final VoidCallback? onConfirm; // 확인 버튼 콜백 (가족/친구 모드용)
  final ValueNotifier<bool>? isLoadingNotifier; // ✅ 로딩 상태 전달용

  const MilitaryUserSearchStep({
    super.key,
    required this.userType,
    this.initialUserIds = const [],
    required this.onUserIdsSelected,
    this.onBack,
    this.onConfirm,
    this.isLoadingNotifier,
  });

  @override
  State<MilitaryUserSearchStep> createState() => _MilitaryUserSearchStepState();
}

class _MilitaryUserSearchStepState extends State<MilitaryUserSearchStep> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _selectedUserIds = [];
  bool _isSearching = false;
  // 선택된 사용자 정보 저장 (프로필 이미지, 별명 등)
  final Map<String, _SelectedUserInfo> _selectedUserInfoMap = {};

  @override
  void initState() {
    super.initState();
    _selectedUserIds = List<String>.from(widget.initialUserIds);
    _searchController.addListener(_onSearchChanged);

    // 화면이 나타나면 200ms 지연 후 자동으로 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    // 화면이 사라질 때 키보드 확실하게 내리기
    _focusNode.unfocus();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    SearchService().onSearchChanged('');
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    SearchService().onSearchChanged(query);
    setState(() {
      _isSearching = query.isNotEmpty;
    });
  }

  void _addUser(
    String username, {
    String? profileImageUrl,
    String? alias,
    UserType? userType,
  }) {
    if (_selectedUserIds.contains(username)) return;

    // 곰신 모드는 1명만 가능하고, 선택 시 즉시 확인 화면으로 이동
    if (widget.userType == UserType.girlfriend) {
      if (_selectedUserIds.isNotEmpty) {
        return;
      }

      // 곰신 모드: 선택한 사용자 정보 저장하고 확인 화면으로 이동
      _selectedUserInfoMap[username] = _SelectedUserInfo(
        username: username,
        profileImageUrl: profileImageUrl,
        alias: alias,
        userType: userType,
      );

      setState(() {
        _selectedUserIds.add(username);
      });
      widget.onUserIdsSelected(_selectedUserIds);

      // 키보드 내리기 (비동기로 처리하되 Hero 애니메이션은 즉시 시작)
      _focusNode.unfocus();
      FocusScope.of(context).unfocus();

      // ✅ 즉시 확인 화면으로 이동 (Hero 애니메이션 즉시 시작)
      final selectedInfo = _selectedUserInfoMap[username]!;
      // 다음 프레임에서 즉시 실행 (지연 없음)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 800), // Hero만 천천히
            reverseTransitionDuration: const Duration(milliseconds: 250),
            pageBuilder:
                (context, animation, secondaryAnimation) =>
                    MilitaryGirlfriendConfirmationStep(
                      selectedUsername: selectedInfo.username,
                      selectedProfileImageUrl: selectedInfo.profileImageUrl,
                      selectedAlias: selectedInfo.alias,
                      isLoadingNotifier: widget.isLoadingNotifier,
                      onConfirm: () {
                        // 확인 버튼 클릭 시 온보딩 완료 (곰신 모드)
                        // 로딩 상태는 onConfirm 콜백에서 관리
                        widget.onConfirm?.call();
                      },
                      onBack: () {
                        // 뒤로가기 시 선택 취소
                        _removeUser(username);
                        Navigator.of(context).pop();
                      },
                    ),
            // 화면 전환 애니메이션은 제거 (즉시 전환)
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return child;
            },
          ),
        );
      });
      return;
    }

    // 가족/친구 모드: 여러 명 선택 가능
    _selectedUserInfoMap[username] = _SelectedUserInfo(
      username: username,
      profileImageUrl: profileImageUrl,
      alias: alias,
      userType: userType,
    );

    setState(() {
      _selectedUserIds.add(username);
    });
    widget.onUserIdsSelected(_selectedUserIds);
    _searchController.clear();

    // 키보드 내리기
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _removeUser(String username) {
    setState(() {
      _selectedUserIds.remove(username);
      _selectedUserInfoMap.remove(username);
    });
    widget.onUserIdsSelected(_selectedUserIds);
  }

  @override
  Widget build(BuildContext context) {
    final searchService = context.watch<SearchService>();
    final accounts = searchService.searchingAccounts;
    final isSearchLoading = searchService.isLoading;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true, // ✅ 키보드에 따라 레이아웃 조정
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단: 뒤로가기 버튼 + 검색창
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  // 뒤로가기 버튼
                  if (widget.onBack != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      onPressed: () {
                        // 키보드가 올라와 있다면 내리고 0.3초 대기 후 뒤로가기
                        if (_focusNode.hasFocus) {
                          _focusNode.unfocus();
                          FocusScope.of(context).unfocus();
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted && widget.onBack != null) {
                              widget.onBack?.call();
                            }
                          });
                        } else {
                          widget.onBack?.call();
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  // 검색창
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      cursorColor: Theme.of(context).colorScheme.onSurface,
                      style: LocaleTypography.setStyle(
                        context: context,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () {},
                        ),
                        hintText: '내 군인 남친을 찾아봐요',
                        hintStyle: LocaleTypography.setStyle(
                          context: context,
                          fontSize: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child:
                  // 검색 중일 때는 shimmer 로딩 표시 (로딩 중이거나 검색 중이고 결과가 없을 때)
                  _isSearching &&
                          (isSearchLoading ||
                              (accounts.isEmpty && !searchService.hasSearched))
                      ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: 3, // shimmer 3개 표시
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                // 프로필 이미지 Shimmer
                                ShimmerBox(
                                  width: 60,
                                  height: 60,
                                  shape: const CircleBorder(),
                                ),
                                const SizedBox(width: 16),
                                // 사용자 정보 Shimmer
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ShimmerBox(
                                        width: 120,
                                        height: 16,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      const SizedBox(height: 8),
                                      ShimmerBox(
                                        width: 80,
                                        height: 14,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                      // ✅ 곰신 모드에서 선택된 사용자가 있고 Hero 애니메이션 중일 때는 검색 결과를 유지
                      : (_isSearching && accounts.isNotEmpty) ||
                          (widget.userType == UserType.girlfriend &&
                              _selectedUserIds.isNotEmpty &&
                              _searchController.text.isNotEmpty)
                      ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: accounts.length,
                        itemBuilder: (context, index) {
                          final account = accounts[index];
                          final username = account.username ?? '';
                          if (username.isEmpty) return const SizedBox.shrink();

                          final isSelected = _selectedUserIds.contains(
                            username,
                          );
                          final profileImageUrl = account.profileImageUrl ?? '';
                          final alias = account.alias ?? username;

                          // 서버 role을 UserType으로 변환 (null이면 배지 숨김)
                          final UserType? userType =
                              UserTypeExtension.fromServerRole(account.role);

                          return MilitaryUserSearchChip(
                            username: username,
                            alias: alias,
                            profileImageUrl: profileImageUrl,
                            userType: userType, // 서버에서 받아온 역할 정보 (null 가능)
                            // ✅ 곰신 모드: 남친 프사(아바타)만 Hero로 연결
                            avatarHeroTag:
                                widget.userType == UserType.girlfriend
                                    ? 'selected_profile_$username'
                                    : null,
                            isSelected: isSelected,
                            onTap: () {
                              if (isSelected) {
                                _removeUser(username);
                              } else {
                                _addUser(
                                  username,
                                  profileImageUrl: profileImageUrl,
                                  alias: alias,
                                  userType: userType,
                                );
                              }
                            },
                            onAdd:
                                () => _addUser(
                                  username,
                                  profileImageUrl: profileImageUrl,
                                  alias: alias,
                                  userType: userType,
                                ),
                          );
                        },
                      )
                      // 검색 결과가 없을 때 (검색이 완료되었고 결과가 없을 때만)
                      : _isSearching &&
                          accounts.isEmpty &&
                          !isSearchLoading &&
                          searchService.hasSearched
                      ? Center(
                        child: Text(
                          '검색결과가 없어요',
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                      )
                      : _selectedUserIds.isEmpty
                      ? Center(
                        child: Text(
                          '',
                          style: LocaleTypography.setStyle(
                            context: context,
                            fontSize: 16,
                            color: AppColors.lightSurfaceVariant.withOpacity(
                              0.5,
                            ),
                          ),
                        ),
                      )
                      : const SizedBox.shrink(),
            ),
            // 하단 버튼 영역 (키보드가 내려가 있고 검색 필드에 포커스가 없을 때만 표시)
            // 방법 1: MediaQuery로 키보드 상태 확인 (가장 정확)
            // if (MediaQuery.of(context).viewInsets.bottom == 0)
            // 방법 2: FocusNode로 포커스 상태 확인 (검색 필드에 포커스가 없을 때)
            if (!_focusNode.hasFocus)
              Container(
                padding: EdgeInsets.only(
                  left: 50,
                  right: 50,
                  bottom: MediaQuery.of(context).padding.bottom + 4,
                  top: 0,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
