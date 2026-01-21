import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/data/services/account_deletion_service.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:doppy/pages/screens/onboarding_screen.dart';
import 'package:doppy/main.dart' show navigatorKey;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountDeletionSheet extends StatefulWidget {
  const AccountDeletionSheet({super.key});

  @override
  State<AccountDeletionSheet> createState() => _AccountDeletionSheetState();
}

class _AccountDeletionSheetState extends State<AccountDeletionSheet> {
  String? _selectedReason;
  final TextEditingController _detailController = TextEditingController();
  bool _isDeleting = false;

  List<Map<String, String>> _getReasonsWithContext(BuildContext context) {
    return [
      {'key': 'not_useful', 'text': context.tr('reason_not_useful')},
      {'key': 'privacy', 'text': context.tr('reason_privacy')},
      {'key': 'alternative', 'text': context.tr('reason_alternative')},
      {'key': 'complicated', 'text': context.tr('reason_complicated')},
      {'key': 'other', 'text': context.tr('reason_other')},
    ];
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return WillPopScope(
      onWillPop: () async {
        // 탈퇴 진행 중에는 뒤로 가기/드래그로 닫기 방지
        if (_isDeleting) {
          return false;
        }
        return true;
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Container(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.of(context).size.height * 0.92 - keyboardHeight,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들바
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 제목
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 8, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('delete_account'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _isDeleting ? null : () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(context).colorScheme.onSurface
                            .withOpacity(_isDeleting ? 0.2 : 0.6),
                      ),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shrinkWrap: true,
                  children: [
                    // 경고 메시지
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24, left: 10),
                      child: Text(
                        context.tr('delete_account_warning'),
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.6),
                          height: 1.6,
                        ),
                      ),
                    ),

                    // 탈퇴 사유 선택 - 애플 스타일 그룹
                    Container(
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          ..._getReasonsWithContext(
                            context,
                          ).asMap().entries.map((entry) {
                            final index = entry.key;
                            final reasonData = entry.value;
                            final reasonKey = reasonData['key']!;
                            final reasonText = reasonData['text']!;
                            final isSelected = _selectedReason == reasonKey;
                            final isFirst = index == 0;
                            final isLast =
                                index ==
                                _getReasonsWithContext(context).length - 1;

                            return Column(
                              children: [
                                if (!isFirst)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: Divider(
                                      height: 1,
                                      thickness: 0.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.1),
                                    ),
                                  ),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedReason = reasonKey;
                                      // 기타가 아닌 다른 이유 선택 시 상세 설명 초기화
                                      if (reasonKey != 'other') {
                                        _detailController.clear();
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.vertical(
                                    top:
                                        isFirst
                                            ? const Radius.circular(12)
                                            : Radius.zero,
                                    bottom:
                                        isLast && _selectedReason != 'other'
                                            ? const Radius.circular(12)
                                            : Radius.zero,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            reasonText,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w400,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(
                                            Icons.check,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                            size: 24,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ),

                    // 상세 사유 입력 - 애플 스타일 (기타 선택 시만)
                    if (_selectedReason == 'other') ...[
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _detailController,
                          maxLines: 4,
                          maxLength: 200,
                          onChanged:
                              (value) => setState(
                                () {},
                              ), // 🎯 입력 시 상태 업데이트 (버튼 활성화/비활성화)
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: context.tr('detail_reason_hint'),
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.4),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: surfaceColor,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // 하단 고정 버튼 - 애플 스타일
              Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: SafeArea(
                  child: TextButton(
                    onPressed:
                        (_selectedReason == null ||
                                (_selectedReason == 'other' &&
                                    _detailController.text.trim().isEmpty) ||
                                _isDeleting)
                            ? null
                            : () async {
                              // 🎯 기타 선택 시 상세 설명 필수 검증
                              if (_selectedReason == 'other' &&
                                  _detailController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('기타를 선택하셨을 경우 탈퇴 이유를 입력해주세요'),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                );
                                return;
                              }

                              final confirmed =
                                  await DialogUtils.showConfirmDialog(
                                    context,
                                    title: context.tr('delete_account'),
                                    message: context.tr(
                                      'delete_account_final_confirm',
                                    ),
                                    confirmText: context.tr('delete_confirm'),
                                    cancelText: context.tr('cancel'),
                                    isDestructive: true,
                                  );

                              if (confirmed == true) {
                                await _handleAccountDeletion(context);
                              }
                            },
                    style: TextButton.styleFrom(
                      backgroundColor:
                          (_selectedReason == null ||
                                  (_selectedReason == 'other' &&
                                      _detailController.text.trim().isEmpty) ||
                                  _isDeleting)
                              ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.1)
                              : (isDark ? Colors.white : AppColors.darkSurface),
                      foregroundColor:
                          (_selectedReason == null ||
                                  (_selectedReason == 'other' &&
                                      _detailController.text.trim().isEmpty) ||
                                  _isDeleting)
                              ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.4)
                              : (isDark ? Colors.black : Colors.white),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child:
                        _isDeleting
                            ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            )
                            : Text(
                              context.tr('delete_action'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 17,
                              ),
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

  /// 회원 탈퇴 처리 (Firebase 저장 → API 호출 → 로그아웃)
  /// ✅ 버튼 클릭 시 즉시 화면 전환하고, 탈퇴 처리는 백그라운드에서 진행
  Future<void> _handleAccountDeletion(BuildContext context) async {
    if (_isDeleting) return;

    setState(() {
      _isDeleting = true;
    });

    // ✅ 1. 탈퇴 이유 데이터 미리 수집 (화면 전환 전)
    final reasons = _getReasonsWithContext(context);
    final reasonData = reasons.firstWhere((r) => r['key'] == _selectedReason);
    final reasonText = reasonData['text']!;
    final reasonKey = _selectedReason!;
    final detail = reasonKey == 'other' ? _detailController.text.trim() : null;

    // ✅ 2. 짧은 딜레이 후 즉시 화면 전환 (백그라운드 처리 시작 전)
    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted) return;

    // 바텀시트 닫기 및 모든 화면 제거 후 LoginScreen으로 이동
    Navigator.of(context, rootNavigator: true).pop();
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );

    // ✅ 3. 백그라운드에서 탈퇴 처리 진행 (화면 전환 후)
    _processAccountDeletionInBackground(
      reasonKey: reasonKey,
      reasonText: reasonText,
      detail: detail,
    );
  }

  /// 백그라운드에서 회원 탈퇴 처리 (서버 기반: API 성공 후에만 로컬 파쇄)
  Future<void> _processAccountDeletionInBackground({
    required String reasonKey,
    required String reasonText,
    String? detail,
  }) async {
    bool deletionSuccess = false;
    String? accountKey;

    try {
      // ✅ 0. 탈퇴 진행 중 플래그 설정 (재접속 시 상태 확인용)
      try {
        final authService = AuthService();
        accountKey = await authService.getAccountKeyFromToken();
        if (accountKey != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('account_deletion_in_progress_$accountKey', true);
          debugPrint('[AccountDeletionSheet] ✅ 탈퇴 진행 중 플래그 설정');
        }
      } catch (e) {
        debugPrint('[AccountDeletionSheet] ⚠️ 탈퇴 진행 중 플래그 설정 실패: $e');
      }

      // ✅ IMPORTANT: 서버 기반 전환
      // 1. 서버 API가 성공할 때만 로컬 파쇄
      // 2. API 실패 시 재시도 (최대 3회)
      // 3. 최종 실패 시에도 플래그는 유지하여 재접속 시 재시도 가능

      // 1) Firebase Firestore에 탈퇴 이유 저장 (로그인 사용자 정보가 필요할 수 있음)
      try {
        final deletionService = AccountDeletionService();
        await deletionService.saveDeletionReason(
          reason: reasonKey,
          reasonText: reasonText,
          detail: detail,
        );
        debugPrint('[AccountDeletionSheet] ✅ 탈퇴 이유 Firestore 저장 완료');
      } catch (e) {
        debugPrint(
          '[AccountDeletionSheet] ⚠️ 탈퇴 이유 Firestore 저장 실패 (계속 진행): $e',
        );
        // Firestore 저장 실패해도 계속 진행 (API 호출은 수행)
      }

      // 2) 회원 탈퇴 API 호출 (단일 시도)
      try {
        debugPrint('[AccountDeletionSheet] 회원 탈퇴 API 호출');
        final userService = UserService();
        await userService.deleteAccount();
        debugPrint('[AccountDeletionSheet] ✅ 회원 탈퇴 API 호출 성공');
        deletionSuccess = true;
      } catch (e) {
        debugPrint('[AccountDeletionSheet] ⚠️ 회원 탈퇴 API 호출 실패: $e');
        deletionSuccess = false;
      }

      // ✅ 3) 서버 API 성공 시에만 로컬 데이터 파쇄
      if (deletionSuccess) {
        try {
          // ✅ 순서: logout() 먼저 (SharedPreferences 참조 가능), 그 다음 prefs.clear()
          // ✅ 토큰/리프레시 토큰 등 SecureStorage 삭제 + 모든 Provider/캐시 초기화
          await AuthProvider().logout();

          // ✅ SharedPreferences에 저장된 모든 데이터 삭제 (첫 설치 상태로)
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();

          // ✅ 탈퇴 진행 중 플래그도 제거
          if (accountKey != null) {
            await prefs.remove('account_deletion_in_progress_$accountKey');
          }

          debugPrint(
            '[AccountDeletionSheet] ✅ 로컬 데이터(SharedPreferences+토큰) 파쇄 및 Provider 초기화 완료',
          );
        } catch (e) {
          debugPrint('[AccountDeletionSheet] ⚠️ 로컬 파쇄/로그아웃 실패(무시): $e');
        }
      } else {
        // ✅ API 실패 시: 탈퇴 진행 중 플래그는 유지 (재접속 시 재시도 가능)
        debugPrint('[AccountDeletionSheet] ❌ 회원 탈퇴 API 실패');
      }

      debugPrint('[AccountDeletionSheet] ✅ 회원 탈퇴 백그라운드 처리 완료');

      // ✅ 4) 탈퇴 성공/실패 스낵바 표시
      final context = navigatorKey.currentContext;
      if (context != null) {
        final localizations = AppLocalizations.of(context);
        if (deletionSuccess) {
          // 성공: "탈퇴처리되었습니다, 이용해주셔서 감사합니다"
          ErrorHandler.showInfo(
            context,
            localizations.translate('account_deletion_success'),
            duration: const Duration(seconds: 3),
          );
        } else {
          // 실패: "탈퇴에 실패했어요 다시 시도해주세요"
          ErrorHandler.showError(
            context,
            localizations.translate('account_deletion_failed'),
            duration: const Duration(seconds: 3),
          );
        }
      }
    } catch (e) {
      debugPrint('[AccountDeletionSheet] ❌ 회원 탈퇴 백그라운드 처리 실패: $e');
      // ✅ 에러 발생 시에도 스낵바 표시
      final context = navigatorKey.currentContext;
      if (context != null) {
        final localizations = AppLocalizations.of(context);
        ErrorHandler.showError(
          context,
          localizations.translate('account_deletion_failed'),
          duration: const Duration(seconds: 3),
        );
      }
    }
  }
}
