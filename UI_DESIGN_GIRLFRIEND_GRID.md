# 곰신 모드 & 그리드 모드 UI 구상

## 📋 개요

`User` 모델의 `connectedMilitaryUser`와 `connectedToMeByUser` 필드를 기반으로 곰신 모드와 군인 모드의 UI를 구분하여 표시합니다.

---

## 🎯 사용자 모드 구분

### 1. 곰신 모드 (UserType.girlfriend)
- **조건**: `user.militaryInfo?.userType == UserType.girlfriend`
- **그리드 소유자**: `user.connectedMilitaryUser` (남친)
- **그리드 API**: 서버가 자동으로 남친의 그리드를 반환 (`GET /api/military/grid`)

### 2. 군인 모드 (UserType.military | plannedEnlistment)
- **조건**: `user.militaryInfo?.userType == UserType.military || user.militaryInfo?.userType == UserType.plannedEnlistment`
- **그리드 소유자**: 본인 (`user`)
- **그리드 API**: 본인의 그리드 반환 (`GET /api/military/grid`)

---

## 🎨 UI 구조

### 곰신 모드 UI

```
┌─────────────────────────────────────┐
│  [헤더: 남친 프로필 + 인사말]        │
│  ┌───────────────────────────────┐  │
│  │ 👤 [남친 프로필 이미지]        │  │
│  │    [남친 별명]                 │  │
│  │    [계급] [군종]               │  │
│  └───────────────────────────────┘  │
│                                      │
│  [인사말 섹션]                       │
│  "남친님의 복무 일정을 확인해보세요" │
│                                      │
│  [남친의 그리드]                     │
│  ┌───────────────────────────────┐  │
│  │ [Phase: 입대전] [Phase: 훈련소]│  │
│  │ [Phase: 이병] [Phase: 일병]    │  │
│  │                                │  │
│  │ [셀] [셀] [셀] [셀] [셀]       │  │
│  │ [셀] [셀] [셀] [셀] [셀]       │  │
│  │                                │  │
│  │ 💬 "남친님이 작성한 글"        │  │
│  │ 📸 [썸네일] [썸네일] [썸네일]  │  │
│  └───────────────────────────────┘  │
│                                      │
│  [연결 상태 배지] (선택적)           │
│  "✅ 남친과 연결됨"                  │
└─────────────────────────────────────┘
```

**특징:**
- 남친의 그리드를 **읽기 전용**으로 표시
- Phase 선택기 **비활성화** (남친의 현재 Phase만 표시)
- 남친이 작성한 글만 표시 (BOYFRIEND_TO_GIRLFRIEND, PUBLIC)
- 셀 클릭 시 남친의 주차 포스트 목록으로 이동

---

### 군인 모드 UI

```
┌─────────────────────────────────────┐
│  [헤더: Phase 선택기]               │
│  ┌───────────────────────────────┐  │
│  │ [입대전 ▼] [훈련소 ▼] [이병 ▼]│  │
│  └───────────────────────────────┘  │
│                                      │
│  [인사말 섹션]                       │
│  "복무 일정을 기록해보세요"          │
│                                      │
│  [본인의 그리드]                     │
│  ┌───────────────────────────────┐  │
│  │ [Phase: 입대전] [Phase: 훈련소]│  │
│  │ [Phase: 이병] [Phase: 일병]    │  │
│  │                                │  │
│  │ [셀] [셀] [셀] [셀] [셀]       │  │
│  │ [셀] [셀] [셀] [셀] [셀]       │  │
│  │                                │  │
│  │ 💬 "내가 작성한 글"             │  │
│  │ 📸 [썸네일] [썸네일] [썸네일]  │  │
│  └───────────────────────────────┘  │
│                                      │
│  [곰신 연결 상태] (선택적)           │
│  ┌───────────────────────────────┐  │
│  │ 👤 [곰신 프로필] "곰신님이     │  │
│  │    함께 보고 있어요"           │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**특징:**
- 본인의 그리드를 **편집 가능**으로 표시
- Phase 선택기 **활성화** (모든 Phase 선택 가능)
- 본인이 작성한 글 + 친구 공개글 + 곰신→나 글 표시
- 셀 클릭 시 포스트 작성/조회 가능

---

## 🧩 컴포넌트 구조

### 1. `GirlfriendHomeWidget` (곰신 모드)

```dart
class GirlfriendHomeWidget extends StatelessWidget {
  final User currentUser; // 곰신
  final User? connectedMilitaryUser; // 남친
  final MilitaryGridResponse? gridResponse; // 남친의 그리드
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 남친 프로필 헤더
        _BoyfriendProfileHeader(
          boyfriend: connectedMilitaryUser,
        ),
        
        // 인사말
        GreetingSection(
          greetingKey: gridResponse?.greetingKey,
          isLoading: gridResponse == null,
        ),
        
        // 남친의 그리드 (읽기 전용)
        MilitaryGridWidget(
          gridResponse: gridResponse,
          isReadOnly: true, // 읽기 전용
          onCellTap: (phase, cell) {
            // 남친의 주차 포스트 목록으로 이동
            Navigator.push(
              context,
              WeekPostListScreen(
                year: cell.year,
                weekNumber: cell.week,
                authorUsername: connectedMilitaryUser?.username,
              ),
            );
          },
        ),
        
        // 연결 상태 배지
        if (connectedMilitaryUser != null)
          _ConnectionStatusBadge(
            isConnected: true,
            boyfriendName: connectedMilitaryUser.alias,
          ),
      ],
    );
  }
}
```

**`_BoyfriendProfileHeader` 컴포넌트:**
```dart
class _BoyfriendProfileHeader extends StatelessWidget {
  final User? boyfriend;
  
  @override
  Widget build(BuildContext context) {
    if (boyfriend == null) {
      return _NoConnectionHeader(); // 연결 안내
    }
    
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: 30,
            backgroundImage: boyfriend.profileImageUrl != null
                ? CachedNetworkImageProvider(boyfriend.profileImageUrl!)
                : null,
          ),
          SizedBox(width: 12),
          
          // 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  boyfriend.alias ?? boyfriend.username,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (boyfriend.militaryInfo != null) ...[
                  Text(
                    '${boyfriend.militaryInfo!.currentRank?.displayName ?? "훈련병"} · ${boyfriend.militaryInfo!.branch.displayName}',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

### 2. `MilitaryHomeWidget` (군인 모드)

```dart
class MilitaryHomeWidget extends StatelessWidget {
  final User currentUser; // 군인/입대예정
  final User? connectedToMeByUser; // 곰신 (선택적)
  final MilitaryGridResponse? gridResponse; // 본인의 그리드
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Phase 선택기 (AppBar에 표시)
        // (home_screen.dart에서 처리)
        
        // 인사말
        GreetingSection(
          greetingKey: gridResponse?.greetingKey,
          isLoading: gridResponse == null,
        ),
        
        // 본인의 그리드 (편집 가능)
        MilitaryGridWidget(
          gridResponse: gridResponse,
          isReadOnly: false, // 편집 가능
          onCellTap: (phase, cell) {
            // 포스트 작성/조회
            if (cell.postCount > 0) {
              Navigator.push(
                context,
                WeekPostListScreen(
                  year: cell.year,
                  weekNumber: cell.week,
                ),
              );
            } else {
              Navigator.push(
                context,
                PostwriteScreen(isEditingMode: false),
              );
            }
          },
        ),
        
        // 곰신 연결 상태 (선택적)
        if (connectedToMeByUser != null)
          _GirlfriendConnectionBadge(
            girlfriend: connectedToMeByUser,
          ),
      ],
    );
  }
}
```

**`_GirlfriendConnectionBadge` 컴포넌트:**
```dart
class _GirlfriendConnectionBadge extends StatelessWidget {
  final User girlfriend;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: girlfriend.profileImageUrl != null
                ? CachedNetworkImageProvider(girlfriend.profileImageUrl!)
                : null,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '${girlfriend.alias ?? girlfriend.username}님이 함께 보고 있어요',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 🔄 모드 전환 로직

### `home_widgets.dart` 수정

```dart
Widget buildHomeWidget({
  required User? currentUser,
  required MilitaryGridResponse? gridResponse,
  required bool isLoading,
}) {
  if (currentUser == null || currentUser.militaryInfo == null) {
    return _NonMilitaryHomeWidget(); // 비군인 모드
  }
  
  final userType = currentUser.militaryInfo!.userType;
  
  // 곰신 모드
  if (userType == UserType.girlfriend) {
    return GirlfriendHomeWidget(
      currentUser: currentUser,
      connectedMilitaryUser: currentUser.connectedMilitaryUser,
      gridResponse: gridResponse, // 서버가 자동으로 남친 그리드 반환
      isLoading: isLoading,
    );
  }
  
  // 군인 모드 (military | plannedEnlistment)
  if (userType == UserType.military || userType == UserType.plannedEnlistment) {
    return MilitaryHomeWidget(
      currentUser: currentUser,
      connectedToMeByUser: currentUser.connectedToMeByUser,
      gridResponse: gridResponse, // 본인의 그리드
      isLoading: isLoading,
    );
  }
  
  return _NonMilitaryHomeWidget();
}
```

---

## 📱 연결 안내 UI (곰신 모드, 연결 없을 때)

```dart
class _NoConnectionHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.person_add, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '남친과 연결해주세요',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '남친의 복무 일정을 함께 확인하려면\n먼저 남친과 연결해야 합니다',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // 친구 검색 화면으로 이동
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MyFriendsScreen(
                    showSearch: true,
                    filterByRole: 'military', // 군인만 필터링
                  ),
                ),
              );
            },
            child: Text('남친 찾기'),
          ),
        ],
      ),
    );
  }
}
```

---

## 🎯 주요 차이점 요약

| 항목 | 곰신 모드 | 군인 모드 |
|------|----------|----------|
| **그리드 소유자** | 남친 (`connectedMilitaryUser`) | 본인 (`currentUser`) |
| **Phase 선택기** | ❌ 비활성화 | ✅ 활성화 |
| **셀 편집** | ❌ 읽기 전용 | ✅ 편집 가능 |
| **포스트 작성** | ❌ 불가 (남친의 주차) | ✅ 가능 (본인의 주차) |
| **헤더** | 남친 프로필 | Phase 선택기 |
| **연결 상태** | 남친 연결 배지 | 곰신 연결 배지 (선택적) |

---

## 🔧 구현 순서

1. ✅ `User` 모델에 `connectedMilitaryUser`, `connectedToMeByUser` 필드 추가 (완료)
2. 🔄 `GirlfriendHomeWidget` 컴포넌트 생성
3. 🔄 `MilitaryHomeWidget` 컴포넌트 수정 (기존 코드 활용)
4. 🔄 `_BoyfriendProfileHeader` 컴포넌트 생성
5. 🔄 `_GirlfriendConnectionBadge` 컴포넌트 생성
6. 🔄 `_NoConnectionHeader` 컴포넌트 생성
7. 🔄 `home_widgets.dart`에서 모드별 위젯 분기 처리
8. 🔄 `MilitaryGridWidget`에 `isReadOnly` 파라미터 추가
9. 🔄 `home_screen.dart`에서 Phase 선택기 표시 조건 수정

---

## 📝 참고사항

- **그리드 API**: 곰신 모드일 때 서버가 자동으로 `connectedMilitaryUser`의 그리드를 반환하므로, 클라이언트는 추가 로직이 필요 없음
- **연결 상태**: `connectedMilitaryUser`가 `null`이면 연결 안내 UI 표시
- **읽기 전용 모드**: 곰신 모드에서는 셀 클릭 시 포스트 작성 화면으로 이동하지 않고, 포스트 목록 화면으로만 이동

