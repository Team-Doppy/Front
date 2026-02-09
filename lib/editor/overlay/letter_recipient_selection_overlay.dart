import 'dart:ui';

import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:provider/provider.dart';

/// Letter 모드: 발송 대상 선택 화면
class LetterRecipientSelectionScreen extends StatefulWidget {
  final String? initialRecipientUsername; // 초기 선택된 수신인 (자동 선택용)
  final List<String>? initialRecipientUsernames; // 초기 선택된 수신인 목록
  final bool returnResult; // 결과를 반환할지 여부 (PostExportScreen에서 사용)

  const LetterRecipientSelectionScreen({
    super.key,
    this.initialRecipientUsername,
    this.initialRecipientUsernames,
    this.returnResult = false, // 기본값: false (기존 동작 유지)
  });

  @override
  State<LetterRecipientSelectionScreen> createState() =>
      _LetterRecipientSelectionScreenState();
}

class _LetterRecipientSelectionScreenState
    extends State<LetterRecipientSelectionScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController(text: '');
  final FocusNode _focusNode = FocusNode();

  List<_RecipientOption> _allRecipients = [];
  List<_RecipientOption> _filteredRecipients = [];
  final List<_RecipientOption> _selected = <_RecipientOption>[]; // ✅ 여러 명 선택 가능
  bool _loading = false;
  DateTime? _lastQueryAt; // 검색 쿼리 시간 추적

  // 서비스 참조
  late final SearchService _searchService;

  // 페이드 애니메이션
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // 친구 목록 슬라이드 다운 애니메이션
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  bool _hasAnimatedFriendList = false;

  // 연결된 짝궁 username (여친 확인용)
  String? _connectedPartnerUsername;

  @override
  void initState() {
    super.initState();

    // 페이드 애니메이션 초기화
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    // 슬라이드 다운 애니메이션 초기화
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3), // 위에서 시작
      end: Offset.zero, // 원래 위치
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    // 서비스 초기화
    _searchService = SearchService();

    // 수신인 목록 로드
    _loadRecipients();

    // 초기 수신인이 있으면 자동 선택 및 자동 제출
    if (widget.initialRecipientUsername != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectRecipientByUsername(widget.initialRecipientUsername!);
        // 자동 선택된 경우 바로 제출
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _selected.isNotEmpty) {
            _submit();
          }
        });
      });
    } else {
      // 키보드 자동 표시 (자동 선택이 아닐 때만)
      // ✅ initialRecipientUsernames는 _loadRecipients()에서 처리
      if (widget.initialRecipientUsernames == null ||
          widget.initialRecipientUsernames!.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      }
    }
  }

  Future<void> _loadRecipients() async {
    setState(() => _loading = true);

    final userProvider = context.read<UserProvider>();
    final friendProvider = context.read<FriendProvider>();
    final currentUser = userProvider.currentUser;

    final recipients = <_RecipientOption>[];

    // 1. 모든 친구 옵션 추가
    recipients.add(
      _RecipientOption(
        username: 'all_friends',
        alias: '모든 친구',
        imageUrl: null,
        isAllFriends: true,
        isPartner: false,
      ),
    );

    // 2. 연결된 짝궁 확인 및 추가 (곰신일 때 남친, 군인일 때 곰신)
    if (currentUser != null) {
      final userType = currentUser.militaryInfo?.userType;
      User? partner;

      if (userType == UserType.girlfriend) {
        // 곰신: connectedMilitaryUser (남친)
        partner = currentUser.connectedMilitaryUser;
      } else if (userType == UserType.military ||
          userType == UserType.plannedEnlistment) {
        // 군인/입대 예정자: connectedToMeByUser (곰신)
        partner = currentUser.connectedToMeByUser;
      }

      if (partner != null) {
        _connectedPartnerUsername = partner.username;
        recipients.add(
          _RecipientOption(
            username: partner.username,
            alias: partner.alias ?? partner.username,
            imageUrl: partner.profileImageUrl,
            isAllFriends: false,
            isPartner: true, // ✅ 여친 표시
          ),
        );
      }
    }

    // 3. 친구 목록 추가
    final friends = friendProvider.acceptedFriends;
    for (final friend in friends) {
      // 이미 추가된 짝궁은 제외
      if (recipients.any((r) => r.username == friend.username)) {
        continue;
      }

      // 여친인지 확인 (role 필드 확인)
      bool isPartner = false;
      if (friend.role != null) {
        final friendUserType = UserTypeExtension.fromServerRole(friend.role!);
        if (friendUserType == UserType.girlfriend) {
          isPartner = true;
        }
      }
      // 또는 연결된 짝궁과 username이 일치하는지 확인
      if (!isPartner && _connectedPartnerUsername != null) {
        isPartner = friend.username == _connectedPartnerUsername;
      }

      recipients.add(
        _RecipientOption(
          username: friend.username,
          alias: friend.alias,
          imageUrl: friend.profileImageUrl,
          isAllFriends: false,
          isPartner: isPartner,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _allRecipients = recipients;
        _filteredRecipients = recipients;
        _loading = false;
      });

      // ✅ 초기 선택된 멤버들이 있으면 선택 상태로 설정
      if (widget.initialRecipientUsernames != null &&
          widget.initialRecipientUsernames!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            for (final username in widget.initialRecipientUsernames!) {
              _selectRecipientByUsername(username);
            }
          }
        });
      }

      // 친구 목록이 있고 검색어가 없으면 슬라이드 애니메이션 시작
      if (_filteredRecipients.isNotEmpty &&
          _controller.text.trim().isEmpty &&
          !_hasAnimatedFriendList) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _slideController.forward();
            _hasAnimatedFriendList = true;
          }
        });
      }
    }
  }

  void _selectRecipientByUsername(String username) {
    final recipient = _allRecipients.firstWhere(
      (r) => r.username == username,
      orElse: () => _allRecipients.first, // 기본값: 모든 친구
    );

    setState(() {
      if (!_selected.any((s) => s.username == recipient.username)) {
        _selected.add(recipient);
      }
    });
  }

  Widget _buildCircleUserList() {
    final bool hasQuery = _controller.text.trim().isNotEmpty;

    // ✅ 선택된 항목을 제외한 리스트 생성
    final availableRecipients =
        _filteredRecipients
            .where((item) => !_selected.any((s) => s.username == item.username))
            .toList();

    final bool showFriendList = !hasQuery && availableRecipients.isNotEmpty;

    if (hasQuery) {
      // 검색 모드
      if (_loading) {
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemBuilder: (_, i) => const _LoadingCircleUser(),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemCount: 6,
        );
      } else if (availableRecipients.isNotEmpty) {
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemBuilder: (_, i) {
            final item = availableRecipients[i];
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    ),
                    child: child,
                  ),
                );
              },
              child: _CircleUser(
                key: ValueKey(item.username),
                user: item,
                selected: false, // 선택된 항목은 이미 필터링됨
                onTap: () => _toggleSelect(item),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemCount: availableRecipients.length,
        );
      } else {
        return Center(
          child: Text(
            '검색 결과가 없습니다',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        );
      }
    } else {
      // 친구 목록 모드
      if (showFriendList) {
        if (_loading) {
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemBuilder: (_, i) => const _LoadingCircleUser(),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: 6,
          );
        } else if (availableRecipients.isNotEmpty) {
          return SlideTransition(
            position: _slideAnimation,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (_, i) {
                final item = availableRecipients[i];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: _CircleUser(
                    key: ValueKey(item.username),
                    user: item,
                    selected: false, // 선택된 항목은 이미 필터링됨
                    onTap: () => _toggleSelect(item),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: availableRecipients.length,
            ),
          );
        }
      }
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = _controller.text.trim().isNotEmpty;
    // 검색어가 없고 친구 목록이 있을 때만 원형 목록 표시
    final bool showFriendList = !hasQuery && _filteredRecipients.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                size: 22,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Container(
              height: 52, // ✅ 높이 고정
              alignment: Alignment.center, // ✅ 중앙 정렬
              padding: const EdgeInsets.symmetric(vertical: 0),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: widget.initialRecipientUsername == null,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  FocusScope.of(context).unfocus();
                },
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  height: 1.0, // ✅ 줄 높이 고정
                ),
                cursorColor: Theme.of(context).colorScheme.onSurface,
                maxLines: 1, // ✅ 한 줄로 고정
                minLines: 1, // ✅ 최소 한 줄
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant,
                  isDense: false, // ✅ isDense를 false로 변경하여 높이 확보
                  hintText: '누구에게 보낼까요?',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.0, // ✅ 줄 높이 고정
                  ),
                  suffixIcon:
                      _controller.text.isNotEmpty
                          ? IconButton(
                            tooltip: '지우기',
                            onPressed: () {
                              _controller.clear();
                              _onQueryChanged('');
                            },
                            icon: Icon(
                              Icons.close,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                              size: 20,
                            ),
                          )
                          : null,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16, // ✅ vertical padding 증가
                    horizontal: 16,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                    borderSide: BorderSide.none,
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 20),
                // 친구 목록 또는 검색 결과 표시 (원형)
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: SizedBox(
                    key: ValueKey('friend_list_${showFriendList}_${hasQuery}'),
                    height: hasQuery || showFriendList ? 140 : 0,
                    child: _buildCircleUserList(),
                  ),
                ),
                const SizedBox(height: 30),
                // 선택된 수신인 표시 영역
                Expanded(
                  child: Container(
                    child:
                        _selected.isNotEmpty
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
                                          (_, i) => _AnimatedSelectedRowChip(
                                            index: i,
                                            child: _SelectedRowChip(
                                              label:
                                                  _selected[i].alias ??
                                                  _selected[i].username,
                                              username: _selected[i].username,
                                              imageUrl: _selected[i].imageUrl,
                                              isPartner: _selected[i].isPartner,
                                              onRemove:
                                                  () => _toggleSelect(
                                                    _selected[i],
                                                  ),
                                            ),
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
                // 선택된 수신인이 있을 때만 버튼 표시
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.onSurface,
                        foregroundColor: Theme.of(context).colorScheme.surface,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: _submit,
                      child: const Text(
                        '계속하기',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditor() {
    if (_selected.isEmpty) return;

    // ✅ 선택한 친구 목록을 전체 정보로 변환
    final selectedRecipients =
        _selected
            .map(
              (r) => {
                'username': r.username,
                'alias': r.alias ?? r.username,
                'imageUrl': r.imageUrl,
              },
            )
            .toList();

    // ✅ empty state 메시지 생성
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    String? emptyStateMessage;

    // ✅ 짝궁(연결된 파트너) 확인
    User? partner;
    if (currentUser != null) {
      final userType = currentUser.militaryInfo?.userType;
      if (userType == UserType.girlfriend) {
        partner = currentUser.connectedMilitaryUser;
      } else if (userType == UserType.military ||
          userType == UserType.plannedEnlistment) {
        partner = currentUser.connectedToMeByUser;
      }
    }

    // ✅ 짝궁만 선택된 경우: "내 남친에게 포스팅" 또는 "내 여친에게 포스팅"
    if (partner != null &&
        selectedRecipients.length == 1 &&
        selectedRecipients.first['username'] == partner.username) {
      if (currentUser?.militaryInfo?.userType == UserType.girlfriend) {
        emptyStateMessage = '내 남친에게 포스팅';
      } else {
        emptyStateMessage = '내 여친에게 포스팅';
      }
    } else if (selectedRecipients.length > 1) {
      // ✅ 여러 명 선택된 경우: "{첫 번째 사람의 alias} 외 n명에게 포스팅하기"
      final firstPersonAlias =
          (selectedRecipients.first['alias'] ??
                  selectedRecipients.first['username'] ??
                  '선택한 사람')
              .toString();
      final otherCount = selectedRecipients.length - 1;
      emptyStateMessage = '$firstPersonAlias 외 $otherCount명에게 포스팅하기';
    } else {
      // ✅ 1명만 선택된 경우 (짝궁이 아닌 경우)
      final personAlias =
          (selectedRecipients.first['alias'] ??
                  selectedRecipients.first['username'] ??
                  '선택한 사람')
              .toString();
      emptyStateMessage = '$personAlias에게 포스팅하기';
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => PostwriteScreen(
              isEditingMode: false,
              mode: PostWriteMode.letter,
              initialRecipientUsername: _selected.first.username,
              initialRecipients: selectedRecipients, // ✅ 선택한 친구 전체 정보 전달
              emptyStateMessage: emptyStateMessage,
              disableAutoFocus: true,
            ),
      ),
    );
  }

  void _onQueryChanged(String q) {
    setState(() => _loading = true);
    final now = DateTime.now();
    _lastQueryAt = now;

    final String qq = q.trim().toLowerCase();

    Future.delayed(const Duration(milliseconds: 220), () async {
      if (_lastQueryAt != now) return; // 최신 쿼리만 반영

      List<_RecipientOption> next;

      if (qq.isEmpty) {
        // 검색어가 비어있으면 전체 친구 목록 표시
        next = _allRecipients;
      } else {
        // 1. 로컬 친구 목록에서 검색
        final localResults =
            _allRecipients
                .where(
                  (r) =>
                      (r.alias?.toLowerCase().contains(qq) ?? false) ||
                      r.username.toLowerCase().contains(qq),
                )
                .toList();

        // 2. 서버에서 검색
        _searchService.onSearchChanged(qq);
        await Future.delayed(const Duration(milliseconds: 300)); // 검색 완료 대기
        final searchResults = _searchService.searchingAccounts;

        // 3. 서버 검색 결과를 _RecipientOption으로 변환
        final serverResults =
            searchResults.map((item) {
              // 여친인지 확인
              bool isPartner = false;
              if (item.role != null) {
                final userType = UserTypeExtension.fromServerRole(item.role!);
                if (userType == UserType.girlfriend) {
                  isPartner = true;
                }
              }
              // 또는 연결된 짝궁과 username이 일치하는지 확인
              if (!isPartner && _connectedPartnerUsername != null) {
                isPartner = item.username == _connectedPartnerUsername;
              }

              return _RecipientOption(
                username: item.username ?? '',
                alias: item.alias ?? item.username ?? '',
                imageUrl: item.profileImageUrl ?? '',
                isAllFriends: false,
                isPartner: isPartner,
              );
            }).toList();

        // 4. 로컬과 서버 결과를 합치되 Set으로 중복 제거 (username 기준)
        final Set<String> seenUsernames = {};
        next = <_RecipientOption>[];

        // 로컬 결과 먼저 추가
        for (final item in localResults) {
          if (!seenUsernames.contains(item.username)) {
            seenUsernames.add(item.username);
            next.add(item);
          }
        }

        // 서버 결과 추가 (중복 제거)
        for (final item in serverResults) {
          if (!seenUsernames.contains(item.username)) {
            seenUsernames.add(item.username);
            next.add(item);
          }
        }
      }

      if (mounted) {
        setState(() {
          _filteredRecipients = next;
          _loading = false;
        });

        // 검색어가 비워지면 슬라이드 애니메이션 다시 시작
        if (qq.isEmpty &&
            _filteredRecipients.isNotEmpty &&
            !_hasAnimatedFriendList) {
          _slideController.reset();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _slideController.forward();
              _hasAnimatedFriendList = true;
            }
          });
        }
      }
    });
  }

  void _toggleSelect(_RecipientOption recipient) {
    setState(() {
      // ✅ "모든 친구"를 선택하면 기존 선택 모두 취소하고 "모든 친구"만 추가
      if (recipient.isAllFriends) {
        final isAlreadySelected = _selected.any((s) => s.isAllFriends);
        if (isAlreadySelected) {
          // 이미 선택되어 있으면 해제
          _selected.removeWhere((s) => s.isAllFriends);
        } else {
          // 선택: 기존 선택 모두 제거하고 "모든 친구"만 추가
          _selected.clear();
          _selected.add(recipient);
        }
      } else {
        // 일반 항목 선택
        final idx = _selected.indexWhere(
          (s) => s.username == recipient.username,
        );
        if (idx >= 0) {
          // 선택 해제
          _selected.removeAt(idx);
        } else {
          // 선택 추가: "모든 친구"가 선택되어 있으면 제거
          _selected.removeWhere((s) => s.isAllFriends);
          _selected.add(recipient);
        }
      }
    });
  }

  void _submit() {
    if (_selected.isEmpty) return;

    // ✅ returnResult가 true이면 결과를 반환하고 화면 닫기
    if (widget.returnResult) {
      // ✅ 전체 친구 정보를 Map 형태로 반환
      final selectedRecipients =
          _selected
              .map(
                (r) => {
                  'username': r.username,
                  'alias': r.alias ?? r.username,
                  'imageUrl': r.imageUrl,
                },
              )
              .toList();
      Navigator.of(context).pop(selectedRecipients);
      return;
    }

    // ✅ 에디터 화면으로 pushReplacement (기존 동작)
    _navigateToEditor();
  }
}

class _RecipientOption {
  final String username;
  final String? alias;
  final String? imageUrl;
  final bool isAllFriends;
  final bool isPartner; // ✅ 여친 여부

  const _RecipientOption({
    required this.username,
    this.alias,
    this.imageUrl,
    required this.isAllFriends,
    required this.isPartner,
  });
}

class _CircleUser extends StatelessWidget {
  final _RecipientOption user;
  final bool selected;
  final VoidCallback onTap;

  const _CircleUser({
    super.key,
    required this.user,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Theme.of(context).colorScheme.brightness == Brightness.dark;
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
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isDarkMode
                            ? AppColors.darkBackground
                            : AppColors.lightSurfaceVariant,
                    border: Border.all(
                      color:
                          selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child:
                      user.isAllFriends
                          ? Center(
                            child: Text(
                              'A',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          : CommonProfileAvatar(
                            username: user.username,
                            size: 100,
                            borderWidth: 1,
                            borderColor:
                                selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                            imageUrl: user.imageUrl,
                          ),
                ),
              ),
              // ✅ 여친 하트 표시
              if (user.isPartner && !user.isAllFriends)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 24,
                    height: 24,

                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 14,
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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSelectedRowChip extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedSelectedRowChip({required this.index, required this.child});

  @override
  State<_AnimatedSelectedRowChip> createState() =>
      _AnimatedSelectedRowChipState();
}

class _AnimatedSelectedRowChipState extends State<_AnimatedSelectedRowChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final delay = widget.index * 30;
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(delay / 300, 1.0, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.2, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(delay / 300, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

class _SelectedRowChip extends StatelessWidget {
  final String label;
  final String username; // ✅ Hero tag용
  final String? imageUrl; // ✅ 프로필 이미지
  final bool isPartner; // ✅ 여친 여부
  final VoidCallback onRemove;

  const _SelectedRowChip({
    required this.label,
    required this.username,
    this.imageUrl,
    required this.isPartner,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // ✅ 프로필 이미지
          CommonProfileAvatar(
            username: username,
            size: 48,
            borderWidth: 0,
            imageUrl: imageUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (isPartner)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.red,
                      size: 12,
                    ),
                  ),
              ],
            ),
          ),

          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0, right: 8.0),
              child: Text(
                '취소',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
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
      begin: 0.4,
      end: 0.8,
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
                color: Colors.white.withOpacity(
                  0.15 + (_animation.value * 0.15),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(
                  0.15 + (_animation.value * 0.15),
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
