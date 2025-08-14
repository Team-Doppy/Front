import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/components/profile_top_bar.dart';
import 'package:doppy/pages/components/post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../data/services/auth_service.dart';
import '../../data/models/user_model.dart';
import 'manage_group_screen.dart';
import 'manage_neighbor_screen.dart';
import '../../data/services/friend_service.dart';

// 친구 요청 상태를 나타내는 enum
enum FriendRequestStatus {
  none, // 친구 요청 안 함
  requested, // 친구 요청함, 수락 안 됨
  accepted, // 친구가 됨
}

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments; // 다른 사용자 프로필을 볼 때 전달되는 인자

  const UserProfileScreen({super.key, this.arguments});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  // 피드 보기 모드 상태 (true: 카드형, false: 리스트형)
  bool isCardView = true;

  // 인증 서비스 인스턴스
  final AuthService _authService = AuthService();

  // 친구 서비스 인스턴스
  final FriendService _friendService = FriendService();

  // 사용자 정보 관련 상태
  User? _profileUser;
  bool _isLoadingUser = true;
  int? _friendCount; // 친구 수 추가
  String? _selfIntroduction; // 자기소개 추가

  // 친구 상태 관련 상태
  bool _isLoadingFriendStatus = false;
  FriendRequestStatus _friendRequestStatus =
      FriendRequestStatus.none; // 친구 요청 상태

  // 프로필 구분 상태
  late final bool _isOwnProfile; // 내 프로필인지 다른 사용자 프로필인지 구분
  late final String? _targetUsername; // 다른 사용자 프로필을 볼 때의 username

  double? _handleTop; // 드래그 핸들의 현재 top 위치
  late double _minHandleTop; // 핸들이 올라갈 수 있는 최소 top
  late double _initialHandleTop; // 초기 핸들 위치 (아래쪽 한계)

  @override
  void initState() {
    super.initState();

    // arguments가 있으면 다른 사용자 프로필, 없으면 내 프로필
    if (widget.arguments != null) {
      _isOwnProfile = false;
      _targetUsername = widget.arguments!['username'] as String?;
    } else {
      _isOwnProfile = true;
      _targetUsername = null;
    }

    _loadProfileUser();

    // 다른 사용자 프로필인 경우 친구 상태도 확인
    if (!_isOwnProfile) {
      _checkFriendStatus();
    }
  }

  // 프로필 사용자 정보 로드
  Future<void> _loadProfileUser() async {
    try {
      setState(() {
        _isLoadingUser = true;
      });

      // 현재 로그인된 사용자의 토큰을 가져와서 사용자 정보 조회
      final token = await _authService.getToken();

      if (token != null) {
        if (_isOwnProfile) {
          // 내 프로필인 경우
          final String? profileUsername = await _authService.getUsername();

          if (profileUsername != null) {
            final userData = await _authService.getUserInfo(profileUsername);

            if (userData != null) {
              // API 응답에서 User 객체 생성
              final user = User(
                id: userData['id'],
                username: userData['username'],
                role: userData['role'],
                alias: userData['alias'],
              );

              // 친구 수도 함께 조회
              final friendCount = await _authService.getFriendCount();

              // 자기소개도 함께 조회
              final selfIntroduction = await _authService.getSelfIntroduction();

              setState(() {
                _profileUser = user;
                _friendCount = friendCount;
                _selfIntroduction = selfIntroduction;
                _isLoadingUser = false;
              });
            } else {
              setState(() {
                _isLoadingUser = false;
              });
            }
          } else {
            // 사용자명이 없으면 로그인되지 않은 상태
            setState(() {
              _isLoadingUser = false;
            });
            // TODO: 로그인 페이지로 이동하거나 에러 처리
          }
        } else {
          // 다른 사용자 프로필인 경우
          if (_targetUsername != null) {
            final userData = await _authService.getUserInfo(_targetUsername!);

            if (userData != null) {
              // API 응답에서 User 객체 생성
              final user = User(
                id: userData['id'],
                username: userData['username'],
                role: userData['role'],
                alias: userData['alias'],
              );

              // 다른 사용자의 경우에도 이웃 수와 자기소개를 조회해보기
              // (API가 공개 정보를 제공한다면 표시)
              int? otherUserFriendCount;
              String? otherUserSelfIntroduction;

              try {
                // 다른 사용자의 친구 수 조회 (공개 API가 있다면)
                // 현재는 같은 API를 사용하지만, 실제로는 별도의 공개 API가 필요할 수 있음
                otherUserFriendCount = await _authService.getFriendCount();

                // 다른 사용자의 자기소개 조회 (공개 API가 있다면)
                otherUserSelfIntroduction =
                    await _authService.getSelfIntroduction();
              } catch (e) {
                print('⚠️ [UserProfileScreen] 다른 사용자 정보 조회 실패: $e');
                // 실패해도 기본 정보는 표시
              }

              setState(() {
                _profileUser = user;
                _friendCount = otherUserFriendCount;
                _selfIntroduction = otherUserSelfIntroduction;
                _isLoadingUser = false;
              });
            } else {
              setState(() {
                _isLoadingUser = false;
              });
            }
          } else {
            setState(() {
              _isLoadingUser = false;
            });
          }
        }
      } else {
        // 토큰이 없으면 로그인되지 않은 상태
        setState(() {
          _isLoadingUser = false;
        });
        // TODO: 로그인 페이지로 이동하거나 에러 처리
      }
    } catch (e) {
      print('프로필 사용자 정보 로드 실패: $e');
      setState(() {
        _isLoadingUser = false;
      });
    }
  }

  // 친구 상태 확인 메서드
  Future<void> _checkFriendStatus() async {
    if (_isOwnProfile || _targetUsername == null) return;

    setState(() {
      _isLoadingFriendStatus = true;
    });

    try {
      // 1. 내가 보낸 친구 신청 목록 확인
      final sentRequests = await _authService.getSentFriendRequests();
      final hasSentRequest = sentRequests.any(
        (request) =>
            request['targetUsername'] == _targetUsername ||
            request['username'] == _targetUsername,
      );

      if (hasSentRequest) {
        // 2. 친구 요청을 보냈다면, 수락된 친구 목록 확인
        final acceptedFriends = await _authService.getAcceptedFriends();
        final isAccepted = acceptedFriends.any(
          (friend) =>
              friend['username'] == _targetUsername ||
              friend['targetUsername'] == _targetUsername,
        );

        setState(() {
          _friendRequestStatus =
              isAccepted
                  ? FriendRequestStatus.accepted
                  : FriendRequestStatus.requested;
          _isLoadingFriendStatus = false;
        });
      } else {
        setState(() {
          _friendRequestStatus = FriendRequestStatus.none;
          _isLoadingFriendStatus = false;
        });
      }
    } catch (e) {
      print('❌ [UserProfileScreen] 친구 상태 확인 실패: $e');
      setState(() {
        _friendRequestStatus = FriendRequestStatus.none;
        _isLoadingFriendStatus = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 모바일 기준으로 최대 너비 제한 (오버플로우 방지)
    final maxWidth = screenWidth > 500 ? 500.0 : screenWidth;
    final containerWidth = maxWidth - 8.0; // 오버플로우 방지를 위해 8px 여백 추가
    final containerHeight = screenHeight;

    // 초기 위치 계산 (첫 빌드 시 한 번만)
    if (_handleTop == null) {
      _initialHandleTop = containerHeight * 0.320; // 이웃관리 바로 아래로 더 가깝게 위치
      _handleTop = _initialHandleTop;
      _minHandleTop = -20.0; // top bar를 완전히 덮을 수 있도록 더 위로 올라가도록
    }

    // 핸들 위치에 따라 패널 top을 선형 매핑
    final double targetPanelTop = 10.0; // 상단까지 완전히 올라가서 뒤로가기까지 가리도록
    final double initialPanelTop = containerHeight * 0.32; // 패널 초기 위치를 위로 조정
    final double a =
        (initialPanelTop - targetPanelTop) /
        (_initialHandleTop - _minHandleTop);
    final double b = initialPanelTop - a * _initialHandleTop;
    final double panelTop = a * _handleTop! + b;

    // 패널 높이를 동적으로 계산: 패널 top부터 하단 네비게이션 바 바로 위까지
    final double bottomNavHeight = containerHeight * 0.076;
    final double bottomMargin = -5.0; // 하단 네비게이션 바와의 적절한 여백
    final double dynamicPanelHeight =
        containerHeight - panelTop - bottomNavHeight - bottomMargin;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Container(
            width: containerWidth,
            height: containerHeight,
            margin: EdgeInsets.symmetric(horizontal: 4.0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.lightBackground),
            child: _buildContent(
              containerWidth,
              containerHeight,
              panelTop,
              dynamicPanelHeight,
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: 3,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildContent(
    double containerWidth,
    double containerHeight,
    double panelTop,
    double dynamicPanelHeight,
  ) {
    return Stack(
      children: [
        // 배경
        _buildBackground(containerWidth, containerHeight),

        // 프로필 요소들
        ..._buildProfileElements(containerWidth, containerHeight),
        // 하단 네비게이션 바
        //        _buildBottomNavigation(containerWidth, containerHeight),
        // 상단 탑바 (피드 패널 아래에 위치)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DoppyTopBar(
            title: _isLoadingUser
                    ? '로딩 중...'
                    : _profileUser != null
                    ? '@${_profileUser!.username}'
                    : '사용자', // 사용자 아이디 표시
            showBack: !_isOwnProfile, // 다른 사용자 프로필일 때만 뒤로가기 버튼 표시
            onBack: _isOwnProfile ? null : () => Navigator.pop(context),
            onMore: () {
              // 더보기 메뉴 로직 (필요시 구현)
            },
          ),
        ),

        // 피드 패널 (최상위 - top bar를 덮을 수 있도록)
        _buildFeedPanel(containerWidth, panelTop, dynamicPanelHeight),
      ],
    );
  }

  Widget _buildBackground(double containerWidth, double containerHeight) {
    return Positioned(
      left: 0,
      top: 0,
      child: Container(
        width: containerWidth,
        height: containerHeight * 0.4,
        decoration: BoxDecoration(color: AppColors.lightSurface),
      ),
    );
  }

  List<Widget> _buildProfileElements(
    double containerWidth,
    double containerHeight,
  ) {
    List<Widget> elements = [
      // 프로필 이미지 컨테이너
      Positioned(
        left: containerWidth * 0.06,
        top: containerHeight * 0.07, // 위로 올림
        child: Container(
          width: 132, // 고정 크기 132
          height: 132, // 고정 크기 132
          decoration: ShapeDecoration(
            color: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40), // 132/2 = 66
            ),
          ),
        ),
      ),
    ];

    // 이웃관리, 그룹관리 버튼 표시 (내 프로필일 때만 표시)
    if (_isOwnProfile) {
      elements.addAll([
        // 그룹관리 버튼
        Positioned(
          left: containerWidth * 0.517,
          top: containerHeight * 0.25,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ManageGroupScreen(),
                  ),
                );
              }, // 그룹관리 페이지 이동
              child: Container(
                width: containerWidth * 0.453,
                height: containerHeight * 0.046,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: AppColors.lightBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Center(
                  child: Text(
                    '그룹관리',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.lightTextSecondary,
                    ), // 강조 본문 - 메뉴, 중요 본문
                  ),
                ),
              ),
            ),
          ),
        ),
        // 이웃관리 버튼
        Positioned(
          left: containerWidth * 0.047,
          top: containerHeight * 0.25,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ManageNeighborScreen(),
                  ),
                );
              }, // 이웃관리 페이지 이동
              child: Container(
                width: containerWidth * 0.453,
                height: containerHeight * 0.046,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: AppColors.lightSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Center(
                  child: Text(
                    '이웃관리',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w500,
                    ), // 강조 본문 - 메뉴, 중요 본문
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    }

    // 사용자 정보들 추가
    elements.addAll(_buildUserInfoTexts(containerWidth, containerHeight));

    // 다른 사용자 프로필인 경우 이웃 요청하기 버튼과 함께 Doppy하는 이웃 수 추가
    if (!_isOwnProfile) {
      elements.addAll(_buildOtherUserElements(containerWidth, containerHeight));
    }

    return elements;
  }

  List<Widget> _buildUserInfoTexts(
    double containerWidth,
    double containerHeight,
  ) {
    return [
      // 사용자 이름
      Positioned(
        left: containerWidth * 0.475,
        top: containerHeight * 0.09, // 위로 올림
        child: _isLoadingUser
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(
                  _profileUser != null &&
                          _profileUser!.alias != null &&
                          _profileUser!.alias!.isNotEmpty
                      ? _profileUser!.alias!
                      : _profileUser != null
                      ? _profileUser!.username
                      : '사용자',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.lightTextPrimary,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ), // 대형 제목 - 사용자 이름, 메인 제목
                ),
      ),
      // 사용자 설명 (모든 프로필에서 표시)
      Positioned(
        left: containerWidth * 0.475,
        top: containerHeight * 0.16, // 위로 올림
        child: _isLoadingUser
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(
                  _selfIntroduction != null && _selfIntroduction!.isNotEmpty
                      ? _selfIntroduction!
                      : '자기소개가 없습니다.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.lightTextSecondary,
                  ), // 작은 본문 - 사용자 ID, 소개글
                ),
      ),
      // 이웃 수 (모든 프로필에서 표시)
      Positioned(
        left: containerWidth * 0.483,
        top: containerHeight * 0.13, // 위로 올림
        child: _isLoadingUser
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Text(
                  _friendCount != null ? '이웃 ${_friendCount}명' : '이웃 0명',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.lightTextPrimary,
                  ), // 강조 본문 - 메뉴, 중요 본문
                ),
      ),
    ];
  }

  // 다른 사용자 프로필 전용 요소들 (이웃 요청하기 버튼, 함께 Doppy하는 이웃 수)
  List<Widget> _buildOtherUserElements(
    double containerWidth,
    double containerHeight,
  ) {
    return [
      // 함께 Doppy하는 이웃 수 (이웃 요청하기 버튼 바로 위에 위치)
      Positioned(
        left: containerWidth * 0.047, // 이웃 요청하기 버튼과 같은 left 위치
        top: containerHeight * 0.22, // 이웃 요청하기 버튼 바로 위에 위치 (0.25 - 0.02)
        child: Text(
          '함께 Doppy하는 이웃 15명', // 하드코딩된 숫자
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.lightTextSecondary,
          ),
        ),
      ),

      // 이웃 요청하기 버튼 (친구 상태에 따라 다르게 표시)
      if (_friendRequestStatus != FriendRequestStatus.accepted)
        Positioned(
          left: containerWidth * 0.047,
          top: containerHeight * 0.25, // 함께 Doppy하는 이웃 수 아래에 위치
          child: Container(
            width: containerWidth * 0.906, // 전체 너비의 90.6%
            height: containerHeight * 0.046,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                splashColor: Colors.grey.withOpacity(0.6),
                highlightColor: Colors.grey.withOpacity(0.3),
                onTap:
                    _friendRequestStatus == FriendRequestStatus.none
                        ? _sendFriendRequest
                        : null, // 이미 요청한 경우 클릭 불가
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        _friendRequestStatus == FriendRequestStatus.none
                            ? AppColors
                                .primary // 보라색 배경
                            : AppColors.lightSurfaceVariant, // 회색 배경
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child:
                        _isLoadingFriendStatus
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Text(
                              _friendRequestStatus == FriendRequestStatus.none
                                  ? '이웃 요청하기'
                                  : '이웃 요청함',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color:
                                    _friendRequestStatus ==
                                            FriendRequestStatus.none
                                        ? Colors.white
                                        : AppColors.lightTextSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  // 친구 요청 보내기 메서드
  Future<void> _sendFriendRequest() async {
    if (_targetUsername == null) return;

    try {
      // FriendService를 사용하여 친구 요청 보내기
      await _friendService.sendFriendRequest(_targetUsername!);

      // 친구 요청 성공 시 상태 업데이트
      setState(() {
        _friendRequestStatus = FriendRequestStatus.requested;
      });

      // 성공 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이웃 요청이 완료되었습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('❌ [UserProfileScreen] 친구 요청 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이웃 요청 중 오류가 발생했습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildNavIcon(
    String assetPath,
    IconData fallbackIcon,
    double containerWidth,
    double containerHeight,
  ) {
    return Container(
      width: containerWidth * 0.2,
      height: containerHeight * 0.065, // 네비게이션 바 높이에 맞춤
      padding: EdgeInsets.zero, // 패딩 제거
      child: Center(
        child: Image.asset(
          assetPath,
          width: 24,
          height: 24,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              fallbackIcon,
              size: 24,
              color: AppColors.lightTextSecondary,
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeedPanel(
    double containerWidth,
    double panelTop,
    double dynamicPanelHeight,
  ) {
    return Positioned(
      left: 0,
      top: panelTop,
      child: Container(
        width: containerWidth,
        height: dynamicPanelHeight,
        decoration: ShapeDecoration(
          color: AppColors.lightBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (details) {
            final double nextTop = (_handleTop! + details.delta.dy).clamp(
              _minHandleTop,
              _initialHandleTop,
            );
            if (nextTop != _handleTop) {
              setState(() {
                _handleTop = nextTop;
              });
            }
          },
          onVerticalDragEnd: (details) {
            // 현재 위치에서 최대 높이까지의 거리의 중간점 계산
            final double totalDistance = _initialHandleTop - _minHandleTop;
            final double currentDistance = _initialHandleTop - _handleTop!;
            final double threshold = totalDistance * 0.5; // 50% 지점

            // 50% 이상 드래그했으면 최대 높이로, 미만이면 원래 위치로
            final double targetTop =
                currentDistance >= threshold
                    ? _minHandleTop
                    : _initialHandleTop;

            setState(() {
              _handleTop = targetTop;
            });
          },
          child: Column(
            children: [
              SizedBox(height: 16),
              // 핸들 바
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 16),
              // shape1/2 아이콘 행
              Padding(
                padding: EdgeInsets.only(left: 20, right: 20, bottom: 12),
                child: Row(
                  children: [
                    _buildShapeIcon('assets/icons/card.svg', 20.0, 20.0, true),
                    SizedBox(width: 12.0),
                    _buildShapeIcon('assets/icons/list.svg', 20.0, 20.0, false),
                  ],
                ),
              ),
              // 피드 컨텐츠
              Expanded(
                child:
                    isCardView
                        ? _buildFeedImages(containerWidth, dynamicPanelHeight)
                        : _buildFeedList(containerWidth, dynamicPanelHeight),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShapeIcon(
    String assetPath,
    double width,
    double height,
    bool isCard,
  ) {
    final bool isSelected = isCard ? isCardView : !isCardView;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.5),
        splashColor: Colors.grey.withOpacity(0.6),
        highlightColor: Colors.grey.withOpacity(0.3),
        onTap: () {
          setState(() {
            isCardView = isCard;
          });
        },
        child: Container(
          padding: EdgeInsets.all(4),
          child: FutureBuilder<String>(
            future: DefaultAssetBundle.of(context).loadString(assetPath),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return SvgPicture.string(
                  snapshot.data!,
                  width: width,
                  height: height,
                  colorFilter: ColorFilter.mode(
                    isSelected
                        ? AppColors.lightTextSecondary
                        : AppColors.accent,
                    BlendMode.srcIn,
                  ),
                );
              } else {
                return Icon(
                  Icons.grid_view,
                  size: width,
                  color: AppColors.lightTextSecondary,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFeedImages(double containerWidth, double panelHeight) {
    final List<String> feedImages = [
      'assets/images/feed1.jpg',
      'assets/images/feed4.png',
      'assets/images/feed3.png',
      'assets/images/feed2.png',
      'assets/images/feed5.jpg',
      'assets/images/feed6.jpg',
      'assets/images/feed1.jpg',
      'assets/images/feed3.png',
      'assets/images/feed2.png',
      'assets/images/feed4.png',
      'assets/images/feed5.jpg',
      'assets/images/feed6.jpg',
      'assets/images/feed1.jpg',
      'assets/images/feed2.png',
      'assets/images/feed3.png',
      'assets/images/feed4.png',
      'assets/images/feed5.jpg',
      'assets/images/feed6.jpg',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 180 / 135, // width / height 비율
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: feedImages.length,
        physics: const AlwaysScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(2),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () {}, // 피드 상세보기 페이지 이동
              child: Container(
                decoration: ShapeDecoration(
                  color: AppColors.lightSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image.asset(
                    feedImages[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color:
                            index % 2 == 0
                                ? AppColors.accent
                                : AppColors.primary,
                        child: const Center(
                          child: Icon(
                            Icons.image,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedList(double containerWidth, double panelHeight) {
    final List<Map<String, String>> feedData = [
      {
        'image': 'assets/images/feed1.jpg',
        'title': '모태솔로지만연애를해야할까///',
        'author': '수최영',
        'content':
            '안녕하세여,.오늘은 모태솔로지만연애는하고싶 어후기로돌아왓어요다들키스씬은보셧나요저는보다가기절을할뻔했어요 완전 찰스엔터됨 진짜 갈!!!!!!!!!!!!할뻔함 어쩌고 저쩌고 저ㅉ고어쩌고',
      },
      {
        'image': 'assets/images/feed2.png',
        'title': '오늘 날씨가 너무 좋아서 산책했어요',
        'author': '김여름',
        'content':
            '오늘 날씨가 정말 좋아서 산책을 다녀왔어요. 햇살이 따뜻하고 바람도 시원해서 정말 기분이 좋았어요. 특히 공원에서 만난 강아지들이 너무 귀여웠어요!',
      },
      {
        'image': 'assets/images/feed3.png',
        'title': '새로운 카페를 발견했어요!',
        'author': '박카페',
        'content':
            '새로운 카페를 발견했어요! 분위기도 좋고 커피도 맛있어서 정말 만족스러웠어요. 다음에 친구들과 함께 가보려고 해요.',
      },
      {
        'image': 'assets/images/feed4.png',
        'title': '블로그 1000억 무조건 부자될 것 같아',
        'author': '이블로그',
        'content':
            '블로그로 1000억 벌어서 부자가 될 것 같아요! 열심히 글 쓰고 있으니까 조만간 성공할 것 같아요. 다들 응원해주세요!',
      },
      {
        'image': 'assets/images/feed5.jpg',
        'title': '오늘은 수강신청을 망쳐버렸어요',
        'author': '정수강',
        'content':
            '오늘 수강신청을 망쳐버렸어요... 원하는 과목을 못 들었어요. 다음 학기에 다시 도전해보려고 해요. 화이팅!',
      },
    ];

    return ListView.builder(
      itemCount: feedData.length,
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final feed = feedData[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.grey.withOpacity(0.6),
            highlightColor: Colors.grey.withOpacity(0.3),
            onTap: () {
              // 피드 상세보기 페이지 이동
              // TODO: 피드 상세보기 페이지로 이동
            },
            child: PostCard(
              containerWidth: containerWidth,
              imagePath: feed['image']!,
              title: feed['title']!,
              author: feed['author']!,
              content: feed['content']!,
            ),
          ),
        );
      },
    );
  }
}
