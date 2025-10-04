import 'package:doppy/data/services/account_manager_service.dart';
import 'package:doppy/data/services/user_service.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/account_context_service.dart';

class JoinScreen extends StatefulWidget {
  final bool isRedirectMode; // 새 계정 생성 모드인지 여부

  const JoinScreen({super.key, this.isRedirectMode = false});

  @override
  _JoinScreenState createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  int _currentStep = 0;
  final AuthService _authService = AuthService();
  bool _isLinkMode = false; // 내부 상태로 관리

  // 각 단계별 컨트롤러들
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // 각 단계별 상태
  bool _isIdDuplicateChecked = false;
  bool _isIdAvailable = false;
  bool _isPasswordValid = false;
  bool _isPasswordMatch = false;
  bool _isCheckingDuplicate = false;

  // 비밀번호 표시 여부
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  List<String> get _stepTitles {
    if (widget.isRedirectMode) {
      return ['계정 선택', 'ID 입력', '비밀번호 설정', '비밀번호 확인', '완료'];
    } else if (_isLinkMode) {
      return ['기존 계정 로그인', '연동 완료'];
    }
    return ['ID 입력', '비밀번호 설정', '비밀번호 확인', '완료'];
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.isRedirectMode ? '계정 관리' : (_isLinkMode ? '기존 계정 연동' : '회원가입'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: GestureDetector(
          onTap: () {
            if (_currentStep > 0) {
              _previousStep();
            } else {
              Navigator.pop(context);
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 20, top: 22),
            child: Text(
              '이전',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(1),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        bottom: PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / _stepTitles.length,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentStep,
        children:
            _isLinkMode
                ? [_buildLoginStep(), _buildLinkCompleteStep()]
                : widget.isRedirectMode
                ? [
                  _buildAccountSelectionStep(),
                  _buildIdStep(),
                  _buildPasswordStep(),
                  _buildConfirmPasswordStep(),
                  _buildCompleteStep(),
                ]
                : [
                  _buildIdStep(),
                  _buildPasswordStep(),
                  _buildConfirmPasswordStep(),
                  _buildCompleteStep(),
                ],
      ),
    );
  }

  /// 계정 선택 단계 (리다이렉트 모드에서만 사용)
  Widget _buildAccountSelectionStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            '계정을 선택하세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '새 계정을 생성하거나 기존 계정을 연동하세요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 40),

          // 새 계정 생성 옵션
          _buildAccountOption(
            icon: Icons.person_add_rounded,
            title: '새 계정 생성',
            subtitle: '새로운 계정을 만들어 시작하세요',
            onTap: () {
              setState(() {
                _isLinkMode = false; // 새 계정 생성 모드로 설정
                _currentStep = 0;
                if (widget.isRedirectMode) {
                  // 다음 단계로 이동
                  _nextStep();
                }
              });
            },
          ),

          SizedBox(height: 16),

          // 기존 계정 연동 옵션
          _buildAccountOption(
            icon: Icons.login_rounded,
            title: '기존 계정 연동',
            subtitle: '이미 있는 계정으로 로그인하세요',
            onTap: () {
              // 바텀시트 내부에서 기존 계정 연동 모드로 전환
              setState(() {
                _isLinkMode = true; // 기존 계정 연동 모드 활성화
                _currentStep = 0;
                // 첫 번째 페이지로 이동 (PageView가 재빌드되므로 자동으로 0페이지로 이동)
              });
            },
          ),
        ],
      ),
    );
  }

  /// 계정 옵션 빌드
  Widget _buildAccountOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            _isLinkMode ? '기존 계정 ID를 입력해주세요' : 'ID를 입력해주세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _isLinkMode ? '연동하려는 기존 계정의 ID를 입력하세요.' : '내 계정 이름을 잘 지어볼까요?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            cursorColor: Theme.of(context).colorScheme.onSurface,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
            controller: _idController,
            decoration: InputDecoration(
              hintText: 'doppy_official',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
              prefixIconColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.8),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              errorBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              errorStyle: TextStyle(
                color: Theme.of(context).colorScheme.error.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              errorText:
                  _isLinkMode
                      ? null
                      : (_isIdDuplicateChecked && !_isIdAvailable
                          ? '이미 사용 중인 ID에요.'
                          : null),
              suffixIcon:
                  _idController.text.isNotEmpty
                      ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                            _isIdDuplicateChecked = false;
                          });
                        },
                      )
                      : null,
            ),
            onChanged: (value) {
              setState(() {
                _isIdDuplicateChecked = false;
              });
            },
          ),
          SizedBox(height: 16),

          Spacer(),
          // 다음 버튼 (중복확인 포함)
          if (_idController.text.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    _isCheckingDuplicate
                        ? null
                        : (_isLinkMode ? _nextStep : _handleIdNext),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child:
                    _isCheckingDuplicate
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : Text(
                          '다음',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.surface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            '비밀번호를 설정해주세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '안전한 6자리 이상 비밀번호를 설정해볼까요?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: '비밀번호를 입력하세요',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            onChanged: (value) {
              setState(() {
                _isPasswordValid = _validatePassword(value);
              });
            },
          ),
          SizedBox(height: 16),
          if (_passwordController.text.isNotEmpty) ...[
            _buildPasswordRequirement(
              '6자 이상',
              _passwordController.text.length >= 6,
            ),
            _buildPasswordRequirement(
              '영문 포함',
              RegExp(r'[a-zA-Z]').hasMatch(_passwordController.text),
            ),
            _buildPasswordRequirement(
              '숫자 포함',
              RegExp(r'[0-9]').hasMatch(_passwordController.text),
            ),
          ],
          Spacer(),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isPasswordValid ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isPasswordValid
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                '다음',
                style: TextStyle(
                  color:
                      _isPasswordValid
                          ? Theme.of(context).colorScheme.surface
                          : Colors.grey[600],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordRequirement(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check : Icons.close,
            size: 16,
            color:
                isValid
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.4),
          ),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color:
                  isValid
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmPasswordStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            '비밀번호를 다시 입력해주세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '보안을 위해 비밀번호를 한 번 더 입력해주세요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            cursorColor: Theme.of(context).colorScheme.onSurface,
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              hintText: '비밀번호를 다시 입력하세요',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide:
                    _isPasswordMatch &&
                            _confirmPasswordController.text.isNotEmpty
                        ? BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                        : BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ),
            onChanged: (value) {
              setState(() {
                _isPasswordMatch = value == _passwordController.text;
              });
            },
          ),
          SizedBox(height: 16),
          Spacer(),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed:
                  (_isPasswordMatch && !_isCheckingDuplicate)
                      ? _completeSignup
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isPasswordMatch
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child:
                  _isCheckingDuplicate
                      ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.surface,
                          ),
                        ),
                      )
                      : Text(
                        widget.isRedirectMode ? '새 계정 생성' : '회원가입 완료',
                        style: TextStyle(
                          color:
                              _isPasswordMatch
                                  ? Theme.of(context).colorScheme.surface
                                  : Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle,
            size: 100,
            color: Theme.of(context).colorScheme.primary,
          ),
          SizedBox(height: 24),
          Text(
            '회원가입이 완료되었습니다!',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(
            '환영합니다! 이제 서비스를 이용하실 수 있습니다.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 48),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _validatePassword(String password) {
    return password.length >= 6 &&
        RegExp(r'[a-zA-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  void _handleIdNext() {
    if (!_isIdDuplicateChecked) {
      // 중복확인 먼저 수행 (자동으로 다음 단계 진행)
      _checkIdDuplicate();
    } else if (_isIdAvailable) {
      // 중복확인 완료되고 사용 가능하면 다음 단계로
      _nextStep();
    }
  }

  void _checkIdDuplicate() async {
    print('[-] [JoinScreen] _checkIdDuplicate');
    setState(() {
      _isCheckingDuplicate = true;
    });

    try {
      final isAvailable = await _authService.checkUsernameDuplicate(
        _idController.text,
      );

      print('[-] [JoinScreen] _checkIdDuplicate: $isAvailable');

      setState(() {
        _isIdDuplicateChecked = true;
        _isIdAvailable = isAvailable;
        _isCheckingDuplicate = false;
      });

      // 사용 가능한 ID라면 바로 다음 단계로
      if (isAvailable) {
        _nextStep();
      }
    } catch (e) {
      setState(() {
        _isIdDuplicateChecked = true;
        _isIdAvailable = false;
        _isCheckingDuplicate = false;
      });

      // 에러 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('중복확인 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _nextStep() {
    if (_currentStep < _stepTitles.length - 1) {
      setState(() {
        _currentStep++;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  /// 기존 계정 로그인 단계 (ID + 비밀번호)
  Widget _buildLoginStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            '기존 계정 정보를 입력해주세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '연동하려는 기존 계정의 ID와 비밀번호를 입력하세요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 32),

          // ID 입력 필드
          TextField(
            controller: _idController,
            cursorColor: Theme.of(context).colorScheme.onSurface,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'doppy_official',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
              prefixIconColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.8),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              suffixIcon:
                  _idController.text.isNotEmpty
                      ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                          });
                        },
                      )
                      : null,
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),

          SizedBox(height: 16),

          // 비밀번호 입력 필드
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            cursorColor: Theme.of(context).colorScheme.onSurface,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: '비밀번호를 입력하세요',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceVariant,
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
              prefixIconColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.8),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),

          SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (_idController.text.isNotEmpty &&
                          _passwordController.text.isNotEmpty &&
                          !_isCheckingDuplicate)
                      ? _handleLogin
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    (_idController.text.isNotEmpty &&
                            _passwordController.text.isNotEmpty)
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child:
                  _isCheckingDuplicate
                      ? CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.surface,
                        strokeWidth: 2,
                      )
                      : Text(
                        '연동하기',
                        style: TextStyle(
                          color:
                              (_idController.text.isNotEmpty &&
                                      _passwordController.text.isNotEmpty)
                                  ? Theme.of(context).colorScheme.surface
                                  : Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  /// 기존 계정 연동 완료 단계
  Widget _buildLinkCompleteStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 24),
          Text(
            '계정을 연동하고 있어요',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 24),

          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ],
      ),
    );
  }

  /// 기존 계정 로그인 처리
  void _handleLogin() async {
    setState(() {
      _isCheckingDuplicate = true;
    });

    try {
      // 이미 존재하는 계정인지 확인 (입력한 ID 기준 선제 차단)
      final existingLinkedAccount = await AccountManagerService.getAccount(
        _idController.text,
      );
      if (existingLinkedAccount != null) {
        // 이미 연동된 계정
        setState(() {
          _isCheckingDuplicate = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '이미 연동되어 있어요',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          );
        }
        return; // 중복 시 종료
      }

      // 0) 새 계정으로 이동하기 전에, 현재 사용 중인 계정을 반드시 저장/업데이트(업서트)
      try {
        final prevUsername = await _authService.getUsername();
        final prevToken = await _authService.getToken();
        final prevRefresh = await _authService.getRefreshToken();

        final prevUserProvider = context.read<UserProvider>();
        final prevAlias =
            prevUserProvider.currentUser?.alias ?? prevUsername ?? '';
        final prevProfileImageUrl =
            prevUserProvider.currentUser?.profileImageUrl ?? '';

        if (prevUsername != null && prevToken != null && prevRefresh != null) {
          await AccountManagerService.addAccount(
            AccountInfo(
              username: prevUsername,
              alias: prevAlias,
              profileImageUrl: prevProfileImageUrl,
              token: prevToken,
              refreshToken: prevRefresh,
            ),
          );
        }
      } catch (_) {}

      // 1) 로그인 시도 (계정 연동용 - Provider 상태 변경 없이, 토큰 저장만 수행)
      final loginResponse = await _authService.login(
        _idController.text,
        _passwordController.text,
        setAsCurrent: false,
      );

      if (loginResponse == null) {
        // 로그인 실패
        setState(() {
          _isCheckingDuplicate = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '로그인에 실패했습니다 다시 시도해주세요',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      // 2) 사용자 정보 조회하여 alias / profileImageUrl 확보 (빈 값 방지)
      String profileImageUrl = '';
      String alias = '';
      try {
        final userInfo = await UserService().getMyProfile();
        print('');
        print('');
        print('[-] [JoinScreen] userInfo: $userInfo');
        print('');
        print('');

        if ((userInfo.profileImageUrl ?? '').isNotEmpty) {
          profileImageUrl = userInfo.profileImageUrl!;
        }

        if ((userInfo.alias ?? '').isNotEmpty) alias = userInfo.alias!;
      } catch (_) {}
      print('');
      print('');
      print('[-] [JoinScreen] profileImageUrl: $profileImageUrl');
      print('');
      print('');

      // 3) AccountManagerService에 계정 정보 저장/업데이트 (업서트)
      final accountInfo = AccountInfo(
        username: loginResponse.username,
        alias: alias,
        profileImageUrl: profileImageUrl,
        token: loginResponse.token,
        refreshToken: loginResponse.refreshToken,
      );

      await AccountManagerService.addAccount(accountInfo);

      // 4) 진행 화면으로 전환 후, 현재 계정으로 설정 + 컨텍스트 적용
      if (mounted) {
        _nextStep();
      }
      await AccountManagerService.setCurrentAccount(loginResponse.username);
      await AccountContextService.applyCurrentAccount(context);

      if (mounted) {
        setState(() {
          _isCheckingDuplicate = false;
        });
        await Future.delayed(const Duration(milliseconds: 1000));

        if (mounted) {
          Navigator.pop(context); // 바텀시트 닫기
        }
      }
    } catch (e) {
      setState(() {
        _isCheckingDuplicate = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '로그인에 실패했습니다 다시 시도해주세요',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _completeSignup() async {
    // 회원가입 API 호출
    setState(() {
      _isCheckingDuplicate = true; // 로딩 상태로 재사용
    });

    try {
      final success = await _authService.register(
        username: _idController.text,
        password: _passwordController.text,
        alias: _idController.text, // username을 alias로 사용
      );

      if (success) {
        // 회원가입 성공: 로그인은 이미 처리됨 → 현재 계정 적용 및 병렬 로드
        _nextStep(); // 진행 화면
        await AccountContextService.applyCurrentAccount(context);
        if (mounted) {
          Navigator.pop(context); // 바텀시트 닫기
        }
      } else {
        // 회원가입 실패
        setState(() {
          _isCheckingDuplicate = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '회원가입에 실패했습니다. 다시 시도해주세요.',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isCheckingDuplicate = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '회원가입 중 오류가 발생했습니다: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
