import 'dart:ui' as ui;
import 'package:doppy/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum ExitDecision { saveDraft, discard, cancel }

class SaveDraftOverlay extends StatefulWidget {
  const SaveDraftOverlay({super.key});

  @override
  State<SaveDraftOverlay> createState() => _SaveDraftOverlayState();
}

class _SaveDraftOverlayState extends State<SaveDraftOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // Blur + dim background
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  color: const ui.Color.fromARGB(182, 89, 89, 89),
                ),
              ),
            ), // 상단 닫기(X) 버튼
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),

            // Panel
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 320,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),

                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '작성 중인 내용을 임시저장할까요?',
                              style: TextStyle(
                                color: AppColors.darkTextSecondary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed:
                                    () => Navigator.of(
                                      context,
                                    ).pop(ExitDecision.saveDraft),
                                child: const Text(
                                  '임시저장',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.darkTextPrimary,
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed:
                                    () => Navigator.of(
                                      context,
                                    ).pop(ExitDecision.discard),
                                child: const Text('작성 취소'),
                              ),
                            ),
                          ],
                        ),
                      ),
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
}
