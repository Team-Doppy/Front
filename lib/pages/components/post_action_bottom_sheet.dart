import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:doppy/pages/components/liked_users_bottom_sheet.dart';
import 'package:doppy/pages/components/shimmer_box.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/report_service.dart';
import 'package:doppy/data/services/friend_service.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';

/// 🎯 글에 대한 액션 바텀시트
class PostActionBottomSheet extends StatelessWidget {
  final String postId;
  final String postTitle;
  final String authorUsername;
  final String? authorAlias;
  final String? authorProfileImageUrl;
  final String? thumbnailImageUrl;
  final int likeCount;
  final VoidCallback? onShowLikedUsers;

  const PostActionBottomSheet({
    super.key,
    required this.postId,
    required this.postTitle,
    required this.authorUsername,
    this.authorAlias,
    this.authorProfileImageUrl,
    this.thumbnailImageUrl,
    required this.likeCount,
    this.onShowLikedUsers,
  });

  static void show(
    BuildContext context, {
    required String postId,
    required String postTitle,
    required String authorUsername,
    String? authorAlias,
    String? authorProfileImageUrl,
    String? thumbnailImageUrl,
    required int likeCount,
    VoidCallback? onShowLikedUsers,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => PostActionBottomSheet(
            postId: postId,
            postTitle: postTitle,
            authorUsername: authorUsername,
            authorAlias: authorAlias,
            authorProfileImageUrl: authorProfileImageUrl,
            thumbnailImageUrl: thumbnailImageUrl,
            likeCount: likeCount,
            onShowLikedUsers: onShowLikedUsers,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      decoration: BoxDecoration(color: Colors.transparent),
      child: Stack(
        children: [
          // 🎯 블러 배경 탭 감지
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
          ),
          // 🎯 모달 컨텐츠
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // 컨텐츠 탭 시 닫히지 않도록
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 글 제목
                    Text(
                      postTitle.isNotEmpty ? postTitle : l10n.t('post'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // 이 글 신고 버튼
                    _buildActionItem(
                      context,
                      label: l10n.t('report_post'),
                      textColor: theme.colorScheme.error,
                      onTap: () => _handleReportPost(context),
                    ),
                    // 디바이더
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 0,
                      endIndent: 0,
                      color: theme.colorScheme.onSurface.withOpacity(0.05),
                    ),
                    // 작성자 차단 버튼
                    _buildActionItem(
                      context,
                      label: l10n.t('block_author'),
                      textColor: theme.colorScheme.error,
                      onTap: () => _handleBlockAuthor(context),
                    ),
                    // 디바이더
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 0,
                      endIndent: 0,
                      color: theme.colorScheme.onSurface.withOpacity(0.05),
                    ),
                    // 좋아요 한 사람들 버튼
                    _buildActionItem(
                      context,
                      label: l10n.t('liked_users'),
                      textColor: theme.colorScheme.onSurface,
                      onTap: () => _handleShowLikedUsers(context),
                    ),
                    // 디바이더
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 0,
                      endIndent: 0,
                      color: theme.colorScheme.onSurface.withOpacity(0.05),
                    ),
                    // 작성자 프로필 보기 버튼
                    _buildActionItem(
                      context,
                      label: l10n.t('view_author_profile'),
                      textColor: theme.colorScheme.onSurface,
                      onTap: () => _handleViewAuthorProfile(context),
                    ),
                    const SizedBox(height: 24),
                    // 취소 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.onSurface
                              .withOpacity(0.03),
                          foregroundColor: theme.colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          l10n.t('cancel'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required String label,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }

  void _handleReportPost(BuildContext context) {
    Navigator.of(context).pop();
    // 🎯 글 신고 페이지 뷰로 이동
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => _PostReportPage(
              postId: postId,
              postTitle: postTitle,
              thumbnailImageUrl: thumbnailImageUrl,
              authorUsername:
                  authorUsername, // 🎯 작성자 정보 전달 (신고 시 reportedUserId 설정용)
            ),
        fullscreenDialog: true,
      ),
    );
  }

  void _handleBlockAuthor(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final displayName = authorAlias ?? authorUsername;

    // 🎯 DialogUtils 사용하여 확인 다이얼로그 표시
    final confirm = await DialogUtils.showConfirmDialog(
      context,
      title: l10n.t('block_user_confirm_title'),
      message: l10n
          .t('block_user_confirm_message')
          .replaceAll('{name}', displayName),
      confirmText: l10n.t('block_user'),
      cancelText: l10n.t('cancel'),
      isDestructive: true,
    );

    // 취소한 경우: 바텀시트만 닫고 종료
    if (confirm != true) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    // 확인한 경우: 차단 진행
    if (!context.mounted) return;

    // 🎯 바텀시트 닫기 전에 상위 context와 root context 저장
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    BuildContext? parentContext;
    BuildContext? rootContext;
    try {
      // 바텀시트를 닫기 전에 상위 context를 가져옴
      parentContext = navigator.context;
      rootContext = rootNavigator.context;
    } catch (e) {
      print('[PostActionBottomSheet] 상위 context 가져오기 실패: $e');
    }

    // 바텀시트 닫기
    navigator.pop();

    // 🎯 차단 API 호출
    try {
      final friendService = FriendService();
      await friendService.blockUser(authorUsername);

      // 🎯 검색 기록에서 차단된 사용자 제거
      try {
        final searchService = SearchService();
        searchService.removeFromSearchHistory(authorUsername);
        print('[PostActionBottomSheet] 검색 기록에서 제거 완료: $authorUsername');
      } catch (e) {
        print('[PostActionBottomSheet] 검색 기록 제거 실패: $e');
        // 검색 기록 제거 실패해도 차단은 성공으로 간주
      }

      // 🎯 친구 캐시 클리어
      try {
        final finalContext = parentContext ?? rootContext;
        if (finalContext != null && finalContext.mounted) {
          final friendProvider = Provider.of<FriendProvider>(
            finalContext,
            listen: false,
          );
          // 캐시 무효화를 위해 _lastFetchTime을 null로 설정
          friendProvider.fetchAllFriendData(forceRefresh: true);
          print('[PostActionBottomSheet] 친구 캐시 클리어 완료');
        }
      } catch (e) {
        print('[PostActionBottomSheet] 친구 캐시 클리어 실패: $e');
      }

      // 🎯 그룹 캐시 클리어
      try {
        final finalContext = parentContext ?? rootContext;
        if (finalContext != null && finalContext.mounted) {
          final groupProvider = GroupProvider();
          groupProvider.clearAllCache();
          // 그룹 데이터 재조회
          final friendProvider = Provider.of<FriendProvider>(
            finalContext,
            listen: false,
          );
          await groupProvider.fetchMyGroups(
            forceRefresh: true,
            friendProvider: friendProvider,
          );
          print('[PostActionBottomSheet] 그룹 캐시 클리어 완료');
        }
      } catch (e) {
        print('[PostActionBottomSheet] 그룹 캐시 클리어 실패: $e');
      }

      // 🎯 차단 성공 후 처리
      // 약간의 지연을 두어 Navigator 스택이 안정화되도록 함
      await Future.delayed(const Duration(milliseconds: 100));

      // 성공 메시지 표시 (parentContext 우선 사용, 없으면 rootContext)
      final finalContext = parentContext ?? rootContext;
      if (finalContext != null && finalContext.mounted) {
        ErrorHandler.showInfo(finalContext, '차단했습니다');
      }
    } catch (e) {
      print('[PostActionBottomSheet] 차단 실패: $e');
      final finalContext = parentContext ?? rootContext;
      if (finalContext != null && finalContext.mounted) {
        ErrorHandler.showError(finalContext, e.toString());
      }
    }
  }

  void _handleShowLikedUsers(BuildContext context) {
    Navigator.of(context).pop();
    if (onShowLikedUsers != null) {
      onShowLikedUsers!();
    } else {
      // 직접 표시
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder:
            (context) =>
                LikedUsersBottomSheet(postId: postId, likeCount: likeCount),
      );
    }
  }

  void _handleViewAuthorProfile(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => UserProfileScreen(
              otherUser: User(
                username: authorUsername,
                alias: authorAlias,
                profileImageUrl: authorProfileImageUrl,
              ),
            ),
      ),
    );
  }
}

/// 🎯 글 신고 페이지
class _PostReportPage extends StatefulWidget {
  final String postId;
  final String postTitle;
  final String? thumbnailImageUrl;
  final String? authorUsername; // 🎯 작성자 정보 (신고 시 reportedUserId 설정용)

  const _PostReportPage({
    required this.postId,
    required this.postTitle,
    this.thumbnailImageUrl,
    this.authorUsername,
  });

  @override
  State<_PostReportPage> createState() => _PostReportPageState();
}

class _PostReportPageState extends State<_PostReportPage> {
  final TextEditingController _reportController = TextEditingController();
  bool _isReporting = false;

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.t('report_post_title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🎯 글 썸네일 이미지
              if (widget.thumbnailImageUrl != null &&
                  widget.thumbnailImageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CachedNetworkImage(
                    imageUrl: widget.thumbnailImageUrl!,
                    width: 150,
                    height: 160,
                    fit: BoxFit.cover,
                    placeholder:
                        (context, url) => ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: ShimmerBox(
                            width: double.infinity,
                            height: 200,
                          ),
                        ),
                    errorWidget:
                        (context, url, error) => Container(
                          width: double.infinity,
                          height: 200,
                          color: theme.colorScheme.surfaceVariant,
                          child: const Icon(Icons.error_outline),
                        ),
                  ),
                ),
              if (widget.thumbnailImageUrl != null &&
                  widget.thumbnailImageUrl!.isNotEmpty)
                const SizedBox(height: 8),
              // 글 제목 표시
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),

                child: Text(
                  widget.postTitle.isNotEmpty
                      ? widget.postTitle
                      : l10n.t('post'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 20),
              // 신고 사유 입력 필드
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: TextField(
                  controller: _reportController,
                  autofocus: true,
                  maxLines: null,
                  minLines: 3,
                  textInputAction: TextInputAction.newline,
                  cursorColor: theme.colorScheme.onSurface,
                  onChanged: (_) {
                    setState(() {}); // 🎯 입력 시 신고 버튼 상태 업데이트
                  },
                  decoration: InputDecoration(
                    hintText: l10n.t('report_reason_hint'),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceVariant,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 신고 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _reportController.text.trim().isEmpty || _isReporting
                          ? null
                          : () => _handleReportSubmit(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _reportController.text.trim().isEmpty
                            ? theme.colorScheme.surfaceVariant
                            : theme.colorScheme.onSurface,
                    foregroundColor:
                        _reportController.text.trim().isEmpty
                            ? theme.colorScheme.onSurface.withOpacity(0.5)
                            : theme.colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child:
                      _isReporting
                          ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.onSurface,
                              ),
                            ),
                          )
                          : Text(
                            l10n.t('report_submit'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleReportSubmit(BuildContext context) async {
    final reason = _reportController.text.trim();

    if (reason.isEmpty) return;

    final l10n = AppLocalizations.of(context);

    if (_isReporting) return;

    setState(() {
      _isReporting = true;
    });

    try {
      final reportService = ReportService();
      await reportService.reportPost(
        postId: widget.postId,
        reason: ReportReason.other, // 사용자가 입력한 description을 other로 분류
        description: reason,
        authorUsername:
            widget.authorUsername, // 🎯 작성자 정보 전달 (신고 시 reportedUserId 설정용)
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // 페이지 닫기

      // 🎯 신고 성공 안내
      ErrorHandler.showInfo(context, l10n.t('report_success'));
    } catch (e) {
      // 상세 오류 로그는 콘솔에만 출력 (사용자에게는 일반화된 메시지 표시)
      print('[PostReportPage] ❌ 글 신고 실패: $e');
      if (context.mounted) {
        // 일반화된 오류 메시지 표시 (로케일 적용)
        ErrorHandler.showError(context, l10n.t('report_fail'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReporting = false;
        });
      }
    }
  }
}
