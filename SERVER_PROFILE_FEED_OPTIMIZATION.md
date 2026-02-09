# 서버 측 프로필 피드 최적화 전략

## 📋 기본 원칙

### 1. 기본 응답: 전체 포스트
- **기본값**: `phase` 파라미터 없으면 전체 포스트 반환
- **이유**: 클라이언트에서 필터링 가능하지만, 서버 필터링이 더 효율적

### 2. 뷰어 타입별 선별 로직
- **내 프로필**: 모든 포스트 (PUBLIC, FRIENDS, PRIVATE, GIRLFRIEND_TO_BOYFRIEND 등)
- **타인 프로필 (곰신)**: 남친이 그녀에게 공개한 글만 (BOYFRIEND_TO_GIRLFRIEND, PUBLIC)
- **타인 프로필 (일반)**: 공개 글만 (PUBLIC, FRIENDS)

---

## 🎯 API 엔드포인트 설계

### GET /api/profile/feed/{username}

#### 요청 파라미터

| 파라미터 | 타입 | 필수 | 기본값 | 설명 |
|---------|------|------|--------|------|
| `page` | integer | ❌ | 0 | 페이지 번호 (0-based) |
| `size` | integer | ❌ | 20 | 페이지 크기 |
| `phase` | string | ❌ | null | Phase 필터 (preEnlistment, training, private, ...) |
| `lifePhase` | string | ❌ | null | 생활 단계 필터 (LEAVE_OR_PRE_ENLISTMENT, MILITARY_LIFE, SUPPORT) |
| `preview` | boolean | ❌ | false | 미리보기 모드 (6개만 반환) |

#### 뷰어 타입 자동 감지
- JWT에서 현재 로그인한 사용자 정보 추출
- `username`과 현재 사용자 비교 → 내 프로필 vs 타인 프로필 판단
- 타인 프로필일 때: `connectedMilitaryUser` 확인 → 곰신 모드 판단

---

## 🔄 로드 전략

### 전략 1: 기본 전체 로드 (추천)

**동작:**
1. 프로필 화면 진입 시 → 전체 포스트 로드 (기본)
2. 필터 탭 클릭 시 → 클라이언트에서 필터링 (즉시 반응)
3. 서버 필터링 필요 시 → API 재호출 (선택적)

**장점:**
- 초기 로드 후 탭 전환이 빠름 (클라이언트 필터링)
- 네트워크 요청 최소화

**단점:**
- 포스트가 많으면 초기 로드 시간 증가
- 메모리 사용량 증가

**구현:**
```python
# 기본 로드: 전체 포스트
GET /api/profile/feed/{username}?page=0&size=20

# 필터 탭 클릭: 클라이언트에서 필터링
# (서버 재호출 없음)
```

---

### 전략 2: 지연 로드 (Lazy Load)

**동작:**
1. 프로필 화면 진입 시 → "전체" 탭만 로드 (6개 또는 20개)
2. 필터 탭 클릭 시 → 서버에 필터 파라미터로 재요청
3. 각 필터별로 독립적인 페이지네이션

**장점:**
- 초기 로드 시간 단축
- 메모리 사용량 최소화
- 각 필터별 정확한 개수 제공

**단점:**
- 탭 전환 시 네트워크 지연
- 필터별로 별도 요청 필요

**구현:**
```python
# 초기 로드: 전체 6개 (preview=true)
GET /api/profile/feed/{username}?preview=true

# 필터 탭 클릭: 해당 필터로 재요청
GET /api/profile/feed/{username}?phase=private&page=0&size=20
```

---

### 전략 3: 하이브리드 (추천)

**동작:**
1. 프로필 화면 진입 시 → "전체" 탭만 로드 (20개)
2. 필터 탭 클릭 시:
   - **처음 클릭**: 서버에 필터 파라미터로 요청
   - **이후 클릭**: 클라이언트 캐시에서 필터링 (이미 로드된 경우)
3. 페이지네이션: 각 필터별로 독립적

**장점:**
- 초기 로드 시간 적절
- 탭 재전환 시 빠름 (캐시 활용)
- 메모리 사용량 적절

**단점:**
- 구현 복잡도 증가
- 캐시 관리 필요

**구현:**
```python
# 초기 로드: 전체 20개
GET /api/profile/feed/{username}?page=0&size=20

# 필터 탭 클릭 (처음): 서버 요청
GET /api/profile/feed/{username}?phase=private&page=0&size=20

# 필터 탭 재클릭: 클라이언트 캐시에서 필터링
```

---

## 📊 서버 측 쿼리 최적화

### 1. 인덱스 설계

```sql
-- 포스트 테이블 인덱스
CREATE INDEX idx_posts_author_created ON posts(author, created_at DESC);
CREATE INDEX idx_posts_phase ON posts(phase) WHERE phase IS NOT NULL;
CREATE INDEX idx_posts_life_phase ON posts(life_phase) WHERE life_phase IS NOT NULL;
CREATE INDEX idx_posts_author_phase ON posts(author, phase, created_at DESC);
```

### 2. 쿼리 예시

**전체 포스트 (기본)**
```sql
SELECT * FROM posts
WHERE author = 'user123'
  AND (access_level IN ('PUBLIC', 'FRIENDS', 'PRIVATE', 'GIRLFRIEND_TO_BOYFRIEND') 
       OR access_level = 'BOYFRIEND_TO_GIRLFRIEND' AND viewer = 'girlfriend_username')
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

**Phase 필터**
```sql
SELECT * FROM posts
WHERE author = 'user123'
  AND phase = 'private'
  AND (access_level IN (...))
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

**휴가 필터**
```sql
SELECT * FROM posts
WHERE author = 'user123'
  AND life_phase = 'LEAVE_OR_PRE_ENLISTMENT'
  AND phase != 'preEnlistment'
  AND (access_level IN (...))
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

---

## 🔀 뷰어 타입별 선별 로직

### 내 프로필 (isOwnProfile = true)

```python
def get_profile_feed(username, viewer_username, phase=None, life_phase=None, preview=False):
    # 내 프로필: 모든 포스트 표시
    query = Post.objects.filter(author=username)
    
    # Phase 필터
    if phase:
        query = query.filter(phase=phase)
    
    # LifePhase 필터
    if life_phase:
        if life_phase == 'LEAVE_OR_PRE_ENLISTMENT' and phase != 'preEnlistment':
            # 휴가: 입대 후 휴가만
            query = query.filter(
                life_phase='LEAVE_OR_PRE_ENLISTMENT',
                phase__ne='preEnlistment'
            )
        elif phase == 'preEnlistment':
            # 입대전 추억
            query = query.filter(phase='preEnlistment')
        else:
            query = query.filter(life_phase=life_phase)
    
    # 정렬 및 페이지네이션
    posts = query.order_by('-created_at')
    
    if preview:
        posts = posts[:6]
    else:
        posts = posts[page * size:(page + 1) * size]
    
    return posts
```

### 타인 프로필 - 곰신 모드

```python
def get_profile_feed(username, viewer_username, phase=None, life_phase=None, preview=False):
    # 곰신이 남친 프로필을 볼 때
    viewer = User.objects.get(username=viewer_username)
    is_girlfriend = viewer.military_info.user_type == 'girlfriend'
    connected_military = viewer.connected_military_user
    
    if is_girlfriend and connected_military.username == username:
        # 남친이 그녀에게 공개한 글만
        query = Post.objects.filter(
            author=username,
            access_level__in=['BOYFRIEND_TO_GIRLFRIEND', 'PUBLIC']
        )
    else:
        # 일반 사용자: 공개 글만
        query = Post.objects.filter(
            author=username,
            access_level__in=['PUBLIC', 'FRIENDS']
        )
    
    # Phase 필터 적용
    if phase:
        query = query.filter(phase=phase)
    
    # ... 나머지 로직 동일
```

### 타인 프로필 - 일반 사용자

```python
def get_profile_feed(username, viewer_username, phase=None, life_phase=None, preview=False):
    # 일반 사용자: 공개 글만
    query = Post.objects.filter(
        author=username,
        access_level__in=['PUBLIC', 'FRIENDS']
    )
    
    # Phase 필터 적용
    if phase:
        query = query.filter(phase=phase)
    
    # ... 나머지 로직 동일
```

---

## 📱 클라이언트-서버 협업 전략

### 시나리오 1: 프로필 화면 진입

```
1. 클라이언트: GET /api/profile/feed/{username}?page=0&size=20
   ↓
2. 서버: 전체 포스트 20개 반환 (뷰어 타입별 선별 적용)
   ↓
3. 클라이언트: "전체" 탭에 표시 (필터링 없음)
```

### 시나리오 2: 필터 탭 클릭 (처음)

```
1. 클라이언트: 사용자가 "이병" 탭 클릭
   ↓
2. 클라이언트: GET /api/profile/feed/{username}?phase=private&page=0&size=20
   ↓
3. 서버: 이병 Phase 포스트 20개 반환
   ↓
4. 클라이언트: "이병" 제목 + 포스트 리스트 표시
```

### 시나리오 3: 필터 탭 재클릭 (캐시 활용)

```
1. 클라이언트: 사용자가 "전체" 탭 재클릭
   ↓
2. 클라이언트: 이미 로드된 전체 포스트 캐시에서 필터링
   ↓
3. 서버 요청 없음 (즉시 표시)
```

### 시나리오 4: 페이지네이션

```
1. 클라이언트: 스크롤 끝 감지
   ↓
2. 클라이언트: GET /api/profile/feed/{username}?phase=private&page=1&size=20
   ↓
3. 서버: 다음 20개 반환
   ↓
4. 클라이언트: 기존 리스트에 추가
```

---

## 🎯 최적화 포인트

### 1. 캐싱 전략

**서버 측 캐싱:**
- 사용자별 프로필 피드 캐시 (Redis)
- TTL: 5분
- 필터별로 별도 캐시 키: `profile_feed:{username}:{phase}:{page}`

**클라이언트 측 캐싱:**
- Provider에서 필터별 포스트 목록 캐싱
- 필터 전환 시 캐시에서 먼저 확인

### 2. 페이지네이션 최적화

**커서 기반 페이지네이션 (선택적):**
```python
# 기존: OFFSET 기반
SELECT * FROM posts WHERE ... LIMIT 20 OFFSET 40;

# 최적화: 커서 기반 (대량 데이터에 유리)
SELECT * FROM posts 
WHERE author = 'user123' 
  AND created_at < '2025-01-15T10:00:00Z'
ORDER BY created_at DESC 
LIMIT 20;
```

### 3. Phase 계산 최적화

**서버에서 Phase 미리 계산:**
- 포스트 등록 시 `phase` 필드 자동 계산 및 저장
- 쿼리 시 `phase` 필드로 직접 필터링 (계산 불필요)

### 4. 뷰어 타입별 쿼리 분기

**조건부 쿼리:**
```python
if is_own_profile:
    # 내 프로필: access_level 필터링 없음
    query = Post.objects.filter(author=username)
elif is_girlfriend_viewing_boyfriend:
    # 곰신 모드: BOYFRIEND_TO_GIRLFRIEND, PUBLIC만
    query = Post.objects.filter(
        author=username,
        access_level__in=['BOYFRIEND_TO_GIRLFRIEND', 'PUBLIC']
    )
else:
    # 일반: PUBLIC, FRIENDS만
    query = Post.objects.filter(
        author=username,
        access_level__in=['PUBLIC', 'FRIENDS']
    )
```

---

## 📝 API 응답 구조

### 기본 응답 구조: ProfileFeedSchemaAndPostsResponse

```json
{
  "userInfo": {
    "username": "user123",
    "alias": "별명",
    "profileImageUrl": "https://...",
    "militaryInfo": {
      "userType": "military",
      "branch": "army",
      "status": "afterEnlistment",
      "enlistmentDate": "2024-03-01T00:00:00Z",
      "currentRank": "privateFirstClass",
      "plannedEnlistmentDate": null,
      "connectedMilitaryUserIds": null
    },
    "friendCount": 15,
    "onboardingCompleted": true,
    "isOwnProfile": true
  },
  "systemCategoryMappings": {
    "PUBLIC": [
      {"postId": "123", "order": 0},
      {"postId": "124", "order": 1}
    ],
    "FRIENDS": [
      {"postId": "125", "order": 2}
    ],
    "PRIVATE": [
      {"postId": "126", "order": 3}
    ]
  },
  "posts": {
    "posts": [
      {
        "id": "123",
        "title": "오늘의 일기",
        "author": "user123",
        "authorId": 1,
        "authorProfileImageUrl": "https://...",
        "thumbnailImageUrl": "https://...",
        "content": {
          "type": "doc",
          "content": [...]
        },
        "usedImageUrls": [
          "https://...",
          "https://..."
        ],
        "accessLevel": "PUBLIC",
        "year": 2025,
        "weekOfYear": 3,
        "phase": "private",
        "lifePhase": "MILITARY_LIFE",
        "createdAt": "2025-01-15T10:00:00Z",
        "updatedAt": "2025-01-15T10:00:00Z",
        "viewCount": 42,
        "likeCount": 5,
        "commentCount": 2,
        "isLiked": false
      }
    ],
    "totalElements": 42,
    "totalPages": 3,
    "hasNext": true,
    "currentPage": 0,
    "size": 20
  }
}
```

### 필드 상세 설명

#### userInfo
프로필 주인 정보

| 필드 | 타입 | 설명 |
|------|------|------|
| `username` | string | 사용자명 |
| `alias` | string | 별명 |
| `profileImageUrl` | string | 프로필 이미지 URL |
| `militaryInfo` | object | 군인 정보 (있을 경우) |
| `friendCount` | integer | 친구 수 |
| `onboardingCompleted` | boolean | 온보딩 완료 여부 |
| `isOwnProfile` | boolean | 내 프로필인지 여부 (서버에서 판단) |

#### systemCategoryMappings
공개범위별 포스트 ID 매핑 (내 프로필일 때만 제공)

| 키 | 타입 | 설명 |
|---|------|------|
| `PUBLIC` | array | 전체공개 포스트 ID 목록 |
| `FRIENDS` | array | 친구공개 포스트 ID 목록 |
| `PRIVATE` | array | 나만보기 포스트 ID 목록 |

**포맷:**
```json
{
  "PUBLIC": [
    {"postId": "123", "order": 0},
    {"postId": "124", "order": 1}
  ]
}
```

#### posts
포스트 목록 및 페이지네이션 정보

| 필드 | 타입 | 설명 |
|------|------|------|
| `posts` | array | 포스트 목록 |
| `totalElements` | integer | 전체 포스트 수 (필터 적용 후) |
| `totalPages` | integer | 전체 페이지 수 |
| `hasNext` | boolean | 다음 페이지 존재 여부 |
| `currentPage` | integer | 현재 페이지 번호 (0-based) |
| `size` | integer | 페이지 크기 |

#### posts[].post (포스트 객체)

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | string | 포스트 ID |
| `title` | string | 제목 |
| `author` | string | 작성자 username |
| `authorId` | integer | 작성자 ID |
| `authorProfileImageUrl` | string | 작성자 프로필 이미지 URL |
| `thumbnailImageUrl` | string | 썸네일 이미지 URL |
| `content` | object | 본문 콘텐츠 (JSON) |
| `usedImageUrls` | array | 사용된 이미지 URL 목록 |
| `accessLevel` | string | 공개 범위 (PUBLIC, PRIVATE, FRIENDS, ...) |
| `year` | integer | 연도 |
| `weekOfYear` | integer | 주차 (1-53) |
| `phase` | string | Phase 코드 (preEnlistment, training, private, ...) |
| `lifePhase` | string | 생활 단계 (MILITARY_LIFE, LEAVE_OR_PRE_ENLISTMENT, SUPPORT) |
| `createdAt` | string | 생성일시 (ISO 8601) |
| `updatedAt` | string | 수정일시 (ISO 8601) |
| `viewCount` | integer | 조회수 |
| `likeCount` | integer | 좋아요 수 |
| `commentCount` | integer | 댓글 수 |
| `isLiked` | boolean | 현재 사용자가 좋아요 했는지 |

---

### 응답 예시

#### 1. 기본 응답 (전체 포스트, 내 프로필)

```json
{
  "userInfo": {
    "username": "soldier123",
    "alias": "군인",
    "profileImageUrl": "https://...",
    "militaryInfo": {
      "userType": "military",
      "branch": "army",
      "currentRank": "privateFirstClass"
    },
    "isOwnProfile": true
  },
  "systemCategoryMappings": {
    "PUBLIC": [{"postId": "123", "order": 0}],
    "FRIENDS": [{"postId": "124", "order": 1}],
    "PRIVATE": [{"postId": "125", "order": 2}]
  },
  "posts": {
    "posts": [
      {
        "id": "123",
        "title": "오늘의 일기",
        "author": "soldier123",
        "phase": "private",
        "lifePhase": "MILITARY_LIFE",
        "accessLevel": "PUBLIC",
        "createdAt": "2025-01-15T10:00:00Z"
      }
    ],
    "totalElements": 42,
    "totalPages": 3,
    "hasNext": true,
    "currentPage": 0
  }
}
```

#### 2. Phase 필터 응답 (이병 필터)

```json
{
  "userInfo": {...},
  "systemCategoryMappings": {...},
  "posts": {
    "posts": [
      {
        "id": "123",
        "title": "이병 때 쓴 글",
        "author": "soldier123",
        "phase": "private",
        "lifePhase": "MILITARY_LIFE",
        "accessLevel": "PUBLIC",
        "createdAt": "2025-01-15T10:00:00Z"
      }
    ],
    "totalElements": 12,  // 이병 포스트만의 개수
    "totalPages": 1,
    "hasNext": false,
    "currentPage": 0
  }
}
```

#### 3. 미리보기 모드 응답 (preview=true)

```json
{
  "userInfo": {...},
  "systemCategoryMappings": {...},
  "posts": {
    "posts": [
      // 최신 6개만
    ],
    "totalElements": 42,  // 전체 개수 (더보기 버튼용)
    "totalPages": 3,
    "hasNext": true,
    "currentPage": 0,
    "size": 6  // preview 모드에서는 6
  }
}
```

#### 4. 타인 프로필 응답 (곰신 모드)

```json
{
  "userInfo": {
    "username": "soldier123",
    "alias": "남친",
    "profileImageUrl": "https://...",
    "militaryInfo": {
      "userType": "military",
      "branch": "army",
      "currentRank": "privateFirstClass"
    },
    "isOwnProfile": false  // 타인 프로필
  },
  "systemCategoryMappings": null,  // 타인 프로필에서는 null
  "posts": {
    "posts": [
      {
        "id": "123",
        "title": "남친이 그녀에게 공개한 글",
        "author": "soldier123",
        "phase": "private",
        "lifePhase": "MILITARY_LIFE",
        "accessLevel": "BOYFRIEND_TO_GIRLFRIEND",  // 곰신에게만 공개
        "createdAt": "2025-01-15T10:00:00Z"
      }
    ],
    "totalElements": 15,  // 곰신에게 공개된 글만
    "totalPages": 1,
    "hasNext": false,
    "currentPage": 0
  }
}
```

---

### 뷰어 타입별 응답 차이

#### 내 프로필 (isOwnProfile = true)

- `systemCategoryMappings` 제공
- 모든 `accessLevel` 포스트 포함
- `isOwnProfile: true`

#### 타인 프로필 - 곰신 모드

- `systemCategoryMappings: null`
- `accessLevel IN ('BOYFRIEND_TO_GIRLFRIEND', 'PUBLIC')` 포스트만
- `isOwnProfile: false`

#### 타인 프로필 - 일반 사용자

- `systemCategoryMappings: null`
- `accessLevel IN ('PUBLIC', 'FRIENDS')` 포스트만
- `isOwnProfile: false`

---

### Phase 필터별 totalElements

**중요:** `totalElements`는 **필터 적용 후**의 개수입니다.

- 전체 탭: 전체 포스트 수
- 이병 탭: 이병 Phase 포스트 수만
- 휴가 탭: 휴가 포스트 수만

**예시:**
```json
// 전체 탭
{
  "posts": {
    "totalElements": 42  // 전체 42개
  }
}

// 이병 탭
{
  "posts": {
    "totalElements": 12  // 이병 포스트만 12개
  }
}
```

---

### 에러 응답

#### 404: 사용자를 찾을 수 없음

```json
{
  "success": false,
  "message": "사용자를 찾을 수 없습니다.",
  "data": null
}
```

#### 401: 인증 필요

```json
{
  "success": false,
  "message": "인증이 필요합니다.",
  "data": null
}
```

#### 400: 잘못된 파라미터

```json
{
  "success": false,
  "message": "잘못된 phase 값입니다.",
  "data": null
}
```

---

## 🔄 필터 전환 시 최적화

### 옵션 1: 서버 재요청 (정확한 개수)

**장점:**
- 각 필터별 정확한 `totalElements` 제공
- 서버에서 최적화된 쿼리 실행

**단점:**
- 네트워크 지연
- 탭 전환 시 로딩 표시 필요

### 옵션 2: 클라이언트 필터링 (빠른 전환)

**장점:**
- 즉시 반응 (로딩 없음)
- 네트워크 요청 없음

**단점:**
- `totalElements`가 부정확 (전체 기준)
- 클라이언트 메모리 사용

### 옵션 3: 하이브리드 (추천)

**동작:**
1. **첫 필터 클릭**: 서버 재요청 (정확한 데이터)
2. **재클릭**: 클라이언트 캐시 활용 (빠른 전환)
3. **페이지네이션**: 각 필터별로 독립적

**구현:**
```dart
// Provider에 필터별 캐시 관리
Map<ProfileFeedFilter, List<PostData>> _filterCache = {};

void selectPhaseFilter(ProfileFeedFilter filter) {
  _selectedPhaseFilter = filter;
  
  // 캐시에 있으면 즉시 표시
  if (_filterCache.containsKey(filter)) {
    notifyListeners();
    return;
  }
  
  // 캐시에 없으면 서버 요청
  loadInitial(force: true);
}
```

---

## 🎯 추천 구현 전략

### 1단계: 기본 구현 (간단)

```python
# 기본: 전체 포스트만 반환
GET /api/profile/feed/{username}?page=0&size=20

# 클라이언트에서 필터링
# - 빠른 구현
# - 서버 부하 최소
```

### 2단계: 서버 필터링 추가 (최적화)

```python
# Phase 필터 지원
GET /api/profile/feed/{username}?phase=private&page=0&size=20

# 서버에서 필터링
# - 정확한 개수 제공
# - 쿼리 최적화
```

### 3단계: 캐싱 추가 (고급)

```python
# Redis 캐싱
# - 사용자별 캐시
# - 필터별 캐시
# - TTL 관리
```

---

## 📊 성능 비교

| 전략 | 초기 로드 | 탭 전환 | 메모리 | 정확도 |
|------|----------|---------|--------|--------|
| **전체 로드 + 클라이언트 필터** | 느림 | 빠름 | 높음 | 낮음 |
| **지연 로드** | 빠름 | 느림 | 낮음 | 높음 |
| **하이브리드** | 보통 | 빠름 | 보통 | 높음 |

**추천: 하이브리드 전략**

---

## 🔧 구현 체크리스트

### 서버 측

- [ ] `GET /api/profile/feed/{username}` 엔드포인트
- [ ] `phase` 파라미터 지원
- [ ] `lifePhase` 파라미터 지원
- [ ] `preview` 파라미터 지원 (6개만)
- [ ] 뷰어 타입별 선별 로직 (내 프로필 vs 타인 프로필)
- [ ] 곰신 모드 선별 로직
- [ ] Phase 필터 쿼리 최적화
- [ ] 인덱스 추가
- [ ] 페이지네이션 (`totalElements`, `hasNext` 포함)
- [ ] 캐싱 전략 (선택적)

### 클라이언트 측

- [ ] 필터 탭 UI
- [ ] 필터별 캐시 관리
- [ ] 서버 필터 파라미터 전달
- [ ] 페이지네이션 처리
- [ ] 더보기 버튼 (전체 탭)

---

## 💡 추가 고려사항

### 1. Phase 계산 시점

**옵션 A: 포스트 등록 시 계산 (추천)**
- 포스트 등록 시 `phase` 필드 자동 계산 및 저장
- 쿼리 시 계산 불필요

**옵션 B: 쿼리 시 계산**
- `year`, `weekOfYear`로 Phase 계산
- 유연하지만 성능 저하 가능

### 2. 필터별 개수 표시

**전체 탭:**
- `totalElements` 표시 (예: "전체 보기 (총 42개)")

**계급별 탭:**
- 각 탭에 포스트 수 표시 (예: "이병 (12)")
- 서버에서 필터별 개수 제공 필요

### 3. 실시간 업데이트

- 새 포스트 등록 시 캐시 무효화
- WebSocket 또는 Polling으로 실시간 업데이트 (선택적)

