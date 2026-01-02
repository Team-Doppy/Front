import 'package:flutter/material.dart';
import 'package:doppy/l10n/app_localizations.dart';

/// 포스트 리더 에러 화면 컴포넌트
class PostReaderErrorScreen extends StatelessWidget {
  const PostReaderErrorScreen({
    super.key,
    this.showBackButton = true,
    this.onBack,
  });

  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ 에러 화면에서도 키보드(viewInsets)로 인한 불필요 레이아웃 변경 차단
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: showBackButton
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 24,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.75),
                  ),
                  onPressed: onBack ?? () => Navigator.of(context).pop(),
                ),
              ),
            )
          : AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 40),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).translate('content_load_failed'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }
}

