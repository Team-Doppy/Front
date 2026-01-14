import 'package:flutter/material.dart';
import 'package:doppy/data/models/notification_model.dart';
import 'package:doppy/data/models/user_model.dart';
// Firestore 연동 시 사용
// import 'package:doppy/data/services/firestore_notification_service.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';

/// 알림 스크린
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  // Firestore 연동 시 사용
  // final FirestoreNotificationService _notificationService =
  //     FirestoreNotificationService();
  final ScrollController _scrollController = ScrollController();

  List<NotificationData> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<List<NotificationData>>? _subscription;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    try {
      // 하드코딩된 알림 데이터 (UI 완성까지)
      await Future.delayed(const Duration(milliseconds: 500));

      final now = DateTime.now();
      final hardcodedNotifications = [
        // Today
        NotificationData(
          documentId: '1',
          userId: 29,
          type: NotificationType.LIKE_CREATED,
          title: 'doppy_official님이 회원님의 포스트를 좋아합니다',
          body: null,
          read: false,
          createdAt: now.subtract(const Duration(minutes: 30)),
          likerId: 'doppy_official',
          likerUsername: 'doppy_official',
          postId: 'post_123',
        ),
        NotificationData(
          documentId: '2',
          userId: 29,
          type: NotificationType.POST_MENTION,
          title: 'hahah님이 회원님을 언급했습니다',
          body: null,
          read: false,
          createdAt: now.subtract(const Duration(hours: 2)),
          authorId: 'hahah',
          authorUsername: 'hahah',
          postId: 'post_456',
        ),
        NotificationData(
          documentId: '3',
          userId: 29,
          type: NotificationType.FRIEND_REQUEST,
          title: 'sojung05님이 친구 요청을 보냈습니다',
          body: null,
          read: false,
          createdAt: now.subtract(const Duration(hours: 5)),
          requesterId: 'sojung05',
          requesterUsername: 'sojung05',
        ),
        // This Week
        NotificationData(
          documentId: '4',
          userId: 29,
          type: NotificationType.POST_CREATED,
          title: 'doppy_tester님이 새 포스트를 작성했습니다',
          body: null,
          read: true,
          createdAt: now.subtract(const Duration(days: 1)),
          authorId: 'doppy_tester',
          authorUsername: 'doppy_tester',
          postId: 'post_789',
        ),
        NotificationData(
          documentId: '5',
          userId: 29,
          type: NotificationType.FRIEND_ACCEPTED,
          title: 'kang052011님이 친구 요청을 수락했습니다',
          body: null,
          read: true,
          createdAt: now.subtract(const Duration(days: 2)),
          accepterId: 'kang052011',
          accepterUsername: 'kang052011',
        ),
        NotificationData(
          documentId: '6',
          userId: 29,
          type: NotificationType.LIKE_CREATED,
          title: 'jsong1235님이 회원님의 포스트를 좋아합니다',
          body: null,
          read: true,
          createdAt: now.subtract(const Duration(days: 3)),
          likerId: 'jsong1235',
          likerUsername: 'jsong1235',
          postId: 'post_101',
        ),
        NotificationData(
          documentId: '7',
          userId: 29,
          type: NotificationType.CHAT_MENTION,
          title: 'homunoy님이 채팅에서 회원님을 언급했습니다',
          body: null,
          read: true,
          createdAt: now.subtract(const Duration(days: 4)),
          authorId: 'homunoy',
          authorUsername: 'homunoy',
        ),
      ];

      if (mounted) {
        setState(() {
          _notifications = hardcodedNotifications;
          _isLoading = false;
        });
      }

      // 기존 Firestore 구독 코드는 주석 처리
      /*
      final userId = await _notificationService.getCurrentUserId();

      if (userId == null) {
        debugPrint(
          '[NotificationScreen] _initializeNotifications: ❌ userId를 찾을 수 없습니다',
        );
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = '사용자 정보를 불러올 수 없습니다';
          });
        }
        return;
      }

      debugPrint(
        '[NotificationScreen] _initializeNotifications: ✅ userId 가져오기 성공: $userId (타입: ${userId.runtimeType})',
      );
      debugPrint(
        '[NotificationScreen] _initializeNotifications: Firestore 구독 시작',
      );

      // Firestore 실시간 구독 시작
      _subscription = _notificationService
          .subscribeNotifications(userId: userId, limit: 50)
          .listen(
            (notifications) {
              if (mounted) {
                setState(() {
                  _notifications = notifications;
                  _isLoading = false;
                });
              }
            },
            onError: (error) {
              debugPrint('[NotificationScreen] 알림 구독 오류: $error');
              if (mounted) {
                // 권한 오류인 경우 빈 리스트로 처리 (알림이 없거나 권한이 없을 수 있음)
                if (error.toString().contains('permission-denied')) {
                  debugPrint(
                    '[NotificationScreen] Firestore 권한 오류 - 빈 리스트로 처리',
                  );
                  setState(() {
                    _notifications = [];
                    _isLoading = false;
                  });
                } else {
                  setState(() {
                    _errorMessage = '알림을 불러오는데 실패했습니다';
                    _isLoading = false;
                  });
                }
              }
            },
          );
      */
    } catch (e) {
      debugPrint('[NotificationScreen] 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '알림을 불러오는데 실패했습니다';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _deleteNotification(String documentId) {
    setState(() {
      _notifications.removeWhere((n) => n.documentId == documentId);
    });
  }

  void _handleNotificationTap(NotificationData notification) {
    // 알림 타입에 따라 다른 화면으로 이동
    if (notification.relatedPostId != null) {
      // 포스트 관련 알림인 경우
      // TODO: 실제 포스트 데이터를 가져와서 PostReaderScreen으로 이동
      // 현재는 포스트 ID만 있으므로, 나중에 API가 연결되면 수정 필요
      if (mounted) {
        // 일단은 알림만 표시하고 나중에 구현
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('포스트 상세 화면으로 이동 (구현 예정)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else if (notification.relatedUserId != null) {
      // 사용자 관련 알림인 경우 프로필 화면으로 이동
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => UserProfileScreen(
                  otherUser: User(
                    username:
                        notification.relatedUsername ??
                        notification.relatedUserId!,
                    profileImageUrl: null, // Firestore 구조에 imageUrl이 없음
                  ),
                ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('notification_screen_title'),
              style: GoogleFonts.notoSansKr(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (_notifications.any((n) => !n.isRead)) ...[
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 79, 67),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_notifications.where((n) => !n.isRead).length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // 새로고침 시 구독을 재시작
          _subscription?.cancel();
          await _initializeNotifications();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _notifications.isEmpty) {
      return _buildShimmerLoading();
    }

    if (_errorMessage != null && _notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? context.tr('failed_to_load_notifications'),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('no_notifications'),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    // 날짜별로 그룹화 (동적)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 7));
    final monthStart = todayStart.subtract(const Duration(days: 30));

    // 오늘 알림
    final todayNotifications =
        _notifications.where((n) {
          return n.createdAt.isAfter(todayStart);
        }).toList();

    // 이번 주 알림 (오늘 제외)
    final weekNotifications =
        _notifications.where((n) {
          return n.createdAt.isAfter(weekStart) &&
              !n.createdAt.isAfter(todayStart);
        }).toList();

    // 이번 달 알림 (이번 주 제외)
    final monthNotifications =
        _notifications.where((n) {
          return n.createdAt.isAfter(monthStart) &&
              !n.createdAt.isAfter(weekStart);
        }).toList();

    // 그 이전 알림
    final earlierNotifications =
        _notifications.where((n) {
          return !n.createdAt.isAfter(monthStart);
        }).toList();

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (todayNotifications.isNotEmpty) ...[
          _buildSectionHeader(context.tr('today')),
          ...todayNotifications.map(
            (notification) => _buildNotificationItem(notification),
          ),
        ],
        if (weekNotifications.isNotEmpty) ...[
          _buildSectionHeader(context.tr('this_week')),
          ...weekNotifications.map(
            (notification) => _buildNotificationItem(notification),
          ),
        ],
        if (monthNotifications.isNotEmpty) ...[
          _buildSectionHeader(context.tr('this_month')),
          ...monthNotifications.map(
            (notification) => _buildNotificationItem(notification),
          ),
        ],
        if (earlierNotifications.isNotEmpty) ...[
          _buildSectionHeader(context.tr('earlier')),
          ...earlierNotifications.map(
            (notification) => _buildNotificationItem(notification),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: GoogleFonts.notoSansKr(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSectionHeader(context.tr('today')),
        ...List.generate(5, (index) => _buildShimmerNotificationCard(index)),
      ],
    );
  }

  Widget _buildShimmerNotificationCard(int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로필 아바타 쉬머
          Stack(
            clipBehavior: Clip.none,
            children: [
              ShimmerBox(width: 65, height: 65, shape: const CircleBorder()),
              // 좋아요 하트 쉬머 (일부에만 표시)
              if (index % 3 == 0)
                Positioned(
                  bottom: -2,
                  left: 28,
                  right: 0,
                  child: Center(
                    child: ShimmerBox(
                      width: 20,
                      height: 20,
                      shape: const CircleBorder(),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // 알림 내용 쉬머
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목 쉬머 (2줄)
                ShimmerBox(
                  width: double.infinity,
                  height: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                ShimmerBox(
                  width: 200,
                  height: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                // 타임스탬프 쉬머
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
  }

  Widget _buildNotificationItem(NotificationData notification) {
    return _DismissibleNotificationItem(
      notification: notification,
      onDismissed: () => _deleteNotification(notification.documentId),
      onTap: () => _handleNotificationTap(notification),
    );
  }
}

/// 스와이프 가능한 알림 아이템
class _DismissibleNotificationItem extends StatefulWidget {
  final NotificationData notification;
  final VoidCallback onDismissed;
  final VoidCallback onTap;

  const _DismissibleNotificationItem({
    required this.notification,
    required this.onDismissed,
    required this.onTap,
  });

  @override
  State<_DismissibleNotificationItem> createState() =>
      _DismissibleNotificationItemState();
}

class _DismissibleNotificationItemState
    extends State<_DismissibleNotificationItem> {
  double _swipeProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 스와이프 진행도를 곡선 함수로 변환 (초반에 빠르게 진해지도록)
    // sqrt를 사용하여 초반에 빠르게 변하고, 나중에는 천천히
    final curvedProgress =
        _swipeProgress < 0.0
            ? 0.0
            : (_swipeProgress * _swipeProgress * _swipeProgress); // 세제곱으로 더 빠르게

    // 스와이프 진행도에 따라 색상 진하기 조절 (0.0 ~ 1.0)
    // 초반에 빠르게 진해지도록 더 높은 계수 사용
    final opacity = (0.05 + curvedProgress * 0.5).clamp(0.05, 0.55);
    final gradientOpacity = (0.02 + curvedProgress * 0.3).clamp(0.02, 0.32);

    return Dismissible(
      key: Key(widget.notification.documentId),
      direction: DismissDirection.endToStart,
      onUpdate: (details) {
        // 스와이프 진행도 계산 (0.0 ~ 1.0)
        final progress = (details.progress).clamp(0.0, 1.0);
        setState(() {
          _swipeProgress = progress;
        });
      },
      onDismissed: (direction) {
        widget.onDismissed();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              theme.colorScheme.error.withOpacity(opacity),
              theme.colorScheme.error.withOpacity(gradientOpacity),
              Colors.transparent,
            ],
          ),
        ),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(shape: BoxShape.circle),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3.0),
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/delete.svg',
                width: 28,
                height: 28,
                colorFilter: ColorFilter.mode(
                  theme.colorScheme.error,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
      child: _NotificationTile(
        notification: widget.notification,
        onTap: widget.onTap,
      ),
    );
  }
}

/// 알림 타일 위젯
class _NotificationTile extends StatelessWidget {
  final NotificationData notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  IconData _getNotificationIcon() {
    switch (notification.type) {
      case NotificationType.POST_CREATED:
        return Icons.article_outlined;
      case NotificationType.POST_MENTION:
      case NotificationType.CHAT_MENTION:
        return Icons.alternate_email;
      case NotificationType.LIKE_CREATED:
        return Icons.favorite_outline;
      case NotificationType.FRIEND_REQUEST:
        return Icons.person_add_outlined;
      case NotificationType.FRIEND_ACCEPTED:
        return Icons.check_circle_outline;
      case NotificationType.CUSTOM:
      case NotificationType.BLOG_NUDGE:
        return Icons.notifications_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Widget _buildNotificationTitle(String title, ThemeData theme) {
    // 유저네임 추출 (예: "doppy_official님이" -> "doppy_official님")
    final username = notification.relatedUsername;

    if (username != null) {
      // 제목에서 유저네임 찾기 (다양한 패턴 지원)
      final patterns = [
        '$username님이',
        '$username님의',
        '$username님을',
        '$username님',
      ];

      String? matchedPattern;
      int? usernameIndex;

      for (final pattern in patterns) {
        if (title.contains(pattern)) {
          matchedPattern = pattern;
          usernameIndex = title.indexOf(pattern);
          break;
        }
      }

      if (matchedPattern != null &&
          usernameIndex != null &&
          usernameIndex != -1) {
        final beforeUsername = title.substring(0, usernameIndex);
        final afterUsername = title.substring(
          usernameIndex + matchedPattern.length,
        );

        return Text.rich(
          TextSpan(
            children: [
              if (beforeUsername.isNotEmpty)
                TextSpan(
                  text: beforeUsername,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              TextSpan(
                text: matchedPattern,
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (afterUsername.isNotEmpty)
                TextSpan(
                  text: afterUsername,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    // 유저네임을 찾을 수 없으면 기본 스타일
    return Text(
      title,
      style: GoogleFonts.notoSansKr(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurface,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 프로필 아바타
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (notification.relatedUsername != null)
                  CommonProfileAvatar(
                    imageUrl: null,
                    username: notification.relatedUsername ?? '',
                    size: 65,
                  )
                else
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surfaceVariant,
                    ),
                    child: Icon(
                      _getNotificationIcon(),
                      size: 24,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),

                // 좋아요 알림인 경우 하트 아이콘 - 프로필 원의 아래
                if (notification.type == NotificationType.LIKE_CREATED)
                  Positioned(
                    bottom: -2,
                    left: 28,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surface,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.favorite,
                          size: 18,
                          color: const Color.fromARGB(255, 255, 106, 96),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // 알림 내용
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNotificationTitle(notification.title, theme),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(notification.createdAt),
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}
