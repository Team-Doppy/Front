import 'dart:io';
import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:dio/dio.dart';

enum RetryCancelAction { retry, cancel, saveDraft }

/// 에러 정보 클래스
class _ErrorInfo {
  final String message;
  final bool canRetry;
  final bool showNetworkCheck;

  const _ErrorInfo({
    required this.message,
    required this.canRetry,
    this.showNetworkCheck = false,
  });
}

/// ✅ 실패 UX 개선용: "다시 시도 / 취소" 바텀시트
/// - ResumeWritingBottomSheet와 동일한 디자인
class RetryCancelBottomSheet {
  /// 에러를 분석하여 사용자 친화적 메시지와 재시도 가능 여부 결정
  static _ErrorInfo _analyzeError(dynamic error, BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // 1. NetworkError (NetworkUtils.parseError로 이미 변환된 경우)
    if (error is NetworkError) {
      switch (error.type) {
        case NetworkErrorType.timeout:
        case NetworkErrorType.noConnection:
          return _ErrorInfo(
            message: l10n.t('error_network_connection'),
            canRetry: true,
            showNetworkCheck: true,
          );
        case NetworkErrorType.serverError:
          return _ErrorInfo(
            message: l10n.t('error_server_error'),
            canRetry: true,
            showNetworkCheck: true,
          );
        case NetworkErrorType.unauthorized:
          return _ErrorInfo(
            message: l10n.t('error_unauthorized'),
            canRetry: false,
          );
        case NetworkErrorType.notFound:
          return _ErrorInfo(
            message: l10n.t('error_not_found'),
            canRetry: false,
          );
        case NetworkErrorType.badRequest:
          return _ErrorInfo(
            message: l10n.t('error_bad_request'),
            canRetry: false,
          );
        default:
          return _ErrorInfo(message: l10n.t('error_unknown'), canRetry: false);
      }
    }

    // 2. DioException
    if (error is DioException) {
      final networkError = NetworkUtils.parseError(error);
      return _analyzeError(networkError, context);
    }

    // 3. HttpException
    if (error is HttpException) {
      // HttpException은 보통 서버 에러이거나 네트워크 문제
      final errorString = error.toString().toLowerCase();
      if (errorString.contains('timeout') ||
          errorString.contains('connection') ||
          errorString.contains('socket')) {
        return _ErrorInfo(
          message: l10n.t('error_network_connection'),
          canRetry: true,
          showNetworkCheck: true,
        );
      }
      return _ErrorInfo(
        message: l10n.t('error_server_error'),
        canRetry: true,
        showNetworkCheck: true,
      );
    }

    // 4. SocketException
    if (error is SocketException) {
      return _ErrorInfo(
        message: l10n.t('error_network_connection'),
        canRetry: true,
        showNetworkCheck: true,
      );
    }

    // 5. StateError - 검증 에러들
    if (error is StateError) {
      final errorMessage = error.message.toLowerCase();

      // author 관련
      if (errorMessage.contains('author is required')) {
        return _ErrorInfo(
          message: l10n.t('error_author_required'),
          canRetry: true,
        );
      }

      // 필수 필드 관련 (재시도 불가)
      if (errorMessage.contains('title is required') ||
          errorMessage.contains('content is required') ||
          errorMessage.contains('categoryId is required') ||
          errorMessage.contains('thumbnail')) {
        return _ErrorInfo(
          message: l10n.t('error_required_fields'),
          canRetry: false,
        );
      }

      // 그룹 관련
      if (errorMessage.contains('group') || errorMessage.contains('GROUPS')) {
        return _ErrorInfo(
          message: l10n.t('error_group_required'),
          canRetry: false,
        );
      }

      // 업로드 중인 미디어
      if (errorMessage.contains('업로드 중') ||
          errorMessage.contains('uploading')) {
        return _ErrorInfo(
          message: l10n.t('error_media_uploading'),
          canRetry: true,
        );
      }

      // 비디오 URL 로컬 경로
      if (errorMessage.contains('비디오') && errorMessage.contains('로컬')) {
        return _ErrorInfo(
          message: l10n.t('error_video_not_uploaded'),
          canRetry: true,
        );
      }

      // 기타 StateError
      return _ErrorInfo(
        message: l10n.t('error_validation_failed'),
        canRetry: false,
      );
    }

    // 6. TimeoutException
    if (error.toString().contains('TimeoutException') ||
        error.toString().toLowerCase().contains('timeout')) {
      return _ErrorInfo(
        message: l10n.t('error_network_timeout'),
        canRetry: true,
        showNetworkCheck: true,
      );
    }

    // 7. 기타 에러
    return _ErrorInfo(message: l10n.t('error_unknown'), canRetry: false);
  }

  static Future<RetryCancelAction?> show(
    BuildContext context, {
    required String title,
    String? message,
    dynamic error,
    String? retryText,
    String? cancelText,
    bool showSaveDraft = false,
    String? saveDraftText,
  }) {
    final l10n = AppLocalizations.of(context);

    // error가 제공되면 분석하여 메시지와 재시도 가능 여부 결정
    final errorInfo =
        error != null
            ? _analyzeError(error, context)
            : _ErrorInfo(
              message: message ?? l10n.t('retry_error_message'),
              canRetry: true,
            );

    final finalMessage =
        error != null
            ? errorInfo.message
            : (message ?? l10n.t('retry_error_message'));

    // 네트워크 확인 메시지가 필요한 경우 추가 안내
    final displayMessage =
        errorInfo.showNetworkCheck
            ? '$finalMessage\n${l10n.t('error_check_network')}'
            : finalMessage;

    // 로케일 적용
    final finalRetryText = retryText ?? l10n.t('retry');
    final finalCancelText = cancelText ?? l10n.t('cancel');
    final finalSaveDraftText = saveDraftText ?? l10n.t('save_draft');
    return showModalBottomSheet<RetryCancelAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final onSurface = theme.colorScheme.onSurface;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          decoration: const BoxDecoration(color: Colors.transparent),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(bottomSheetContext).pop(null),
                  child: Container(color: Colors.transparent),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {},
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
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          displayMessage,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (errorInfo.canRetry)
                          _buildActionItem(
                            bottomSheetContext,
                            label: finalRetryText,
                            textColor: onSurface,
                            onTap: () {
                              Navigator.of(
                                bottomSheetContext,
                              ).pop(RetryCancelAction.retry);
                            },
                          ),
                        if (errorInfo.canRetry)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 0,
                            endIndent: 0,
                            color: onSurface.withOpacity(0.05),
                          ),
                        if (showSaveDraft) ...[
                          _buildActionItem(
                            bottomSheetContext,
                            label: finalSaveDraftText,
                            textColor: onSurface,
                            onTap: () {
                              Navigator.of(
                                bottomSheetContext,
                              ).pop(RetryCancelAction.saveDraft);
                            },
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 0,
                            endIndent: 0,
                            color: onSurface.withOpacity(0.05),
                          ),
                        ],
                        _buildActionItem(
                          bottomSheetContext,
                          label: finalCancelText,
                          textColor: theme.colorScheme.error,
                          onTap: () {
                            Navigator.of(
                              bottomSheetContext,
                            ).pop(RetryCancelAction.cancel);
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                () =>
                                    Navigator.of(bottomSheetContext).pop(null),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: onSurface.withOpacity(0.03),
                              foregroundColor: onSurface,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              l10n.t('close'),
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
      },
    );
  }

  static Widget _buildActionItem(
    BuildContext context, {
    required String label,
    required Color textColor,
    required VoidCallback? onTap,
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
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
