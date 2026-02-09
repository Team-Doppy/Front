import 'package:doppy/data/models/military_info_model.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 군인 정보 입력 - 입대 상태 선택 단계
class MilitaryStatusStep extends StatefulWidget {
  final MilitaryStatus? initialStatus;
  final Function(MilitaryStatus) onStatusSelected;

  const MilitaryStatusStep({
    super.key,
    this.initialStatus,
    required this.onStatusSelected,
  });

  @override
  State<MilitaryStatusStep> createState() => _MilitaryStatusStepState();
}

class _MilitaryStatusStepState extends State<MilitaryStatusStep> {
  late MilitaryStatus _selectedStatus;
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus ?? MilitaryStatus.afterEnlistment;
    _controller = FixedExtentScrollController(
      initialItem: MilitaryStatus.values.indexOf(_selectedStatus),
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '입대 상태를 선택하세요',
                style: LocaleTypography.setStyle(
                  context: context,
                  fontSize: 24,
                  color: AppColors.lightSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 40),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.lightSurface.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: CupertinoPicker(
                  scrollController: _controller,
                  itemExtent: 50,
                  diameterRatio: 0.8,
                  useMagnifier: false,
                  onSelectedItemChanged: (index) {
                    setState(() {
                      _selectedStatus = MilitaryStatus.values[index];
                    });
                    widget.onStatusSelected(_selectedStatus);
                  },
                  children:
                      MilitaryStatus.values.map((status) {
                        return Center(
                          child: Text(
                            status == MilitaryStatus.beforeEnlistment
                                ? '입대 전'
                                : '입대 후',
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
    );
  }
}
