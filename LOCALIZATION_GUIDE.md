# 다국어(i18n) 구현 가이드

## ✅ 완료된 작업

### 1. LocaleProvider 생성
- 파일: `lib/providers/locale_provider.dart`
- 기능:
  - 시스템 언어 자동 감지
  - 언어 변경 및 저장 (SharedPreferences)
  - JWT용 region 코드 제공 ('KR', 'US')

### 2. AppLocalizations 생성
- 파일: `lib/l10n/app_localizations.dart`
- 기능:
  - 한국어/영어 번역 맵
  - `context.tr('key')` 확장 메서드

### 3. AuthService/AuthProvider 업데이트
- `login()`, `register()` 메서드에 `region` 파라미터 추가
- JWT 토큰 발행 시 region 필드 포함

### 4. 설정 화면 구현
- 파일: `lib/pages/user/setting_screen.dart`
- 기능:
  - 언어 선택 다이얼로그
  - 현재 언어 표시

---

## 🚀 적용 방법

### main.dart 설정

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:doppy/providers/locale_provider.dart';
import 'package:doppy/l10n/app_localizations.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        // ... 기존 providers
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return MaterialApp(
          // 다국어 설정
          locale: localeProvider.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          
          // ... 기존 설정
        );
      },
    );
  }
}
```

---

## 📝 사용법

### 1. UI 텍스트 번역

```dart
// 방법 1: Extension 사용 (권장)
Text(context.tr('settings'))

// 방법 2: AppLocalizations 직접 사용
Text(AppLocalizations.of(context).translate('settings'))
```

### 2. 로그인/회원가입 시 region 전달

```dart
// 로그인
final localeProvider = context.read<LocaleProvider>();
await AuthProvider().login(
  username,
  password,
  region: localeProvider.regionCode, // 'KR' or 'US'
);

// 회원가입
await AuthService().register(
  username: username,
  password: password,
  region: localeProvider.regionCode,
);
```

### 3. 언어 변경

```dart
// 한국어로 변경
context.read<LocaleProvider>().setKorean();

// 영어로 변경
context.read<LocaleProvider>().setEnglish();

// 토글
context.read<LocaleProvider>().toggleLocale();
```

---

## 🌐 번역 추가 방법

`lib/l10n/app_localizations.dart` 파일의 `_localizedValues` 맵에 추가:

```dart
static final Map<String, Map<String, String>> _localizedValues = {
  'ko': {
    'new_key': '새로운 텍스트',
  },
  'en': {
    'new_key': 'New Text',
  },
};
```

---

## 🎯 적용해야 할 화면들

아래 화면들의 하드코딩된 텍스트를 `context.tr()`로 변경:

1. **설정 화면** (`setting_screen.dart`) ✅ 완료
2. **로그인/회원가입 화면**
3. **포스트 리더 화면**
4. **댓글 화면**
5. **프로필 화면**
6. **피드 화면**
7. **검색 화면**

---

## 📱 테스트 방법

1. 설정 > 언어 설정에서 언어 변경
2. 앱 전체 UI가 선택한 언어로 변경되는지 확인
3. 로그인/회원가입 시 서버로 올바른 region 코드가 전송되는지 확인
4. 앱 재시작 시 선택한 언어가 유지되는지 확인

---

## 🔧 주의사항

1. **모든 하드코딩 제거**: '설정', '로그아웃' 등 → `context.tr('settings')`, `context.tr('logout')`
2. **일관성 유지**: 동일한 의미는 동일한 키 사용
3. **키 네이밍**: snake_case 사용 (예: `language_settings`)
4. **Flutter 재시작**: 언어 변경 후 hot reload가 아닌 hot restart 필요

---

## 🎨 추가 개선 사항 (선택)

1. **ARB 파일 사용**: 더 체계적인 번역 관리
2. **Intl 패키지**: 날짜, 숫자 포맷팅
3. **플러럴 지원**: 복수형 처리
4. **컨텍스트 번역**: 같은 단어의 다른 의미 구분

---

## 🐛 문제 해결

### "AppLocalizations.of() called with a context that does not contain a Localizations widget"
- main.dart에 `localizationsDelegates` 추가 필요

### 언어 변경이 즉시 반영되지 않음
- `Consumer<LocaleProvider>`로 MaterialApp 감싸기
- Hot restart 필요

### 시스템 언어가 감지되지 않음
- `LocaleProvider` 생성자에서 자동으로 감지됨
- 로그 확인: `[LocaleProvider] 시스템 언어 감지: ko`

