import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/report_service.dart';
import 'package:doppy/data/services/friend_service.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';

/// 🎯 프로필 액션 바텀시트 (재사용 가능한 컴포넌트)
class ProfileActionBottomSheet extends StatelessWidget {
  final String username;
  final String? alias;
  final String? profileImageUrl;
  final VoidCallback? onBlockSuccess; // 🎯 차단 성공 콜백
  final bool hideViewProfile; // 🎯 프로필 보기 옵션 숨김 (프로필 화면에서 열 때)

  const ProfileActionBottomSheet({
    super.key,
    required this.username,
    this.alias,
    this.profileImageUrl,
    this.onBlockSuccess,
    this.hideViewProfile = false,
  });

  static void show(
    BuildContext context, {
    required String username,
    String? alias,
    String? profileImageUrl,
    VoidCallback? onBlockSuccess, // 🎯 차단 성공 콜백
    bool hideViewProfile = false, // 🎯 프로필 보기 옵션 숨김
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder:
          (context) => ProfileActionBottomSheet(
            username: username,
            alias: alias,
            profileImageUrl: profileImageUrl,
            onBlockSuccess: onBlockSuccess,
            hideViewProfile: hideViewProfile,
          ),
    );
  }

  static void showReportPage(
    BuildContext context, {
    required String username,
    String? alias,
    String? profileImageUrl,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => _ReportPage(
              username: username,
              alias: alias,
              profileImageUrl: profileImageUrl,
            ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = alias ?? username;
    return _buildActionList(context, theme, displayName);
  }

  Widget _buildActionList(
    BuildContext context,
    ThemeData theme,
    String displayName,
  ) {
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
                    // 프로필 이미지
                    CommonProfileAvatar(
                      imageUrl: profileImageUrl,
                      username: username,
                      size: 80,
                      borderWidth: 0,
                    ),
                    const SizedBox(height: 16),
                    // 유저네임
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 신고 버튼
                    _buildActionItem(
                      context,
                      label: l10n.t('report_user'),
                      textColor: theme.colorScheme.error,
                      onTap: () => _handleReport(context),
                    ),
                    // 디바이더
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 0,
                      endIndent: 0,
                      color: theme.colorScheme.onSurface.withOpacity(0.05),
                    ),
                    // 차단 버튼
                    _buildActionItem(
                      context,
                      label: l10n.t('block_user'),
                      textColor: theme.colorScheme.error,
                      onTap: () => _handleBlock(context),
                    ),
                    // 프로필 화면에서 열 때는 프로필 보기 옵션 숨김
                    if (!hideViewProfile) ...[
                      // 디바이더
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 0,
                        endIndent: 0,
                        color: theme.colorScheme.onSurface.withOpacity(0.05),
                      ),
                      // 프로필 보기 버튼
                      _buildActionItem(
                        context,
                        label: l10n.t('view_profile'),
                        textColor: theme.colorScheme.onSurface,
                        onTap: () => _handleViewProfile(context),
                      ),
                    ],
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

  void _handleBlock(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final displayName = alias ?? username;

    // 🎯 다이얼로그 표시
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

    // 🎯 바텀시트 닫기 전에 상위 context와 콜백 저장
    final navigator = Navigator.of(context);
    final callback = onBlockSuccess;

    // 상위 Navigator의 context 가져오기 (바텀시트를 닫기 전에)
    BuildContext? parentContext;
    try {
      // 바텀시트를 닫기 전에 상위 context를 가져옴
      parentContext = navigator.context;
    } catch (e) {
      print('[ProfileActionBottomSheet] 상위 context 가져오기 실패: $e');
    }

    // 바텀시트 닫기
    navigator.pop();

    // 🎯 차단 API 호출
    try {
      final friendService = FriendService();
      await friendService.blockUser(username);

      // 🎯 검색 기록에서 차단된 사용자 제거
      try {
        final searchService = SearchService();
        searchService.removeFromSearchHistory(username);
      } catch (e) {
        print('[ProfileActionBottomSheet] 검색 기록 제거 실패: $e');
      }

      // 🎯 친구 캐시 클리어
      try {
        if (parentContext != null && parentContext.mounted) {
          final friendProvider = Provider.of<FriendProvider>(
            parentContext,
            listen: false,
          );
          // 캐시 무효화를 위해 _lastFetchTime을 null로 설정
          friendProvider.fetchAllFriendData(forceRefresh: true);
          print('[ProfileActionBottomSheet] 친구 캐시 클리어 완료');
        }
      } catch (e) {
        print('[ProfileActionBottomSheet] 친구 캐시 클리어 실패: $e');
      }

      // 🎯 그룹 캐시 클리어
      try {
        if (parentContext != null && parentContext.mounted) {
          final groupProvider = GroupProvider();
          groupProvider.clearAllCache();
          // 그룹 데이터 재조회
          final friendProvider = Provider.of<FriendProvider>(
            parentContext,
            listen: false,
          );
          await groupProvider.fetchMyGroups(
            forceRefresh: true,
            friendProvider: friendProvider,
          );
          print('[ProfileActionBottomSheet] 그룹 캐시 클리어 완료');
        }
      } catch (e) {
        print('[ProfileActionBottomSheet] 그룹 캐시 클리어 실패: $e');
      }

      // 🎯 차단 성공 후 처리
      // 약간의 지연을 두어 Navigator 스택이 안정화되도록 함
      await Future.delayed(const Duration(milliseconds: 100));

      // 콜백 실행
      if (callback != null) {
        print('[ProfileActionBottomSheet] 콜백 실행');
        callback();
      } else {
        // 콜백이 없으면 상위 Navigator로 프로필 페이지 닫기 시도
        if (parentContext != null && parentContext.mounted) {
          final parentNav = Navigator.of(parentContext);
          if (parentNav.canPop()) {
            parentNav.pop();
          }
        }
      }

      // 성공 메시지 표시
      if (parentContext != null && parentContext.mounted) {
        ErrorHandler.showInfo(parentContext, '차단했습니다');
      }
    } catch (e) {
      print('[ProfileActionBottomSheet] 차단 실패: $e');
      if (parentContext != null && parentContext.mounted) {
        ErrorHandler.showError(parentContext, e.toString());
      }
    }
  }

  void _handleReport(BuildContext context) async {
    print('[ProfileActionBottomSheet] 신고 시작 - username: $username');

    // 바텀시트 닫기
    Navigator.of(context).pop();
    print('[ProfileActionBottomSheet] 바텀시트 닫기 완료');

    // 🎯 약간의 지연 후 신고 페이지 열기
    await Future.delayed(const Duration(milliseconds: 100));

    // 🎯 신고 페이지 열기 (스낵바는 신고 페이지에서 직접 표시)
    print('[ProfileActionBottomSheet] 신고 페이지 열기 시작');
    ProfileActionBottomSheet.showReportPage(
      context,
      username: username,
      alias: alias,
      profileImageUrl: profileImageUrl,
    );
  }

  void _handleViewProfile(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => UserProfileScreen(
              otherUser: User(
                username: username,
                alias: alias,
                profileImageUrl: profileImageUrl,
              ),
            ),
      ),
    );
  }
}

/// 🎯 신고 페이지
class _ReportPage extends StatefulWidget {
  final String username;
  final String? alias;
  final String? profileImageUrl;

  const _ReportPage({required this.username, this.alias, this.profileImageUrl});

  @override
  State<_ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<_ReportPage> {
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
    final displayName = widget.alias ?? widget.username;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.t('report_user_title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 프로필 이미지 및 유저네임
              CommonProfileAvatar(
                imageUrl: widget.profileImageUrl,
                username: widget.username,
                size: 80,
                borderWidth: 0,
              ),
              const SizedBox(height: 16),
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 32),
              // 신고 사유 입력 필드
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: TextField(
                  controller: _reportController,
                  autofocus: true,
                  maxLines: null,
                  minLines: 5,
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
                            ? theme.colorScheme.surface.withOpacity(0.5)
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
      await reportService.reportUser(
        targetUsername: widget.username,
        reason: ReportReason.other, // 사용자가 입력한 description을 other로 분류
        description: reason,
      );

      print('[ReportPage] 신고 API 호출 성공');

      if (!mounted) return;

      // 🎯 스낵바 먼저 표시 (페이지 닫기 전)
      print('[ReportPage] 신고 성공 메시지 표시');
      if (context.mounted) {
        ErrorHandler.showInfo(context, l10n.t('report_success'));
        print('[ReportPage] 스낵바 표시 완료');
      }

      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;

      Navigator.of(context).pop();
      print('[ReportPage] 페이지 닫기 완료');
    } catch (e) {
      // 상세 오류 로그는 콘솔에만 출력 (사용자에게는 일반화된 메시지 표시)
      print('[ReportPage] ❌ 유저 신고 실패: $e');
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
