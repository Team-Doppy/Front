# 프로필 피드 필터 설계

## 📋 현재 Feed 구조 분석

### 1. FeedDisplayMode
- **`card`**: `VerticalCategorySection` 사용
  - 세로 리스트 형태
  - `CardView` 컴포넌트 사용
  - 텍스트 + 썸네일 표시
  
- **`imageOnly`**: `GridCategorySection` 사용
  - 그리드 형태 (3열)
  - `ImageView` 컴포넌트 사용
  - 썸네일만 표시

### 2. 페이지네이션 구조
```dart
// BaseFeedProvider
int _pageSize = 20;  // 한 번에 20개씩
int _currentPage = 0;
bool _hasMore = true;
bool _loadingMore = false;

Future<void> loadMore() async {
  // 다음 페이지 로드
  // _currentPage + 1
  // _hasMore 업데이트
}
```

### 3. 필터 구조
```dart
enum BaseFilter { all, private, friends, public }

// 현재는 공개범위 필터만 존재
// Phase 필터 추가 필요
```

---

## 🎯 새로운 필터 구성

### 군인 모드 (본인 프로필)

```
[전체] [입대전 추억] [훈련소] [이병] [일병] [상병] [병장] [휴가]
```

**필터 타입:**
- `전체`: 대표 6개만 표시 + "더보기" 버튼
- `입대전 추억`: `phase == preEnlistment` 또는 `lifePhase == LEAVE_OR_PRE_ENLISTMENT` (입대 전)
- `훈련소`: `phase == training`
- `이병`: `phase == private`
- `일병`: `phase == privateFirstClass`
- `상병`: `phase == corporal`
- `병장`: `phase == sergeant`
- `휴가`: `lifePhase == LEAVE_OR_PRE_ENLISTMENT` (입대 후)

---

### 곰신 모드 (남친 프로필)

```
[전체] [입대전] [훈련소] [이병] [일병] [상병] [병장]
```

**필터 타입:**
- `전체`: 대표 6개만 표시 + "더보기" 버튼
- `입대전`: `phase == preEnlistment`
- `훈련소`: `phase == training`
- `이병`: `phase == private`
- `일병`: `phase == privateFirstClass`
- `상병`: `phase == corporal`
- `병장`: `phase == sergeant`

**참고:** 곰신 모드에서는 "입대전 추억"과 "휴가"를 구분하지 않음

---

## 🎨 UI 구조

### "전체" 탭 (대표 6개)

```
┌─────────────────────────────────┐
│ [필터 탭]                       │
│ [전체 ▼] [입대전] [훈련소] ...  │
├─────────────────────────────────┤
│ [포스트 6개]                    │
│ - CardView 또는 GridView        │
│                                 │
│ [더보기 버튼]                   │
│ "전체 보기 (총 42개)"           │
└─────────────────────────────────┘
```

**동작:**
1. "전체" 탭 선택 시 → 최신 6개만 표시
2. "더보기" 버튼 클릭 → `ProfileFeedFilterScreen`으로 이동 (전체 필터 적용)

---

### 계급별/휴가 탭 (전체 표시)

```
┌─────────────────────────────────┐
│ [필터 탭]                       │
│ [전체] [입대전 ▼] [훈련소] ...  │
├─────────────────────────────────┤
│ [포스트 전체]                    │
│ - 페이지네이션 적용              │
│ - 스크롤 시 자동 로드            │
│                                 │
│ [로딩 인디케이터]               │
└─────────────────────────────────┘
```

**동작:**
1. 계급별 탭 선택 시 → 해당 Phase의 모든 포스트 표시
2. 페이지네이션 적용 (20개씩)
3. 스크롤 끝에 도달 시 자동으로 `loadMore()` 호출

---

## 🔧 구현 구조

### 1. 필터 Enum 추가

```dart
enum ProfileFeedFilter {
  all,              // 전체 (6개만)
  preEnlistment,    // 입대전
  preEnlistmentMemory, // 입대전 추억 (군인만)
  training,         // 훈련소
  private,          // 이병
  privateFirstClass, // 일병
  corporal,         // 상병
  sergeant,         // 병장
  leave,            // 휴가 (군인만)
}
```

### 2. BaseFeedProvider 확장

```dart
abstract class BaseFeedProvider extends ChangeNotifier {
  // 기존 필드
  BaseFilter _selectedBase = BaseFilter.all;
  
  // 새 필드 추가
  ProfileFeedFilter _selectedPhaseFilter = ProfileFeedFilter.all;
  bool _isShowingPreview = false; // "전체" 탭에서 6개만 보여주는지
  
  ProfileFeedFilter get selectedPhaseFilter => _selectedPhaseFilter;
  bool get isShowingPreview => _isShowingPreview;
  
  void selectPhaseFilter(ProfileFeedFilter filter) {
    _selectedPhaseFilter = filter;
    _isShowingPreview = (filter == ProfileFeedFilter.all);
    notifyListeners();
  }
  
  // Phase 필터링된 포스트 가져오기
  List<PostData> getFilteredPosts() {
    final allPosts = posts.map((p) => PostData.fromServer(p)).toList();
    
    if (_selectedPhaseFilter == ProfileFeedFilter.all) {
      // 전체: 6개만 반환 (isShowingPreview일 때)
      if (_isShowingPreview) {
        return allPosts.take(6).toList();
      }
      return allPosts;
    }
    
    // Phase별 필터링
    return allPosts.where((post) {
      final phase = _getPhaseFromPost(post);
      return _matchesPhaseFilter(phase, _selectedPhaseFilter);
    }).toList();
  }
  
  String? _getPhaseFromPost(PostData post) {
    // post.metadata에서 phase 추출
    // 또는 year/week로 계산
    return post.metadata?['phase'];
  }
  
  bool _matchesPhaseFilter(String? phase, ProfileFeedFilter filter) {
    switch (filter) {
      case ProfileFeedFilter.preEnlistment:
        return phase == 'preEnlistment';
      case ProfileFeedFilter.training:
        return phase == 'training';
      case ProfileFeedFilter.private:
        return phase == 'private';
      // ... 나머지
      default:
        return false;
    }
  }
}
```

### 3. "더보기" 버튼 컴포넌트

```dart
class _MorePostsButton extends StatelessWidget {
  final int totalCount;
  final ProfileFeedFilter filter;
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: onTap,
        child: Text('전체 보기 (총 $totalCount개)'),
      ),
    );
  }
}
```

### 4. 필터 전용 화면

```dart
class ProfileFeedFilterScreen extends StatefulWidget {
  final ProfileFeedFilter filter;
  final String username;
  final bool isOwnProfile;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getFilterTitle(filter)),
      ),
      body: Feed(
        // 해당 필터만 적용된 피드 표시
        // 페이지네이션 적용
      ),
    );
  }
}
```

---

## 📱 사용자 플로우

### 시나리오 1: 전체 탭에서 더보기

```
1. 프로필 화면 진입
   ↓
2. "전체" 탭 선택 (기본)
   ↓
3. 최신 6개 포스트 표시
   ↓
4. "더보기" 버튼 클릭
   ↓
5. ProfileFeedFilterScreen으로 이동
   ↓
6. 전체 포스트 표시 (페이지네이션)
```

### 시나리오 2: 계급별 탭 선택

```
1. 프로필 화면 진입
   ↓
2. "이병" 탭 선택
   ↓
3. 이병 Phase의 모든 포스트 표시
   ↓
4. 스크롤 시 자동으로 loadMore()
```

---

## 🔄 페이지네이션 처리

### "전체" 탭 (6개만)
- 페이지네이션 없음
- 서버에서 최신 6개만 가져오기
- 또는 클라이언트에서 `posts.take(6)`

### 계급별 탭
- 기존 페이지네이션 로직 사용
- `loadMore()` 호출 시 해당 Phase 필터 적용
- API 호출: `GET /api/profile/feed?username=xxx&phase=private&page=0&size=20`

---

## 🎯 구현 순서

1. ✅ `ProfileFeedFilter` enum 추가
2. ✅ `BaseFeedProvider`에 Phase 필터 로직 추가
3. ✅ 필터 탭 UI 컴포넌트 생성
4. ✅ "전체" 탭에서 6개만 표시 + 더보기 버튼
5. ✅ 계급별 탭에서 전체 표시 + 페이지네이션
6. ✅ `ProfileFeedFilterScreen` 생성 (더보기 클릭 시)
7. ✅ API에 Phase 필터 파라미터 추가

---

## 📝 참고사항

- **"전체" 탭**: 대표 6개만 보여주는 것은 클라이언트에서 처리 가능
- **계급별 탭**: 서버 API에 `phase` 파라미터 추가 필요
- **페이지네이션**: 기존 `loadMore()` 로직 재사용
- **필터 전환**: 필터 변경 시 `loadInitial(force: true)` 호출하여 새로 로드

---

## 🖥️ 서버 API 스펙

### GET /api/profile/feed/{username}

프로필 피드 조회 API (Phase 필터 지원)

#### 요청

**Path Parameters:**
- `username` (string, required): 프로필 주인 username

**Query Parameters:**
- `page` (integer, default: 0): 페이지 번호 (0-based)
- `size` (integer, default: 20): 페이지 크기
- `phase` (string, optional): Phase 필터
  - `preEnlistment`: 입대전
  - `training`: 훈련소
  - `private`: 이병
  - `privateFirstClass`: 일병
  - `corporal`: 상병
  - `sergeant`: 병장
- `lifePhase` (string, optional): 생활 단계 필터
  - `LEAVE_OR_PRE_ENLISTMENT`: 휴가 또는 입대전
  - `MILITARY_LIFE`: 부대 생활
  - `SUPPORT`: 응원 글
- `preview` (boolean, default: false): 미리보기 모드 (6개만 반환)
- `viewerType` (string, optional): 뷰어 타입 (서버가 자동 감지 가능)
  - `military`: 군인/입대예정
  - `girlfriend`: 곰신

**참고:**
- `phase`와 `lifePhase`를 동시에 사용할 수 있음
- `preview=true`일 때는 `size` 무시하고 6개만 반환
- `viewerType`은 서버가 JWT에서 자동 감지 가능 (선택적 파라미터)

#### 응답

```json
{
  "userInfo": {
    "username": "user123",
    "alias": "별명",
    "profileImageUrl": "https://...",
    "militaryInfo": {
      "userType": "military",
      "branch": "army",
      "currentRank": "privateFirstClass"
    }
  },
  "systemCategoryMappings": {
    "PUBLIC": [...],
    "FRIENDS": [...],
    "PRIVATE": [...]
  },
  "posts": {
    "posts": [
      {
        "id": "123",
        "title": "제목",
        "author": "user123",
        "thumbnailImageUrl": "https://...",
        "content": {...},
        "accessLevel": "PUBLIC",
        "year": 2025,
        "weekOfYear": 3,
        "phase": "private",
        "lifePhase": "MILITARY_LIFE",
        "createdAt": "2025-01-15T10:00:00Z",
        "likeCount": 5,
        "commentCount": 2
      }
    ],
    "totalElements": 42,
    "totalPages": 3,
    "hasNext": true,
    "currentPage": 0
  }
}
```

**응답 필드 설명:**

- `userInfo`: 프로필 주인 정보
- `systemCategoryMappings`: 공개범위별 포스트 ID 매핑 (기존)
- `posts.posts[]`: 포스트 목록
  - `phase`: 포스트가 속한 Phase (서버에서 계산)
  - `lifePhase`: 포스트의 생활 단계
- `posts.totalElements`: 전체 포스트 수 (필터 적용 후)
- `posts.totalPages`: 전체 페이지 수
- `posts.hasNext`: 다음 페이지 존재 여부
- `posts.currentPage`: 현재 페이지 번호

#### 필터 조합 예시

**1. 전체 탭 (미리보기 6개)**
```
GET /api/profile/feed/user123?preview=true
```

**2. 전체 탭 (전체)**
```
GET /api/profile/feed/user123?page=0&size=20
```

**3. 이병 Phase 필터**
```
GET /api/profile/feed/user123?phase=private&page=0&size=20
```

**4. 휴가 필터 (군인만)**
```
GET /api/profile/feed/user123?lifePhase=LEAVE_OR_PRE_ENLISTMENT&page=0&size=20
```
- 서버에서 `lifePhase == LEAVE_OR_PRE_ENLISTMENT` && `phase != preEnlistment` 조건으로 필터링

**5. 입대전 추억 필터 (군인만)**
```
GET /api/profile/feed/user123?phase=preEnlistment&page=0&size=20
```
또는
```
GET /api/profile/feed/user123?lifePhase=LEAVE_OR_PRE_ENLISTMENT&phase=preEnlistment&page=0&size=20
```

#### 서버 로직 요구사항

**1. Phase 계산**
- 포스트의 `year`, `weekOfYear` 또는 `phase`, `slotIndex`를 기반으로 Phase 계산
- 그리드 시스템과 동일한 로직 사용

**2. 필터 적용 순서**
1. `phase` 필터 적용 (있을 경우)
2. `lifePhase` 필터 적용 (있을 경우)
3. 공개범위 필터 적용 (뷰어 타입에 따라)
4. 정렬: 최신순 (createdAt DESC)
5. 페이지네이션 적용

**3. 뷰어 타입별 공개범위 필터**

**군인 모드 (본인 프로필):**
- 모든 포스트 표시 (PUBLIC, FRIENDS, PRIVATE, GIRLFRIEND_TO_BOYFRIEND 등)

**곰신 모드 (남친 프로필):**
- 남친이 그녀에게 공개한 글만 표시
- `accessLevel == BOYFRIEND_TO_GIRLFRIEND` 또는 `PUBLIC`
- 남친의 친구 공개글은 제외

**4. "입대전 추억" vs "휴가" 구분**

**입대전 추억:**
- `phase == preEnlistment`
- 또는 `lifePhase == LEAVE_OR_PRE_ENLISTMENT` && 입대 전

**휴가:**
- `lifePhase == LEAVE_OR_PRE_ENLISTMENT` && 입대 후
- 즉, `phase != preEnlistment` && `lifePhase == LEAVE_OR_PRE_ENLISTMENT`

**5. 미리보기 모드 (`preview=true`)**
- `size` 파라미터 무시
- 항상 최신 6개만 반환
- `totalElements`는 전체 개수 반환 (더보기 버튼용)

#### 에러 처리

- `404`: 사용자를 찾을 수 없음
- `401`: 인증 필요
- `400`: 잘못된 파라미터 (예: 잘못된 phase 값)

---

## 🔄 클라이언트 API 호출 예시

### BlogService 수정

```dart
Future<Map<String, dynamic>> getProfileFeed(
  String username, {
  int page = 0,
  int size = 20,
  String? phase,           // 새로 추가
  String? lifePhase,       // 새로 추가
  bool preview = false,    // 새로 추가
}) async {
  final queryParams = <String, dynamic>{
    'page': page,
    'size': size,
  };
  
  if (phase != null) {
    queryParams['phase'] = phase;
  }
  
  if (lifePhase != null) {
    queryParams['lifePhase'] = lifePhase;
  }
  
  if (preview) {
    queryParams['preview'] = true;
  }
  
  final response = await _dio.get(
    '/api/profile/feed/$username',
    queryParameters: queryParams,
  );
  
  // ... 기존 로직
}
```

### Provider에서 사용

```dart
// 전체 탭 (미리보기)
final feedData = await blogService.getProfileFeed(
  username,
  preview: true,
);

// 이병 Phase 필터
final feedData = await blogService.getProfileFeed(
  username,
  phase: 'private',
  page: 0,
  size: 20,
);

// 휴가 필터
final feedData = await blogService.getProfileFeed(
  username,
  lifePhase: 'LEAVE_OR_PRE_ENLISTMENT',
  page: 0,
  size: 20,
);
```

---

## 📊 데이터베이스 쿼리 예시 (서버 참고용)

### Phase 필터 쿼리

```sql
-- 이병 Phase 포스트 조회
SELECT * FROM posts
WHERE author = 'user123'
  AND phase = 'private'
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

### 휴가 필터 쿼리

```sql
-- 휴가 포스트 조회 (입대 후)
SELECT * FROM posts
WHERE author = 'user123'
  AND life_phase = 'LEAVE_OR_PRE_ENLISTMENT'
  AND phase != 'preEnlistment'
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

### 입대전 추억 필터 쿼리

```sql
-- 입대전 추억 포스트 조회
SELECT * FROM posts
WHERE author = 'user123'
  AND phase = 'preEnlistment'
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

---

## 🎯 서버 구현 체크리스트

- [ ] `GET /api/profile/feed/{username}`에 `phase` 파라미터 추가
- [ ] `GET /api/profile/feed/{username}`에 `lifePhase` 파라미터 추가
- [ ] `GET /api/profile/feed/{username}`에 `preview` 파라미터 추가
- [ ] Phase 계산 로직 구현 (그리드 시스템과 동일)
- [ ] "입대전 추억" vs "휴가" 구분 로직 구현
- [ ] 뷰어 타입별 공개범위 필터 적용
- [ ] 응답에 `totalElements` 포함
- [ ] 페이지네이션 로직 검증
- [ ] 에러 처리 추가

