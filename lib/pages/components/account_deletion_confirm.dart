import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/data/services/account_deletion_service.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/dialog_utils.dart';
import 'package:doppy/utils/error_handler.dart';
import 'package:flutter/material.dart';

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
  Future<void> _handleAccountDeletion(BuildContext context) async {
    if (_isDeleting) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      // 1. 탈퇴 이유 텍스트 가져오기
      final reasons = _getReasonsWithContext(context);
      final reasonData = reasons.firstWhere((r) => r['key'] == _selectedReason);
      final reasonText = reasonData['text']!;
      final reasonKey = _selectedReason!;

      // 2. 기타 선택 시 상세 설명 가져오기
      final detail =
          reasonKey == 'other' ? _detailController.text.trim() : null;

      // 3. Firebase Firestore에 탈퇴 이유 저장
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

      // 4. 회원 탈퇴 API 호출
      final userService = UserService();
      await userService.deleteAccount();

      if (!mounted) return;

      // 5. 바텀시트 닫기
      Navigator.pop(context);

      // 6. 로그아웃 처리
      await AuthProvider().logout();

      // 7. 로그인 화면으로 이동
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);

        // 8. 탈퇴 완료 메시지 표시 (ErrorHandler 사용)
        if (context.mounted) {
          ErrorHandler.showInfo(
            context,
            context.tr('account_deletion_complete'),
          );
        }
      }
    } catch (e) {
      debugPrint('[AccountDeletionSheet] ❌ 회원 탈퇴 실패: $e');
      if (mounted) {
        ErrorHandler.showError(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
}
