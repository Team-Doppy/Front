# 주차별 기여도 그리드 API 명세서

## 개요

사용자의 주차별 포스트 기여도를 잔디 심기 스타일의 그리드로 표시하기 위한 API입니다.  
연도별로 52-53주 전체 데이터를 반환하며, 각 주차별 포스트 정보를 포함합니다.

---

## 엔드포인트

```
GET /api/weeks/contributions
```

### 요청 파라미터

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| `year` | int | 필수 | 조회할 연도 (예: 2026) |

#### `year` 파라미터 상세

- **범위**: 가입일이 속한 연도부터 현재 연도까지 (또는 서버에서 허용하는 범위)
- **형식**: 4자리 정수 (예: `2026`, `2025`, `2024`)
- **제한사항**:
  - 미래 연도는 조회 불가 (현재 연도까지만 조회 가능)
  - 가입일 이전 연도는 조회 불가 (또는 빈 데이터 반환)
- **연도 변경**: 다른 연도를 조회하려면 `year` 파라미터를 변경하여 API를 다시 호출해야 함

### 예시 요청

```
GET /api/weeks/contributions?year=2026
GET /api/weeks/contributions?year=2025
GET /api/weeks/contributions?year=2024
```

---

## 응답 구조

### 성공 응답 (200 OK)

```json
{
  "year": 2026,
  "weeksInYear": 53,
  "timezone": "Asia/Seoul",
  "weekSystem": "ISO-8601",
  "asOf": "2026-09-12T15:30:00Z",
  "weeks": [
    {
      "weekNumber": 1,
      "postCount": 0,
      "myPosts": []
    },
    {
      "weekNumber": 13,
      "postCount": 15,
      "myPosts": [
        {
          "id": "post-123",
          "title": "내 포스트 제목 1",
          "thumbnailUrl": "https://cdn.example.com/thumbnails/post-123.jpg"
        },
        {
          "id": "post-124",
          "title": "내 포스트 제목 2",
          "thumbnailUrl": "https://cdn.example.com/thumbnails/post-124.jpg"
        }
      ]
    } ...
  ]
}
```

---

## 필드 상세 설명

### 최상위 필드

#### `year` (int, 필수)
- 조회한 연도
- 예: `2026`

#### `weeksInYear` (int, 필수)
- 해당 연도의 총 주차 수
- ISO 8601 기준으로 계산
- 값: `52` 또는 `53`
- 계산 방법: 해당 연도의 12월 28일이 포함된 주차 번호

#### `timezone` (string, 필수)
- 시간대 정보
- 고정값: `"Asia/Seoul"`

#### `weekSystem` (string, 필수)
- 주차 계산 기준
- 고정값: `"ISO-8601"`
- ISO 8601 규칙:
  - 주는 월요일에 시작하여 일요일에 끝남
  - 연도의 첫 번째 주는 해당 연도의 첫 번째 목요일을 포함하는 주

#### `asOf` (string, 선택)
- 서버 기준 시점
- ISO 8601 UTC 형식
- 클라이언트 시간 불일치 방지용
- 예: `"2026-09-12T15:30:00Z"`

#### `weeks` (array, 필수)
- 주차별 데이터 배열
- **반드시 1부터 `weeksInYear`까지 모든 주차를 포함해야 함**
- 총 개수: `weeksInYear`개 (52 또는 53)

---

### `weeks` 배열 각 항목

#### `weekNumber` (int, 필수)
- 주차 번호
- 범위: `1` ~ `weeksInYear` (52 또는 53)
- **반드시 연속된 순서로 정렬되어야 함** (1, 2, 3, ..., weeksInYear)

#### `postCount` (int, 필수)
- 해당 주차의 **전체 포스트 개수** (내 포스트 + 친구 포스트)
- `0` 이상의 정수
- **중요**: 친구 포스트는 별도 API로 조회해야 함
- 내 포스트 개수는 `myPosts.length`로 계산

#### `myPosts` (array, 조건부)
- 내 포스트 리스트
- **제한 없음**: 내 포스트는 **모두 포함** (10개, 20개, 100개 등 개수 제한 없음)
- **중요**: 내 포스트가 10개를 넘어도 모두 포함되어야 함
- `postCount == 0`인 경우 빈 배열 `[]` 또는 필드 생략 가능
- `postCount > 0`이지만 내 포스트가 없는 경우 빈 배열 `[]`
- **친구 포스트는 이 API 응답에 포함되지 않음** (별도 API로 조회)

---

### 포스트 객체 (경량)

각 포스트는 목록 표시에 필요한 최소 정보만 포함합니다.

#### `id` (string, 필수)
- 포스트 고유 ID
- 예: `"post-123"`

#### `title` (string, 필수)
- 포스트 제목
- 예: `"오늘의 일기"`

#### `thumbnailUrl` (string, 필수)
- 썸네일 이미지 URL
- 절대 URL 또는 상대 경로
- 예: `"https://cdn.example.com/thumbnails/post-123.jpg"`
- **중요**: 클라이언트가 이 URL을 미리보기 이미지로 사용합니다

---

## 포스트 데이터 구조 규칙

### 규칙 요약
1. **내 포스트 (`myPosts`)**: **제한 없음, 모두 포함** (10개, 20개, 100개 등 개수 제한 없음)
2. **친구 포스트**: **초기 응답에 포함되지 않음**, 별도 API로만 조회
3. **포스트 개수 정보**:
   - `postCount`: 전체 포스트 개수 (내 포스트 + 친구 포스트)
   - 내 포스트 개수: `myPosts.length`로 계산
   - 친구 포스트 개수 = `postCount - myPosts.length`

### 데이터 구조 예시

```javascript
// 예시 1: 내 포스트 3개, 친구 포스트 7개
{
  postCount: 10,
  myPosts: [/* 3개 모두 포함 */]
  // friendsPosts 필드 없음
  // 내 포스트 개수: myPosts.length = 3
  // 친구 포스트 개수: postCount - myPosts.length = 7
}

// 예시 2: 내 포스트 15개, 친구 포스트 5개
{
  postCount: 20,
  myPosts: [/* 15개 모두 포함 */]
  // friendsPosts 필드 없음
  // 내 포스트 개수: myPosts.length = 15
  // 친구 포스트 개수: postCount - myPosts.length = 5
}

// 예시 3: 내 포스트 0개, 친구 포스트 10개
{
  postCount: 10,
  myPosts: []
  // friendsPosts 필드 없음
  // 내 포스트 개수: myPosts.length = 0
  // 친구 포스트 개수: postCount - myPosts.length = 10
}
```

### 친구 포스트 조회

- 친구 포스트는 **별도 API로만 조회** 가능
- 엔드포인트: `GET /api/weeks/{year}/{weekNumber}/friends-posts`
- 자세한 내용은 아래 "친구 포스트 조회 API" 섹션 참고

---

## 친구 포스트 조회 API

특정 주차의 친구 포스트를 조회하는 별도 API입니다.  
초기 응답에는 친구 포스트가 포함되지 않으므로, 필요 시 이 API를 호출해야 합니다.

### 엔드포인트

```
GET /api/weeks/{year}/{weekNumber}/friends-posts
```

### 요청 파라미터

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| `year` | int | 필수 | 연도 (경로 파라미터) |
| `weekNumber` | int | 필수 | 주차 번호 (경로 파라미터) |
| `page` | int | 선택 | 페이지 번호 (기본값: 0) |
| `size` | int | 선택 | 페이지 크기 (기본값: 20) |

### 예시 요청

```
GET /api/weeks/2026/13/friends-posts?page=0&size=20
```

### 성공 응답 (200 OK)

```json
{
  "year": 2026,
  "weekNumber": 13,
  "totalCount": 25,
  "page": 0,
  "size": 20,
  "hasMore": true,
  "posts": [
    {
      "id": "post-125",
      "title": "친구 포스트 1",
      "thumbnailUrl": "https://cdn.example.com/thumbnails/post-125.jpg"
    },
    {
      "id": "post-126",
      "title": "친구 포스트 2",
      "thumbnailUrl": "https://cdn.example.com/thumbnails/post-126.jpg"
    }
    // ... 최대 size개
  ]
}
```

### 필드 설명

#### `totalCount` (int, 필수)
- 해당 주차의 전체 친구 포스트 개수

#### `page` (int, 필수)
- 현재 페이지 번호 (0부터 시작)

#### `size` (int, 필수)
- 페이지 크기

#### `hasMore` (boolean, 필수)
- 더 많은 포스트가 있는지 여부
- `(page + 1) * size < totalCount`이면 `true`

#### `posts` (array, 필수)
- 친구 포스트 리스트
- 포스트 객체 구조는 위의 "포스트 객체 (경량)" 섹션과 동일

### 정렬

- 최신순 정렬 (최신 포스트가 첫 번째)
- 정렬 기준: `createdAt` 내림차순

### 에러 응답

#### 400 Bad Request

```json
{
  "error": "Invalid parameters",
  "message": "Year and weekNumber must be valid integers"
}
```

#### 404 Not Found

```json
{
  "error": "Week not found",
  "message": "No data available for the specified week"
}
```

---

## 주차 계산 규칙

### ISO 8601 기준

1. **주 시작일**: 월요일
2. **주 종료일**: 일요일
3. **첫 번째 주**: 해당 연도의 첫 번째 목요일을 포함하는 주
4. **총 주차 수**: 12월 28일이 포함된 주차 번호

### 주차 번호 계산 예시

- 2026년 1월 1일이 목요일이면 → 1주차
- 2026년 1월 1일이 금요일이면 → 2025년의 마지막 주차 또는 2026년 1주차 (ISO 규칙에 따라)

### 가입일 처리

- 가입일이 주의 중간(예: 금요일)이어도 **그 주 전체를 1칸으로 포함**
- 클라이언트에서 가입일을 기반으로 시작 주차를 계산합니다

---

## 데이터 정렬 및 순서

### `weeks` 배열
- `weekNumber` 기준 오름차순 정렬 (1, 2, 3, ..., weeksInYear)
- **모든 주차가 연속적으로 포함되어야 함** (빈 주차도 포함)

### `myPosts` 배열
- 최신순 정렬 권장 (최신 포스트가 첫 번째)
- 정렬 기준: `createdAt` 내림차순

---

## 에러 응답

### 400 Bad Request

#### 잘못된 연도 파라미터

```json
{
  "error": "Invalid year parameter",
  "message": "Year must be a valid integer"
}
```

**발생 조건**:
- `year` 파라미터가 정수가 아닌 경우
- `year` 파라미터가 4자리 숫자가 아닌 경우 (예: `26`, `20266`)

#### 범위를 벗어난 연도

```json
{
  "error": "Year out of range",
  "message": "Year must be between {minYear} and {currentYear}"
}
```

**발생 조건**:
- 가입일 이전 연도를 조회하려는 경우
- 현재 연도를 초과하는 미래 연도를 조회하려는 경우

### 404 Not Found

```json
{
  "error": "Data not found",
  "message": "No contribution data available for the specified year"
}
```

**발생 조건**:
- 해당 연도에 대한 데이터가 존재하지 않는 경우
- 가입일 이전 연도이지만 서버에서 빈 데이터 대신 404를 반환하는 경우

### 500 Internal Server Error

```json
{
  "error": "Internal server error",
  "message": "An error occurred while processing the request"
}
```

---

## 성능 고려사항

### 응답 크기 최적화

- 포스트 객체는 경량화되어 있음 (id, title, thumbnailUrl만)
- 친구 포스트는 초기 응답에 포함되지 않아 응답 크기가 더 작아짐
- 예상 응답 크기:
  - 일반적인 경우: 3-8 KB (gzip 압축 후)
  - 최악의 경우 (52주 모두 내 포스트 존재): 10-15 KB (gzip 압축 후)

### 캐싱 권장

- 연도별 데이터는 자주 변경되지 않으므로 캐싱 권장
- `ETag` 또는 `Cache-Control` 헤더 사용 권장

---

## 구현 체크리스트

### 필수 구현 사항

- [ ] 연도별 52-53주 전체 데이터 반환
- [ ] 모든 주차가 연속적으로 포함 (1부터 weeksInYear까지)
- [ ] `postCount`는 실제 전체 개수 (내 포스트 + 친구 포스트)
- [ ] `myPosts`는 모두 포함 (제한 없음, 10개 이상이어도 모두 포함)
- [ ] 내 포스트 개수는 `myPosts.length`로 계산
- [ ] `friendsPosts` 필드는 포함하지 않음 (별도 API로만 제공)
- [ ] 포스트 객체는 경량화 (id, title, thumbnailUrl만)
- [ ] ISO 8601 기준 주차 계산
- [ ] `weeksInYear` 정확히 계산 (52 또는 53)
- [ ] 친구 포스트 조회 API 구현 (필수)

### 선택 구현 사항

- [ ] `asOf` 필드 포함 (서버 시간 기준)
- [ ] 포스트 배열 최신순 정렬
- [ ] 응답 캐싱 (ETag, Cache-Control)

---

## 예시 시나리오

### 시나리오 1: 일반적인 경우

```json
{
  "year": 2026,
  "weeksInYear": 53,
  "timezone": "Asia/Seoul",
  "weekSystem": "ISO-8601",
  "weeks": [
    {
      "weekNumber": 1,
      "postCount": 0,
      "myPosts": []
    },
    {
      "weekNumber": 13,
      "postCount": 5,
      "myPosts": [
        {
          "id": "post-123",
          "title": "내 포스트",
          "thumbnailUrl": "https://cdn.example.com/thumbnails/post-123.jpg"
        }
      ]
      // friendsPosts 필드 없음 (별도 API로 조회)
    }
    // ... 나머지 주차들 (총 53개)
  ]
}
```

### 시나리오 2: 내 포스트가 있는 경우

```json
{
  "weekNumber": 20,
  "postCount": 15,
  "myPosts": [
    {
      "id": "post-200",
      "title": "내 포스트 1",
      "thumbnailUrl": "https://..."
    },
    {
      "id": "post-201",
      "title": "내 포스트 2",
      "thumbnailUrl": "https://..."
    },
    {
      "id": "post-202",
      "title": "내 포스트 3",
      "thumbnailUrl": "https://..."
    },
    {
      "id": "post-203",
      "title": "내 포스트 4",
      "thumbnailUrl": "https://..."
    },
    {
      "id": "post-204",
      "title": "내 포스트 5",
      "thumbnailUrl": "https://..."
    }
    // 내 포스트는 모두 포함 (5개)
  ]
  // friendsPosts 필드 없음
  // 친구 포스트 10개는 별도 API로 조회: GET /api/weeks/2026/20/friends-posts
}
```

### 시나리오 3: 내 포스트가 10개 이상인 경우

```json
{
  "weekNumber": 25,
  "postCount": 20,
  "myPosts": [
    {
      "id": "post-300",
      "title": "내 포스트 1",
      "thumbnailUrl": "https://..."
    },
    {
      "id": "post-301",
      "title": "내 포스트 2",
      "thumbnailUrl": "https://..."
    }
    // ... 내 포스트 15개 모두 포함 (제한 없음)
  ]
  // friendsPosts 필드 없음
  // 친구 포스트 5개는 별도 API로 조회: GET /api/weeks/2026/25/friends-posts
}
```

### 시나리오 4: 내 포스트가 없는 경우

```json
{
  "weekNumber": 30,
  "postCount": 10,
  "myPosts": []
  // friendsPosts 필드 없음
  // 친구 포스트 10개는 별도 API로 조회: GET /api/weeks/2026/30/friends-posts
}
```

---

## 클라이언트 사용 예시

### 연도 변경

클라이언트는 사용자가 연도를 변경할 때마다 해당 연도의 데이터를 조회하기 위해 API를 다시 호출해야 합니다.

```javascript
// 연도 선택 시
function changeYear(newYear) {
  // 연도 변경 시 API 재호출
  fetch(`/api/weeks/contributions?year=${newYear}`)
    .then(response => response.json())
    .then(data => {
      // 그리드 데이터 업데이트
      updateGrid(data);
    });
}

// 예시: 2025년 데이터 조회
changeYear(2025);
```

**주의사항**:
- 연도별로 별도의 API 호출이 필요합니다
- 연도 변경 시 이전 연도의 데이터는 캐시에 저장해두는 것을 권장합니다
- 현재 연도 기준 ±2년 범위 내에서만 연도 선택을 제공하는 것이 일반적입니다

### 미리보기 이미지 추출

클라이언트는 `myPosts[0]?.thumbnailUrl`을 미리보기 이미지로 사용합니다.  
친구 포스트의 미리보기는 별도 API 호출 후 사용할 수 있습니다.

### 포스트 개수 계산

```javascript
const myPostCount = week.myPosts.length; // 내 포스트 개수
const totalPostCount = week.postCount; // 전체 포스트 개수
const friendsPostCount = totalPostCount - myPostCount; // 친구 포스트 개수

// 친구 포스트가 있는지 확인
if (friendsPostCount > 0) {
  // 친구 포스트 조회 API 호출
  // GET /api/weeks/{year}/{weekNumber}/friends-posts
}
```

---

## 문의 및 피드백

API 구현 중 질문이나 이슈가 있으면 프론트엔드 팀에 문의해주세요.

