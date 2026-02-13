import 'package:doppy/data/services/auth_service.dart';
import 'package:doppy/onbording/onbording_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/snackbar_util.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── 문자열 (한글) ─────────────────────────────────────────────
class _AccountDeleteStrings {
  static const deleteAccount = '회원 탈퇴';
  static const deleteAccountWarning = '탈퇴 시 모든 데이터가 삭제되며 복구할 수 없습니다.';
  static const deleteAction = '탈퇴하기';
  static const detailReasonHint = '탈퇴 사유를 입력해주세요 (선택)';
  static const reasonNotUseful = '사용하지 않아요';
  static const reasonPrivacy = '개인정보가 걱정돼요';
  static const reasonAlternative = '다른 서비스를 이용할 거예요';
  static const reasonComplicated = '이용 방법이 어려워요';
  static const reasonOther = '기타';
  static const otherReasonRequired = '기타를 선택한 경우 탈퇴 이유를 입력해주세요.';
}

class AccountDeletionSheet extends StatefulWidget {
  const AccountDeletionSheet({super.key});

  @override
  State<AccountDeletionSheet> createState() => _AccountDeletionSheetState();

  /// 탈퇴 처리 후 로그인 화면으로 이동 (확인 다이얼로그에서 확인 시 부모에서 호출)
  static Future<void> performDeletionAndNavigate(
    BuildContext context, {
    required String reasonKey,
    String? detail,
  }) async {
    final success = await processDeletion(reasonKey: reasonKey, detail: detail);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(deletionResult: success)),
      (route) => false,
    );
  }

  static Future<bool> processDeletion({
    required String reasonKey,
    String? detail,
  }) async {
    String? username;
    try {
      username = await AuthService().getUsername();
      if (username != null && username.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('account_deletion_in_progress_$username', true);
      }
    } catch (e) {
      debugPrint('[AccountDeletionSheet] 탈퇴 진행 플래그 설정 실패: $e');
    }

    bool deletionSuccess = false;
    try {
      final userService = UserService();
      await userService.deleteAccount(reasonKey: reasonKey, detail: detail);
      deletionSuccess = true;
    } catch (e) {
      debugPrint('[AccountDeletionSheet] 회원 탈퇴 API 실패: $e');
    }

    if (deletionSuccess) {
      try {
        await AuthProvider().logout();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (username != null) {
          await prefs.remove('account_deletion_in_progress_$username');
        }
      } catch (e) {
        debugPrint('[AccountDeletionSheet] 로컬 정리 실패(무시): $e');
      }
    }

    return deletionSuccess;
  }
}

class _AccountDeletionSheetState extends State<AccountDeletionSheet> {
  String? _selectedReason;
  final TextEditingController _detailController = TextEditingController();
  List<Map<String, String>> _getReasons() {
    return [
      {'key': 'not_useful', 'text': _AccountDeleteStrings.reasonNotUseful},
      {'key': 'privacy', 'text': _AccountDeleteStrings.reasonPrivacy},
      {'key': 'alternative', 'text': _AccountDeleteStrings.reasonAlternative},
      {'key': 'complicated', 'text': _AccountDeleteStrings.reasonComplicated},
      {'key': 'other', 'text': _AccountDeleteStrings.reasonOther},
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

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92 - keyboardHeight,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 8, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _AccountDeleteStrings.deleteAccount,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24, left: 10),
                    child: Text(
                      _AccountDeleteStrings.deleteAccountWarning,
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
                  Container(
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children:
                          _getReasons().asMap().entries.map((entry) {
                            final index = entry.key;
                            final reasonData = entry.value;
                            final reasonKey = reasonData['key']!;
                            final reasonText = reasonData['text']!;
                            final isSelected = _selectedReason == reasonKey;
                            final isFirst = index == 0;
                            final isLast = index == _getReasons().length - 1;
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
                                  child: Padding(
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
                    ),
                  ),
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
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: _AccountDeleteStrings.detailReasonHint,
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
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
              ),
              child: SafeArea(
                child: TextButton(
                  onPressed:
                      _isButtonEnabled()
                          ? () {
                            if (_selectedReason == 'other' &&
                                _detailController.text.trim().isEmpty) {
                              SnackbarUtil.showError(
                                context,
                                _AccountDeleteStrings.otherReasonRequired,
                              );
                              return;
                            }
                            // 바텀시트 먼저 내린 뒤, 부모에서 DialogUtils로 확인 다이얼로그 표시
                            Navigator.pop(context, <String, dynamic>{
                              'reason': _selectedReason!,
                              'detail':
                                  _selectedReason == 'other'
                                      ? _detailController.text.trim()
                                      : null,
                            });
                          }
                          : null,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        _isButtonEnabled()
                            ? (isDark ? Colors.white : AppColors.darkSurface)
                            : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.1),
                    foregroundColor:
                        _isButtonEnabled()
                            ? (isDark ? Colors.black : Colors.white)
                            : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _AccountDeleteStrings.deleteAction,
                    style: const TextStyle(
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
    );
  }

  bool _isButtonEnabled() {
    if (_selectedReason == null) return false;
    if (_selectedReason == 'other' && _detailController.text.trim().isEmpty)
      return false;
    return true;
  }
}
