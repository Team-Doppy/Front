import 'package:doppy/utils/text_bold_utils.dart';
import 'package:flutter/material.dart';

/// ✅ 입대 예정자 목표 및 걱정사항 입력 화면
class PreEnlistmentGoalsScreen extends StatefulWidget {
  const PreEnlistmentGoalsScreen({super.key});

  @override
  State<PreEnlistmentGoalsScreen> createState() =>
      _PreEnlistmentGoalsScreenState();
}

class _PreEnlistmentGoalsScreenState extends State<PreEnlistmentGoalsScreen> {
  final TextEditingController _goalsController = TextEditingController();
  final TextEditingController _worriesController = TextEditingController();
  final TextEditingController _postDischargeGoalsController =
      TextEditingController();

  @override
  void dispose() {
    _goalsController.dispose();
    _worriesController.dispose();
    _postDischargeGoalsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '입대 전에 꼭 답해보세요',
          style: LocaleTypography.style(
            context: context,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: onSurface,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 여러가지 목표
            _buildSection(
              context: context,
              title: '여러가지 목표',
              hint: '입대 전에 이루고 싶은 목표들을 적어보세요',
              controller: _goalsController,
              maxLines: 5,
            ),

            const SizedBox(height: 32),

            // ✅ 전역 후 목표
            _buildSection(
              context: context,
              title: '전역 후 목표',
              hint: '전역 후 이루고 싶은 목표들을 적어보세요',
              controller: _postDischargeGoalsController,
              maxLines: 5,
            ),

            const SizedBox(height: 32),

            // ✅ 가기 전에 제일 걱정되는 것
            _buildSection(
              context: context,
              title: '가기 전에 제일 걱정되는 것',
              hint: '입대 전 가장 걱정되는 것들을 적어보세요',
              controller: _worriesController,
              maxLines: 5,
            ),

            const SizedBox(height: 40),

            // ✅ 저장 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: 서버에 저장하는 로직 추가
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '저장하기',
                  style: LocaleTypography.style(
                    context: context,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required String hint,
    required TextEditingController controller,
    int maxLines = 3,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant = Theme.of(context).colorScheme.surfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: LocaleTypography.style(
            context: context,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: LocaleTypography.style(
              context: context,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: onSurface,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: LocaleTypography.style(
                context: context,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: onSurface.withOpacity(0.5),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }
}
