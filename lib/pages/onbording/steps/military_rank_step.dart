import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 군인 정보 입력 - 현재 계급 선택 단계
class MilitaryRankStep extends StatefulWidget {
  final MilitaryRank? initialRank;
  final Function(MilitaryRank) onRankSelected;
  final VoidCallback? onConfirm;
  final VoidCallback? onBack;

  const MilitaryRankStep({
    super.key,
    this.initialRank,
    required this.onRankSelected,
    this.onConfirm,
    this.onBack,
  });

  @override
  State<MilitaryRankStep> createState() => _MilitaryRankStepState();
}

class _MilitaryRankStepState extends State<MilitaryRankStep> {
  late MilitaryRank _selectedRank;
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _selectedRank = widget.initialRank ?? MilitaryRank.trainee;
    _controller = FixedExtentScrollController(
      initialItem: MilitaryRank.values.indexOf(_selectedRank),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // 뒤로가기 버튼
            if (widget.onBack != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    color: AppColors.lightSurfaceVariant,
                    onPressed: widget.onBack,
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '현재 계급을 선택하세요',
                      style: LocaleTypography.setStyle(
                        context: context,
                        fontSize: 24,
                        color: AppColors.lightSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      height: 200,
                      child: CupertinoPicker(
                        scrollController: _controller,
                        itemExtent: 50,
                        diameterRatio: 1.0, // 서큘러 리스트처럼 보이도록
                        useMagnifier: true, // 확대 효과
                        magnification: 1.1,
                        squeeze: 0.8,
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _selectedRank = MilitaryRank.values[index];
                          });
                          widget.onRankSelected(_selectedRank);
                        },
                        children:
                            MilitaryRank.values.map((rank) {
                              return Center(
                                child: Text(
                                  rank.displayName,
                                  style: LocaleTypography.setStyle(
                                    context: context,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.lightSurfaceVariant,
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 하단 확인 버튼
            Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                top: 16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: AppColors.lightSurfaceVariant,
                  onPressed:
                      widget.onConfirm ??
                      () {
                        widget.onRankSelected(_selectedRank);
                      },
                  child: Text(
                    '확인',
                    style: LocaleTypography.setStyle(
                      context: context,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkSurface,
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
