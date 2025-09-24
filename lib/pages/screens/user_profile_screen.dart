import 'package:doppy/pages/user/setting_screen.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:doppy/data/services/blog_service.dart';
import 'package:doppy/pages/screens/post_reader_screen.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/profile_feed_provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/theme/app_text_styles.dart';
import 'package:doppy/editor/image/profile_image_bottom_sheet.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:doppy/pages/screens/manage_neighbor_screen.dart';
import 'package:doppy/pages/screens/manage_group_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final User? otherUser; // 다른 사용자 프로필을 볼 때 username 전달

  const UserProfileScreen({super.key, this.otherUser});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  // 피드 보기 모드 상태 (true: 카드형, false: 리스트형)
  bool isCardView = true;
  // 패널 위치/측정
  final GlobalKey _headerKey = GlobalKey();
  double _panelTop = 0.0; // 현재 패널 top(px)
  double _headerHeight = 0.0; // 헤더(프로필+버튼) 전체 높이(px)
  late final AnimationController _panelAnimCtrl;
  Animation<double>? _panelAnim;

  // ✅ 프로필 구분 상태는 그대로 유지
  late final bool _isOwnProfile;

  // 업로드 진행 상태
  UploadTask? _profileUploadTask;
  VoidCallback? _profileTaskListener;

  @override
  void initState() {
    super.initState();
    _isOwnProfile = (widget.otherUser == null);
    _panelAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    // ✅ [구조 개선] Provider를 통해 필요한 데이터를 한번에 요청합니다.
    // 이 코드 하나로 모든 데이터 로딩이 시작됩니다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      //final userProvider = context.read<UserProvider>();
      if (_isOwnProfile) {
        // 내 프로필에 필요한 데이터 로딩
        //userProvider.fetchMyProfile();
      } else {
        // 다른 사용자 프로필: 서버에서 상세 정보 & 친구 상태 병렬 로딩
        // userProvider.fetchUserProfile(widget.username!);
        context.read<FriendProvider>().checkFriendStatus(
          widget.otherUser!.username,
        );
      }
      // 헤더 측정 이후 초기 패널 위치 설정
      _scheduleMeasureHeader();
      // 프로필 피드 초기 로드
      try {
        await context.read<ProfileFeedProvider>().loadInitial();
      } catch (_) {}
    });
  }

  void _animatePanelTo(double target) {
    final double begin = _panelTop;
    if ((begin - target).abs() < 0.5) return;
    _panelAnim = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: _panelAnimCtrl, curve: Curves.easeOutCubic),
    )..addListener(() {
      if (!mounted) return;
      setState(() {
        _panelTop = _panelAnim!.value;
      });
    });
    _panelAnimCtrl
      ..reset()
      ..forward();
  }

  Widget _fallbackAvatar(ThemeData theme) => Container(
    color: theme.colorScheme.surfaceVariant,
    child: const Icon(Icons.person, color: Colors.white, size: 60),
  );

  Widget _avatarWithUploadIndicator({
    required double size,
    required String? imageUrl,
    required bool uploading,
  }) {
    final theme = Theme.of(context);
    const double borderThickness = 3.0;
    return Container(
      width: size + borderThickness * 2,
      height: size + borderThickness * 2,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 항상 동일 두께의 투명 보더로 레이아웃 고정
          Container(
            width: size + borderThickness * 2,
            height: size + borderThickness * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.transparent,
                width: borderThickness,
              ),
            ),
          ),
          Container(
            width: size,
            height: size,
            decoration: ShapeDecoration(
              color: theme.colorScheme.surfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(300),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(400),
              child:
                  (imageUrl?.isNotEmpty ?? false)
                      ? Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallbackAvatar(theme),
                      )
                      : _fallbackAvatar(theme),
            ),
          ),
          if (uploading)
            SizedBox(
              width: size + borderThickness * 2,
              height: size + borderThickness * 2,
              child: CircularProgressIndicator(
                strokeWidth: borderThickness,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _panelAnimCtrl.dispose();
    if (_profileUploadTask != null && _profileTaskListener != null) {
      _profileUploadTask!.removeListener(_profileTaskListener!);
    }
    super.dispose();
  }

  void _startProfileUpload(File file) {
    final upload = context.read<UploadService>();
    final task = upload.enqueueFile(file, kind: UploadKind.profile);
    _profileUploadTask = task;
    _profileTaskListener = () async {
      if (!mounted) return;
      setState(() {});
      if (task.state == UploadState.success) {
        try {
          final imageUrl = task.url ?? '';
          if (imageUrl.isNotEmpty) {
            await context.read<UserProvider>().updateProfileImage(
              imageUrl: imageUrl,
            );
          } else {
            await context.read<UserProvider>().fetchMyProfile();
          }
        } catch (_) {}
        if (_profileTaskListener != null) {
          task.removeListener(_profileTaskListener!);
          _profileTaskListener = null;
        }
        _profileUploadTask = null;
        if (mounted) setState(() {});
      }
      if (task.state == UploadState.failed ||
          task.state == UploadState.cancelled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('프로필 업로드 실패'),
              backgroundColor: Colors.red,
            ),
          );
        }
        if (_profileTaskListener != null) {
          task.removeListener(_profileTaskListener!);
          _profileTaskListener = null;
        }
        _profileUploadTask = null;
        if (mounted) setState(() {});
      }
    };
    task.addListener(_profileTaskListener!);
    setState(() {});
  }

  void _scheduleMeasureHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _headerKey.currentContext;
      if (ctx != null) {
        final size = ctx.size;
        if (size != null) {
          final double h = size.height;
          if ((_headerHeight - h).abs() > 0.5) {
            setState(() {
              _headerHeight = h;
              if (_panelTop == 0.0) {
                // 초기 진입 시 핸들이 헤더(이웃요청/관리 버튼) 하단에 위치하도록 설정
                _panelTop = _headerHeight;
              }
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Provider 상태
    final userProvider = context.watch<UserProvider>();
    final friendProvider = context.watch<FriendProvider>();

    final bool isOther = !_isOwnProfile; // true: 타인 프로필, false: 내 프로필
    final User? me = userProvider.currentUser;
    final String? myIntro = userProvider.selfIntroduction;
    final int? myFriendCount = userProvider.friendCount;
    final User? other = widget.otherUser;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 모바일 기준으로 최대 너비 제한 (오버플로우 방지)
    final maxWidth = screenWidth > 500 ? 500.0 : screenWidth;
    final containerWidth = maxWidth - 8.0; // 오버플로우 방지를 위해 8px 여백 추가
    final containerHeight = screenHeight;

    // 헤더 높이를 아직 모르면 측정 예약
    if (_headerHeight <= 0) _scheduleMeasureHeader();

    // 패널 높이를 동적으로 계산: 패널 top부터 하단 네비게이션 바 바로 위까지
    final double bottomNavHeight = containerHeight * 0.01;
    final double bottomMargin = -5.0; // 하단 네비게이션 바와의 적절한 여백
    final double dynamicPanelHeight =
        containerHeight - _panelTop - bottomNavHeight - bottomMargin;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          isOther ? "@${other?.username ?? ''}" : "@${me?.username ?? ''}",
          style: AppTextStyles.headlineLarge.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onBackground,
          ),
        ),
        centerTitle: false,
        leading:
            isOther
                ? GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                )
                : null,

        actions: [
          if (_isOwnProfile)
            IconButton(
              icon: Icon(
                Icons.menu,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        top: true,
        child: Center(
          child: Container(
            width: containerWidth,
            height: containerHeight,
            margin: EdgeInsets.symmetric(horizontal: 4.0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child:
                      isOther
                          ? _buildHeaderSectionOther(
                            containerWidth,
                            other,
                            friendProvider,
                          )
                          : _buildHeaderSectionMine(
                            containerWidth,
                            me,
                            myIntro,
                            myFriendCount,
                          ),
                ),
                _buildFeedPanel(containerWidth, _panelTop, dynamicPanelHeight),
              ],
            ),
          ),
        ),
      ),
      // 하단 네비게이션은 RootShell에서 고정 제공
    );
  }

  Widget _buildHeaderSectionOther(
    double containerWidth,
    User? other,
    FriendProvider friendProvider,
  ) {
    final theme = Theme.of(context);
    if (other == null) return const SizedBox.shrink();
    return Container(
      key: _headerKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Container(
            width: containerWidth,
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatarWithUploadIndicator(
                  size: 132,
                  imageUrl: other.profileImageUrl,
                  uploading: false,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        other.alias ?? '',
                        style: AppTextStyles.headlineLarge.copyWith(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onBackground,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '이웃 ${other.friendCount ?? 0}명',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        other.selfIntroduction ?? '자기소개가 없습니다.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '함께 도피하는 친구 13명',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      friendProvider.friendStatus == FriendRequestStatus.none
                          ? Expanded(
                            child: _buildFilledActionButton(
                              label: '이웃 요청하기',
                              onTap: () async {
                                final ok = await context
                                    .read<FriendProvider>()
                                    .sendFriendRequest(other.username);
                                if (!mounted) return;
                                if (!ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('이웃 요청을 보낼 수 없습니다'),
                                      backgroundColor: Colors.red,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  );
                                }
                              },
                              isEnabled: !friendProvider.isLoadingStatus,
                            ),
                          )
                          : Expanded(
                            child: _buildFilledActionButton(
                              label: '이웃 요청됨',
                              onTap: () {},
                              isEnabled: false,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSectionMine(
    double containerWidth,
    User? me,
    String? selfIntroduction,
    int? friendCount,
  ) {
    final theme = Theme.of(context);
    return Container(
      key: _headerKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Container(
            width: containerWidth,
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () async {
                    await showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      barrierColor: Colors.black54,
                      isScrollControlled: true,
                      builder:
                          (_) => ProfileImageBottomSheet(
                            onClearProfileImage: () async {
                              await context
                                  .read<UserProvider>()
                                  .updateProfileImage(imageUrl: '');
                            },
                            onImagesSelected: (files) async {
                              if (files.isEmpty) return;
                              _startProfileUpload(files.first);
                            },
                          ),
                    );
                  },
                  child: _avatarWithUploadIndicator(
                    size: 132,
                    imageUrl: me?.profileImageUrl,
                    uploading:
                        _profileUploadTask?.state == UploadState.uploading,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        me?.alias ?? '',
                        style: AppTextStyles.headlineLarge.copyWith(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onBackground,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '이웃 ${friendCount ?? 0}명',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        selfIntroduction ?? '자기소개가 없습니다.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildFilledActionButton(
                      label: '내 이웃',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ManageNeighborScreen(),
                          ),
                        );
                      },
                      isEnabled: false,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                  ),

                  Expanded(
                    child: _buildFilledActionButton(
                      label: '내 그룹',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ManageGroupScreen(),
                          ),
                        );
                      },
                      isEnabled: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilledActionButton({
    required String label,
    required VoidCallback onTap,
    required bool isEnabled,

    bool loading = false,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        label: Text(
          label,
          style: AppTextStyles.bodyLarge.copyWith(
            color: isEnabled ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceVariant,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: !loading ? onTap : null,
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
          color: Theme.of(context).colorScheme.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
        ),
        child: Column(
          children: [
            SizedBox(height: 16),
            // 상단 핸들/토글 영역에서만 드래그 제스처 처리
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) {
                if (_panelAnimCtrl.isAnimating) {
                  _panelAnimCtrl.stop();
                }
              },
              onVerticalDragUpdate: (details) {
                final double next = (_panelTop + details.delta.dy).clamp(
                  0.0,
                  _headerHeight,
                );
                if (next != _panelTop) {
                  setState(() => _panelTop = next);
                }
              },
              onVerticalDragEnd: (details) {
                final double velocity =
                    details.primaryVelocity ?? 0.0; // +down, -up
                const double snapThreshold = 0.5;
                const double flingVelocity = 600.0; // px/s

                double target;
                if (velocity < -flingVelocity) {
                  target = 0.0;
                } else if (velocity > flingVelocity) {
                  target = _headerHeight;
                } else {
                  final double ratio = (_panelTop /
                          (_headerHeight == 0 ? 1 : _headerHeight))
                      .clamp(0.0, 1.0);
                  target = (ratio < snapThreshold) ? 0.0 : _headerHeight;
                }

                _animatePanelTo(target);
              },
              child: Column(
                children: [
                  // 핸들 바
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(height: 16),
                  // shape1/2 아이콘 행
                  Padding(
                    padding: EdgeInsets.only(left: 20, right: 20, bottom: 12),
                    child: Row(
                      children: [
                        _buildShapeIcon(
                          'assets/icons/card.svg',
                          20.0,
                          20.0,
                          true,
                        ),
                        SizedBox(width: 12.0),
                        _buildShapeIcon(
                          'assets/icons/list.svg',
                          20.0,
                          20.0,
                          false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 피드 컨텐츠 (Provider 기반) — 제스처 영향에서 분리
            Expanded(
              child: Consumer<ProfileFeedProvider>(
                builder: (context, feed, _) {
                  if (feed.isLoading && feed.posts.isEmpty) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final posts = feed.posts;
                  return NotificationListener<ScrollNotification>(
                    onNotification: (sn) {
                      if (sn.metrics.pixels >=
                              sn.metrics.maxScrollExtent - 300 &&
                          feed.hasMore &&
                          !feed.isLoadingMore) {
                        context.read<ProfileFeedProvider>().loadMore();
                      }
                      return false;
                    },
                    child:
                        isCardView
                            ? _buildFeedImagesFromProvider(
                              containerWidth,
                              posts,
                            )
                            : _buildFeedListFromProvider(containerWidth, posts),
                  );
                },
              ),
            ),
          ],
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
                        ? Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7)
                        : Theme.of(context).colorScheme.secondary,
                    BlendMode.srcIn,
                  ),
                );
              } else {
                return Icon(
                  Icons.grid_view,
                  size: width,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  // legacy (sample) grid renderer - replaced by provider-backed version
  // kept temporarily for reference; not used

  Widget _buildFeedImagesFromProvider(
    double containerWidth,
    List<Map<String, dynamic>> posts,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        padding: const EdgeInsets.only(bottom: 200),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 9 / 13,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemCount: posts.length,
        physics: const AlwaysScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final post = posts[index];
          final thumb = (post['thumbnailImageUrl'] ?? '').toString();
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(2),
              splashColor: Colors.grey.withOpacity(0.6),
              highlightColor: Colors.grey.withOpacity(0.3),
              onTap: () async {
                final String postId = (post['id'] ?? '').toString();
                final String username = (post['username'] ?? '').toString();
                final me = context.read<UserProvider>().currentUser;
                final bool isMine = me != null && me.username == username;

                // 상세 데이터 필요 시 서버에서 재조회
                Map<String, dynamic> exported = post;
                try {
                  if ((post['content'] == null ||
                          post['content'].toString().isEmpty) &&
                      postId.isNotEmpty) {
                    exported = await BlogService().getPostDetail(postId);
                  }
                } catch (_) {}

                if (!mounted) return;
                if (isMine) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => PostwriteScreen(
                            screenWidth: MediaQuery.of(context).size.width,
                            initialExported: exported,
                          ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => PostReaderScreen(
                            exported: exported,
                            heroTag: 'post_$postId',
                          ),
                    ),
                  );
                }
              },
              child: Container(
                decoration: ShapeDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: _buildThumb(thumb, index),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedListFromProvider(
    double containerWidth,
    List<Map<String, dynamic>> posts,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 200),
      itemCount: posts.length,
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final feed = posts[index];
        final String title = (feed['title'] ?? '').toString();
        final String content = (feed['content'] ?? '').toString();
        final String thumb = (feed['thumbnailImageUrl'] ?? '').toString();
        final int views =
            (feed['viewCount'] ?? 0) is int ? feed['viewCount'] as int : 0;
        final int likes =
            (feed['likeCount'] ?? 0) is int ? feed['likeCount'] as int : 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: AspectRatio(
                  aspectRatio: 9 / 13,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: InkWell(
                      onTap: () async {
                        final String postId = (feed['id'] ?? '').toString();
                        final String username =
                            (feed['username'] ?? '').toString();
                        final me = context.read<UserProvider>().currentUser;
                        final bool isMine =
                            me != null && me.username == username;

                        Map<String, dynamic> exported = feed;
                        try {
                          if ((feed['content'] == null ||
                                  feed['content'].toString().isEmpty) &&
                              postId.isNotEmpty) {
                            exported = await BlogService().getPostDetail(
                              postId,
                            );
                          }
                        } catch (_) {}

                        if (!mounted) return;
                        if (isMine) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => PostwriteScreen(
                                    screenWidth:
                                        MediaQuery.of(context).size.width,
                                    initialExported: exported,
                                  ),
                            ),
                          );
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => PostReaderScreen(
                                    exported: exported,
                                    heroTag: 'post_$postId',
                                  ),
                            ),
                          );
                        }
                      },
                      child: _buildThumb(thumb, index),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: onVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.remove_red_eye_outlined,
                          size: 16,
                          color: onVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$views',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: onVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.favorite_border, size: 16, color: onVariant),
                        const SizedBox(width: 4),
                        Text(
                          '$likes',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: onVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThumb(String pathOrUrl, int index) {
    final isNetwork = pathOrUrl.startsWith('http');
    if (isNetwork) {
      return Image.network(
        pathOrUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbFallback(index),
      );
    } else if (pathOrUrl.isNotEmpty) {
      return Image.asset(
        pathOrUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbFallback(index),
      );
    }
    return _thumbFallback(index);
  }

  Widget _thumbFallback(int index) {
    return Container(
      color:
          index % 2 == 0
              ? Theme.of(context).colorScheme.secondary
              : Theme.of(context).colorScheme.primary,
      child: const Center(
        child: Icon(Icons.image, color: Colors.white, size: 40),
      ),
    );
  }
}
