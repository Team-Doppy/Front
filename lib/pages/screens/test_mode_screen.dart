import 'package:flutter/material.dart';
import 'package:doppy/utils/week_utils.dart';
import 'package:doppy/theme/app_colors.dart';
import 'package:intl/intl.dart';

/// 통합 테스트 모드 설정 화면
/// 현재 주차와 가입일을 설정하여 다양한 시나리오를 테스트할 수 있습니다.
class TestModeScreen extends StatefulWidget {
  const TestModeScreen({super.key});

  @override
  State<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends State<TestModeScreen> {
  DateTime? _testCurrentDate;
  DateTime? _testSignupDate;
  bool _isTestModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadTestModeState();
  }

  void _loadTestModeState() {
    // 테스트 모드 상태 확인 (간단한 구현)
    // 실제로는 SharedPreferences나 Provider를 사용할 수 있습니다
    setState(() {
      _isTestModeEnabled = false;
      _testCurrentDate = null;
      _testSignupDate = null;
    });
  }

  Future<void> _selectCurrentDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _testCurrentDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) {
      setState(() {
        _testCurrentDate = picked;
      });
    }
  }

  Future<void> _selectSignupDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _testSignupDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) {
      setState(() {
        _testSignupDate = picked;
      });
    }
  }

  void _applyTestMode() {
    if (_isTestModeEnabled) {
      WeekUtils.setTestCurrentDate(_testCurrentDate);
      WeekUtils.setTestSignupDate(_testSignupDate);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('테스트 모드가 활성화되었습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      WeekUtils.resetTestMode();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('테스트 모드가 비활성화되었습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetTestMode() {
    setState(() {
      _isTestModeEnabled = false;
      _testCurrentDate = null;
      _testSignupDate = null;
    });
    WeekUtils.resetTestMode();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('테스트 모드가 초기화되었습니다.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy년 MM월 dd일', 'ko_KR');
    final currentYear = WeekUtils.getCurrentYear();
    final currentWeek = WeekUtils.getCurrentWeekNumber();

    return Scaffold(
      appBar: AppBar(
        title: const Text('통합 테스트 모드'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 현재 상태 표시
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 상태',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('현재 연도: $currentYear'),
                  Text('현재 주차: $currentWeek'),
                  if (_testCurrentDate != null)
                    Text(
                      '테스트 기준일: ${dateFormat.format(_testCurrentDate!)}',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (_testSignupDate != null)
                    Text(
                      '테스트 가입일: ${dateFormat.format(_testSignupDate!)}',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 테스트 모드 활성화 토글
          SwitchListTile(
            title: const Text('테스트 모드 활성화'),
            subtitle: const Text('현재 주차와 가입일을 오버라이드합니다'),
            value: _isTestModeEnabled,
            onChanged: (value) {
              setState(() {
                _isTestModeEnabled = value;
              });
              if (value) {
                _applyTestMode();
              } else {
                WeekUtils.resetTestMode();
              }
            },
          ),
          const SizedBox(height: 16),

          // 현재 주차 설정
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              title: const Text('현재 주차 설정'),
              subtitle: Text(
                _testCurrentDate != null
                    ? dateFormat.format(_testCurrentDate!)
                    : '설정하지 않음 (실제 날짜 사용)',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectCurrentDate,
            ),
          ),
          const SizedBox(height: 8),

          // 가입일 설정
          Card(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              title: const Text('가입일 설정'),
              subtitle: Text(
                _testSignupDate != null
                    ? dateFormat.format(_testSignupDate!)
                    : '설정하지 않음 (실제 가입일 사용)',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectSignupDate,
            ),
          ),
          const SizedBox(height: 16),

          // 적용 버튼
          ElevatedButton(
            onPressed: _isTestModeEnabled ? _applyTestMode : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              '테스트 모드 적용',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),

          // 초기화 버튼
          OutlinedButton(
            onPressed: _resetTestMode,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('테스트 모드 초기화'),
          ),
          const SizedBox(height: 16),

          // 안내 메시지
          Card(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안내',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• 테스트 모드를 활성화하면 앱 전체에서 설정한 날짜가 사용됩니다.\n'
                    '• 코치마크, 주차 계산, 가입일 체크 등 모든 기능이 테스트 날짜를 기준으로 작동합니다.\n'
                    '• 테스트 완료 후 반드시 초기화하세요.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
