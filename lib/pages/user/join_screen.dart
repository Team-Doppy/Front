import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/auth_service.dart';

enum AuthMode { login, signup }

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  _JoinScreenState createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  AuthMode? _selectedMode; // null이면 선택 화면
  int _currentStep = 0;
  final AuthService _authService = AuthService();

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
    if (_selectedMode == null) {
      return ['인증 방식 선택'];
    } else if (_selectedMode == AuthMode.login) {
      return ['로그인'];
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
              value:
                  _selectedMode == null
                      ? 0.25 // 선택 화면에서는 100% (1/1)
                      : (_currentStep + 1) /
                          _stepTitles.length, // 선택 후에는 현재 단계 / 전체 단계
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
            _selectedMode == null
                ? [_buildModeSelectionStep()]
                : _selectedMode == AuthMode.login
                ? [_buildModeSelectionStep(), _buildLoginStep()]
                : [
                  _buildModeSelectionStep(),
                  _buildIdStep(),
                  _buildPasswordStep(),
                  _buildConfirmPasswordStep(),
                  _buildCompleteStep(),
                ],
      ),
    );
  }

  Widget _buildModeSelectionStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            '환영합니다!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '도피 이용약관 확인하기 (개인정보 수집 동의)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 32),

          // 로그인 옵션
          _buildAuthOption(
            title: '로그인',
            subtitle: '기존 계정으로 로그인하세요',
            onTap: () {
              setState(() {
                _selectedMode = AuthMode.login;
                _currentStep = 1;
              });
            },
          ),

          SizedBox(height: 10),

          // 회원가입 옵션
          _buildAuthOption(
            title: '회원가입',
            subtitle: '새로운 계정을 만들어 시작하세요',
            onTap: () {
              setState(() {
                _selectedMode = AuthMode.signup;
                _currentStep = 1;
              });
            },
          ),

          Spacer(),
        ],
      ),
    );
  }

  Widget _buildAuthOption({
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
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
                size: 24,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            '로그인',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'ID와 비밀번호를 입력해주세요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 32),

          // ID 입력
          TextField(
            cursorColor: Theme.of(context).colorScheme.onSurface,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
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

          // 비밀번호 입력
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            cursorColor: Theme.of(context).colorScheme.onSurface,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
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
                borderSide: BorderSide.none,
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
          Spacer(),

          // 로그인 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
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
                        '로그인',
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

  Widget _buildIdStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 36),
          Text(
            'ID를 입력해주세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '내 계정 이름을 잘 지어볼까요?',
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
                  (_isIdDuplicateChecked && !_isIdAvailable
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
                onPressed: _isCheckingDuplicate ? null : _handleIdNext,
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
                        '회원가입 완료',
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
        // 첫 번째 단계(모드 선택)로 돌아가면 선택 초기화
        if (_currentStep == 0) {
          _selectedMode = null;
          _idController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _isIdDuplicateChecked = false;
          _isIdAvailable = false;
          _isPasswordValid = false;
          _isPasswordMatch = false;
        }
      });
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isCheckingDuplicate = true;
    });

    final id = _idController.text.trim();
    final pw = _passwordController.text;
    final region = context.read<LocaleProvider>().regionCode; // 'KR' or 'US'

    final success = await AuthProvider().login(id, pw, region: region);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } else {
      // 로그인 실패 시 사용자에게 피드백 제공
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('아이디 또는 비밀번호가 일치하지 않습니다.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }

    setState(() {
      _isCheckingDuplicate = false;
    });
  }

  void _completeSignup() async {
    // 회원가입 API 호출
    setState(() {
      _isCheckingDuplicate = true; // 로딩 상태로 재사용
    });

    try {
      final region = context.read<LocaleProvider>().regionCode; // 'KR' or 'US'

      final success = await _authService.register(
        username: _idController.text,
        password: _passwordController.text,
        alias: _idController.text, // username을 alias로 사용
        region: region,
      );

      if (success) {
        // 회원가입 성공
        _nextStep(); // 완료 화면으로 이동

        // 1초 후 스플래시 화면으로 이동 (자동 로그인 및 데이터 로드)
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          // 모든 화면을 제거하고 스플래시 화면으로 이동
          // 스플래시 화면에서 자동으로 로그인 시도 → 홈으로 이동
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
