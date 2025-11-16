import 'package:flutter/material.dart';
import 'package:doppy/data/models/user_model.dart';
import 'package:doppy/pages/components/common_profile_avatar.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/report_service.dart';
import 'package:doppy/data/services/friend_service.dart';
import 'package:doppy/utils/error_handler.dart';

/// 🎯 프로필 액션 바텀시트 (재사용 가능한 컴포넌트)
class ProfileActionBottomSheet extends StatelessWidget {
  final String username;
  final String? alias;
  final String? profileImageUrl;

  const ProfileActionBottomSheet({
    super.key,
    required this.username,
    this.alias,
    this.profileImageUrl,
  });

  static void show(
    BuildContext context, {
    required String username,
    String? alias,
    String? profileImageUrl,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => ProfileActionBottomSheet(
            username: username,
            alias: alias,
            profileImageUrl: profileImageUrl,
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
                  color: theme.colorScheme.surface.withOpacity(0.95),
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
                      onTap: () {
                        Navigator.of(context).pop(); // 바텀시트 닫기
                        ProfileActionBottomSheet.showReportPage(
                          context,
                          username: username,
                          alias: alias,
                          profileImageUrl: profileImageUrl,
                        );
                      },
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
    Navigator.of(context).pop();
    final l10n = AppLocalizations.of(context);

    try {
      final friendService = FriendService();
      await friendService.blockUser(username);

      // 🎯 차단 성공 스낵바 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.t('block_success')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('[ProfileActionBottomSheet] 차단 실패: $e');
      if (context.mounted) {
        ErrorHandler.showError(context, e.toString());
      }
    }
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

      if (!mounted) return;
      Navigator.of(context).pop(); // 페이지 닫기

      // 🎯 신고 성공 안내
      ErrorHandler.showInfo(context, l10n.t('report_success'));
    } catch (e) {
      print('[ReportPage] 신고 실패: $e');
      if (context.mounted) {
        ErrorHandler.showError(context, e.toString());
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
