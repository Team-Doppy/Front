# FCM 토큰 관리 전체 정리

## 📋 목차
1. [토큰 갱신 vs 재발급](#토큰-갱신-vs-재발급)
2. [FCM 토큰 처리 시점별 정리](#fcm-토큰-처리-시점별-정리)
3. [특수 케이스](#특수-케이스)
4. [DeviceId 관리](#deviceid-관리)

---

## 🔄 토큰 갱신 vs 재발급

### 토큰 갱신 (Token Refresh)
**Firebase가 자동으로 수행하는 작업**
- **시점**: Firebase SDK가 내부적으로 토큰을 갱신할 때
- **트리거**: 앱 재설치, 앱 데이터 삭제, 토큰 만료 등
- **처리**: `onTokenRefresh` 리스너가 자동 호출됨
- **동작**:
  1. Firebase가 새 토큰 발급
  2. `onTokenRefresh` 리스너 실행
  3. 캐시된 `_fcmToken` 업데이트
  4. **자동으로 서버에 전송** (`syncFcmTokenAndSettings()`)

```dart
// FcmService.onTokenRefresh 리스너
_firebaseMessaging.onTokenRefresh.listen((newToken) async {
  _fcmToken = newToken;
  await authService.syncFcmTokenAndSettings(); // 자동 서버 동기화
});
```

### 토큰 재발급 (Token Refresh/Re-issue)
**앱이 수동으로 수행하는 작업**
- **시점**: 토큰이 무효하다고 감지될 때
- **트리거**: `checkAndRefreshTokenIfNeeded()` 호출 시
- **조건**:
  - 알림 권한이 있어야 함
  - 캐시된 토큰과 실제 토큰이 불일치
  - 토큰이 null이거나 비어있음
- **동작**:
  1. `refreshTokenIfNeeded()` 호출
  2. 캐시 초기화 (`_fcmToken = null`)
  3. `getToken(forceRefresh: true)` 호출하여 새 토큰 발급
  4. 서버에 전송 필요 (호출한 곳에서 처리)

---

## 🕐 FCM 토큰 처리 시점별 정리

### 1. 앱 시작 시 (SplashScreen)
**파일**: `lib/pages/screens/splash_screen.dart`
**호출**: `_checkAndSyncFcmToken()` → `syncFcmTokenAndSettings()`

**처리 순서**:
1. 로그인 상태 확인 (토큰이 유효한 경우에만)
2. FCM 토큰 검사 및 필요시 재발급
3. 서버에 전송 (deviceId + fcmToken)
4. 비동기 처리 (앱 시작을 막지 않음)

**특징**:
- 앱이 시작될 때마다 실행
- 토큰이 만료되었거나 변경되었으면 자동 재발급 및 서버 동기화

---

### 2. 로그인 시
**파일**: `lib/data/services/auth_service.dart`
**호출**: `login()` → `_sendFcmTokenToServer()`

**처리 순서**:
1. 로그인 성공 후
2. 알림 권한 확인
   - 권한 없으면: 서버 설정 OFF로 동기화 (`_syncNotificationSettingsOnDenied()`)
   - 권한 있으면: 계속 진행
3. FCM 토큰 검사 및 필요시 재발급 (`checkAndRefreshTokenIfNeeded()`)
4. 토큰이 없으면 발급 시도 (`getToken()`)
5. DeviceId 가져오기 (없으면 생성, 기존 것은 유지)
6. 서버에 전송 (`POST /api/fcm/tokens`)
   - Body: `{ deviceId, token }`

**특징**:
- 로그인할 때마다 실행
- DeviceId는 항상 동일하게 유지 (SharedPreferences에 저장)

---

### 3. 로그아웃 시
**파일**: `lib/data/services/auth_service.dart`
**호출**: `logout()` → `fcmService.clearToken()`

**처리 순서**:
1. FCM 토큰 메모리 캐시 초기화 (`_fcmToken = null`)
2. 인증 토큰 삭제
3. 사용자명 삭제

**특징**:
- 로컬 캐시만 초기화 (서버의 FCM 토큰은 유지됨)
- 실제로는 서버에서 FCM 토큰을 삭제해야 하지만 현재는 클라이언트만 처리
- 다음 로그인 시 새 토큰이 서버에 전송됨

---

### 4. 회원 탈퇴 시
**파일**: `lib/pages/components/account_deletion_confirm.dart`
**호출**: `_handleAccountDeletion()` → `UserService.deleteAccount()`

**처리 순서**:
1. Firebase Firestore에 탈퇴 이유 저장
2. 회원 탈퇴 API 호출 (`DELETE /api/users/account`)
3. 로그아웃 처리 (`AuthProvider().logout()`)
4. 로그아웃 시 FCM 토큰 초기화 (`clearToken()`)

**특징**:
- 탈퇴 이유는 Firebase에 저장 (서버 API 호출 없음)
- 서버 API에서 계정 삭제 시 관련 FCM 토큰도 삭제되어야 함 (서버 측 처리)
- 클라이언트는 로컬 캐시만 초기화

**⚠️ 주의사항**:
- 서버에서 회원 탈퇴 시 해당 사용자의 모든 FCM 토큰을 삭제해야 함
- 현재 클라이언트는 로컬 캐시만 초기화함

---

### 5. 앱 삭제 시
**현재 구현**: 별도 처리 없음

**예상 동작**:
1. 앱이 완전히 삭제되면 모든 로컬 데이터 제거
   - SharedPreferences (deviceId 포함)
   - FlutterSecureStorage (인증 토큰 포함)
   - FCM 토큰 캐시
2. 서버에는 FCM 토큰이 남아있을 수 있음
   - 서버 측에서 오래된 토큰 정리 필요
   - 또는 서버에서 푸시 발송 시 실패 토큰 정리

**⚠️ 개선 필요사항**:
- 서버에서 오래된 FCM 토큰 자동 정리 로직 필요
- 또는 주기적으로 토큰 유효성 검증

---

### 6. 포그라운드 전환 시
**파일**: `lib/main.dart`
**호출**: `didChangeAppLifecycleState()` → `_checkAndSyncFcmTokenOnForeground()`

**처리 순서**:
1. 앱이 백그라운드에서 포그라운드로 전환될 때
2. 로그인 상태 확인
3. FCM 토큰 검사 및 필요시 재발급
4. 서버에 전송 (`syncFcmTokenAndSettings()`)

**특징**:
- 비동기 처리 (UI를 막지 않음)
- 백그라운드에서 포그라운드로 전환될 때마다 실행

---

### 7. 알림 설정 변경 시
**파일**: `lib/pages/screens/setting_screen.dart`
**호출**: `_toggleNotification()` → `syncFcmTokenAndSettings()`

**처리 순서**:
1. 서버 설정 변경 (ON/OFF 토글)
2. FCM 토큰 검사 및 필요시 재발급
3. 서버에 전송

**특징**:
- 알림을 켠 경우: 토큰 검사 후 서버 전송
- 알림을 끈 경우: 서버 설정 동기화 (권한 확인)
- 권한이 없으면 서버 설정도 OFF로 동기화

---

### 8. Firebase 자동 토큰 갱신 시
**파일**: `lib/data/services/fcm_service.dart`
**호출**: `onTokenRefresh` 리스너 (Firebase가 자동 호출)

**처리 순서**:
1. Firebase가 새 토큰 발급 (앱 재설치, 데이터 삭제 등)
2. `onTokenRefresh` 리스너 실행
3. 캐시된 `_fcmToken` 업데이트
4. **자동으로 서버에 전송** (`syncFcmTokenAndSettings()`)

**특징**:
- Firebase SDK가 자동으로 호출
- 앱이 실행 중일 때만 동작
- 앱이 종료된 상태에서는 동작하지 않음 (다음 시작 시 처리)

---

## 🔍 특수 케이스

### 케이스 1: 알림 권한 없음
**상황**: 사용자가 알림 권한을 거부한 경우

**처리**:
1. FCM 토큰 발급 불가 (`getToken()` → `null` 반환)
2. 서버 전송 건너뜀
3. 서버 설정 OFF로 동기화 (`_syncNotificationSettingsOnDenied()`)
   - `notificationEnabled` → `false`
   - `marketingConsent` → `false`

**결과**: 서버에 FCM 토큰이 없음 (권한 허용 전까지)

---

### 케이스 2: 토큰 불일치 감지
**상황**: 캐시된 토큰과 실제 토큰이 다른 경우

**처리**:
1. `isTokenValid()`에서 불일치 감지
2. 캐시된 토큰을 실제 토큰으로 업데이트 (`_fcmToken = currentToken`)
3. `false` 반환 (재발급 필요)
4. `checkAndRefreshTokenIfNeeded()`에서 재발급 시도
5. 새 토큰 서버에 전송

**결과**: 서버에 최신 토큰이 저장됨

---

### 케이스 3: 토큰 만료/무효
**상황**: FCM 토큰이 만료되었거나 무효한 경우

**처리**:
1. `isTokenValid()`에서 무효 감지
2. `checkAndRefreshTokenIfNeeded()` 호출
3. `refreshTokenIfNeeded()` 호출
4. 새 토큰 발급 (`getToken(forceRefresh: true)`)
5. 서버에 전송

**결과**: 새 토큰이 서버에 저장됨

---

### 케이스 4: 앱 재설치
**상황**: 사용자가 앱을 삭제하고 재설치한 경우

**처리**:
1. Firebase가 새 FCM 토큰 발급
2. `onTokenRefresh` 리스너 실행 (앱 실행 중일 때)
3. 자동으로 서버에 전송
4. 또는 다음 앱 시작 시 `syncFcmTokenAndSettings()` 실행

**결과**: 새 토큰이 서버에 저장됨 (이전 토큰은 무효)

**⚠️ 주의사항**:
- 서버에서 이전 토큰 정리 필요
- DeviceId는 새로 생성됨 (SharedPreferences 초기화)

---

### 케이스 5: 여러 기기에서 로그인
**상황**: 같은 계정으로 여러 기기에서 로그인

**처리**:
1. 각 기기마다 고유한 DeviceId 생성 (첫 로그인 시)
2. 각 기기마다 고유한 FCM 토큰 발급
3. 서버에 각각 저장 (`deviceId` + `token` 쌍)

**결과**: 서버에 여러 기기의 FCM 토큰이 저장됨

---

### 케이스 6: 로그아웃 후 재로그인
**상황**: 로그아웃 후 다시 로그인

**처리**:
1. 로그아웃: FCM 토큰 캐시 초기화
2. 재로그인: 새 FCM 토큰 발급 (또는 기존 토큰 재사용)
3. 서버에 전송

**결과**: 서버에 FCM 토큰이 업데이트됨

---

### 케이스 7: 회원 탈퇴
**상황**: 사용자가 계정을 탈퇴

**처리**:
1. Firebase Firestore에 탈퇴 이유 저장
2. 회원 탈퇴 API 호출
3. 로그아웃 처리 (FCM 토큰 캐시 초기화)
4. **서버에서 계정 삭제 시 관련 FCM 토큰도 삭제되어야 함** (서버 측 처리)

**결과**: 
- 클라이언트: FCM 토큰 캐시 초기화
- 서버: 계정 및 FCM 토큰 삭제 (서버 측에서 처리 필요)

---

## 📱 DeviceId 관리

### DeviceId 생성 및 저장
**파일**: `lib/data/services/auth_service.dart`
**메서드**: `getDeviceId()`

**특징**:
- SharedPreferences에 저장 (`'device_id'` 키)
- UUID v4로 생성
- **앱을 삭제하지 않는 한 항상 동일**
- 같은 기기에서는 항상 같은 DeviceId 사용

**저장 위치**: `SharedPreferences`
**생성 시점**: 첫 로그인 시 또는 FCM 토큰 전송 시

---

### DeviceId와 FCM 토큰 관계
- **1 DeviceId = 1 FCM Token** (일반적으로)
- 같은 기기에서는 DeviceId가 유지됨
- FCM 토큰은 변경될 수 있음 (갱신, 재발급 등)
- 서버는 DeviceId를 기준으로 FCM 토큰을 관리

---

## 📊 전체 플로우 요약

```
┌─────────────────────────────────────────────────────────────┐
│                    FCM 토큰 라이프사이클                      │
└─────────────────────────────────────────────────────────────┘

1. 앱 시작
   └─> 토큰 검사 → 필요시 재발급 → 서버 전송

2. 로그인
   └─> 토큰 검사 → 필요시 재발급 → DeviceId 가져오기 → 서버 전송

3. 로그아웃
   └─> FCM 토큰 캐시 초기화 (서버는 유지)

4. 회원 탈퇴
   └─> 탈퇴 이유 Firebase 저장 → 탈퇴 API 호출 → 로그아웃
       → 서버에서 계정 및 FCM 토큰 삭제 (서버 측 처리)

5. 포그라운드 전환
   └─> 토큰 검사 → 필요시 재발급 → 서버 전송

6. 알림 설정 변경
   └─> 서버 설정 변경 → 토큰 검사 → 서버 전송

7. Firebase 자동 갱신
   └─> onTokenRefresh 리스너 → 자동 서버 전송

8. 앱 삭제
   └─> 모든 로컬 데이터 삭제 → 서버 토큰은 유지 (서버 정리 필요)
```

---

## ✅ 검증 체크리스트

- [x] 앱 시작 시 토큰 검사 및 서버 전송
- [x] 로그인 시 토큰 검사 및 서버 전송
- [x] 로그아웃 시 토큰 캐시 초기화
- [x] 회원 탈퇴 시 로컬 토큰 초기화 (서버 삭제는 서버 측 처리)
- [x] 포그라운드 전환 시 토큰 검사 및 서버 전송
- [x] 알림 설정 변경 시 토큰 검사 및 서버 전송
- [x] Firebase 자동 갱신 시 자동 서버 전송
- [x] 토큰 불일치 감지 및 자동 업데이트
- [x] 토큰 만료 시 재발급 및 서버 전송
- [x] 알림 권한 없을 시 서버 설정 동기화
- [x] DeviceId 유지 (앱 삭제 전까지)

---

## ⚠️ 주의사항 및 개선 필요사항

### 1. 앱 삭제 시
- 현재: 서버에 FCM 토큰이 남아있을 수 있음
- 개선: 서버에서 오래된 토큰 자동 정리 또는 주기적 유효성 검증

### 2. 회원 탈퇴 시
- 현재: 클라이언트는 로컬 캐시만 초기화
- 개선: 서버에서 계정 삭제 시 관련 FCM 토큰도 삭제 (서버 측 처리 필요)

### 3. 로그아웃 시
- 현재: 로컬 캐시만 초기화, 서버 토큰은 유지
- 개선: 로그아웃 시 서버에서 FCM 토큰 삭제 API 호출 고려

---

## 📝 코드 위치 정리

### FCM 관련 파일
- `lib/data/services/fcm_service.dart` - FCM 토큰 관리 서비스
- `lib/data/services/auth_service.dart` - FCM 토큰 서버 전송
- `lib/main.dart` - FCM 핸들러 등록 및 포그라운드 전환 처리
- `lib/pages/screens/splash_screen.dart` - 앱 시작 시 토큰 검사
- `lib/pages/screens/setting_screen.dart` - 알림 설정 변경 시 토큰 동기화
- `lib/pages/components/account_deletion_confirm.dart` - 회원 탈퇴 처리

---

## 🔧 주요 메서드 설명

### FcmService
- `getToken(forceRefresh)` - FCM 토큰 가져오기 (캐시 확인)
- `isTokenValid()` - 토큰 유효성 검사
- `checkAndRefreshTokenIfNeeded()` - 토큰 검사 및 필요시 재발급
- `refreshTokenIfNeeded()` - 토큰 재발급
- `clearToken()` - 토큰 캐시 초기화
- `isNotificationPermissionGranted()` - 알림 권한 확인

### AuthService
- `_sendFcmTokenToServer()` - FCM 토큰 서버 전송
- `syncFcmTokenAndSettings()` - FCM 토큰 동기화 (검사 + 전송)
- `getDeviceId()` - DeviceId 가져오기 (없으면 생성)

