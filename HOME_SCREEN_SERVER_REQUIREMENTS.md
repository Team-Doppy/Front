# 홈 화면 서버 구현 필요 사항

## 📋 개요

홈 화면 구성 요소 중 서버 구현이 필요한 부분을 최소 API로 정리합니다.

---

## ✅ 이미 구현된 부분 (서버 API 사용 중)

### 1. **친구 포스트** (`FriendProvider`)
- **API**: `GET /api/friends/bundle`
- **상태**: ✅ 구현 완료
- **설명**: `friendPosts` 필드에서 친구 포스트 목록을 가져옴
- **사용 위치**: "요새 내 친구들" 섹션

### 2. **친구 추천** (`FriendProvider`)
- **API**: `GET /api/friends/bundle`
- **상태**: ✅ 구현 완료
- **설명**: `friendRecommendations` 필드에서 친구 추천 목록을 가져옴
- **사용 위치**: "아는 곰신인가요?" 섹션

### 3. **프로필 피드** (`MyProfileFeedProvider`)
- **API**: `GET /api/profile/feed/{username}`
- **상태**: ✅ 구현 완료
- **설명**: `lifePhase` 파라미터로 필터링 가능
- **사용 위치**: "사회에서의 추억" 섹션 (클라이언트 측 필터링)

---

## ❌ 서버 구현 필요한 부분

### 1. **나에게 온 편지** (`SupportPostsSection`)

**현재 상태:**
- 하드코딩된 mock 데이터 사용
- `lib/pages/home/home_widgets.dart:2528-2566`

**필요한 API:**
```
GET /api/posts/received-support
```

**요청 파라미터:**
| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| `page` | integer | ❌ | 페이지 번호 (기본값: 0) |
| `size` | integer | ❌ | 페이지 크기 (기본값: 5) |

**응답 형식:**
```json
{
  "content": [
    {
      "id": "post_123",
      "thumbnailImageUrl": "https://...",
      "title": "이번주 나에게 온 편지!",
      "subtitle": "내 여자친구가 응원해줬어요",
      "author": "girlfriend_user",
      "authorProfileImageUrl": "https://...",
      "createdAt": "2025-01-15T10:00:00Z"
    }
  ],
  "totalElements": 10,
  "hasNext": true
}
```

**설명:**
- 군인 사용자가 받은 `letter` 모드 포스트 목록
- 발송 대상이 현재 사용자인 포스트만 반환
- 최신순 정렬
- 홈 화면에서는 최대 5개만 표시

**최소 구현:**
- `GET /api/posts/received-support?size=5` (페이지네이션 불필요)

---

### 2. **진급 리포트** (`PromotionReportCTASection`)

**현재 상태:**
- 하드코딩된 mock 이미지와 데이터 사용
- `lib/pages/home/home_widgets.dart:2568-2662`
- 리포트 존재 여부를 확인할 수 없음

**필요한 API:**
```
GET /api/reports/promotion/status
```

**요청 파라미터:**
없음 (JWT에서 현재 사용자 정보 추출)

**응답 형식:**
```json
{
  "hasReport": true,
  "report": {
    "id": "report_123",
    "thumbnailImageUrl": "https://...",
    "title": "진급 리포트 보기",
    "subtitle": "이번주 나의 발전",
    "createdAt": "2025-01-15T10:00:00Z"
  }
}
```

또는 리포트가 없을 때:
```json
{
  "hasReport": false
}
```

**설명:**
- 리포트 존재 여부만 확인 (홈 화면 CTA 표시 여부 결정)
- 리포트가 있을 때만 CTA 섹션 표시
- 리포트 상세 정보는 리포트 화면에서 별도 API 호출

**최소 구현:**
- `GET /api/reports/promotion/status` (boolean만 반환해도 됨)

---

### 3. **사회에서의 추억** (입대전 + 휴가 포스트)

**현재 상태:**
- `MyProfileFeedProvider`에서 전체 포스트를 가져온 후 클라이언트 측에서 필터링
- `lib/pages/home/military_home_content.dart:287-295`
- 필터링 조건: `lifePhase == 'LEAVE_OR_PRE_ENLISTMENT'`

**현재 API:**
```
GET /api/profile/feed/{username}?lifePhase=LEAVE_OR_PRE_ENLISTMENT
```

**상태:**
- ✅ API는 이미 `lifePhase` 파라미터를 지원함
- ❌ 하지만 현재 클라이언트에서 필터링 중

**최적화 제안:**
- 서버에서 `lifePhase=LEAVE_OR_PRE_ENLISTMENT` 파라미터로 필터링하도록 변경
- 클라이언트 측 필터링 제거

**설명:**
- 입대 후 홈 화면에서만 표시
- 입대전 포스트와 휴가 중 포스트만 포함
- 최대 5개만 표시

**최소 구현:**
- 기존 API 활용: `GET /api/profile/feed/{username}?lifePhase=LEAVE_OR_PRE_ENLISTMENT&size=5`
- 클라이언트 코드 수정만 필요 (서버 구현 불필요)

---

## 📊 API 우선순위

### 우선순위 1 (필수)
1. **나에게 온 편지 API** (`GET /api/posts/received-support`)
   - 현재 하드코딩된 데이터를 실제 데이터로 교체
   - 홈 화면 핵심 기능

### 우선순위 2 (권장)
2. **진급 리포트 상태 API** (`GET /api/reports/promotion/status`)
   - 리포트 존재 여부 확인
   - 리포트가 없을 때 CTA 섹션 숨김 처리

### 우선순위 3 (최적화)
3. **사회에서의 추억 필터링**
   - 기존 API 활용 가능
   - 클라이언트 코드 수정만 필요

---

## 🎯 최소 API 구현 제안

### 단일 API로 통합 가능한 경우

**옵션 1: 홈 화면 번들 API**
```
GET /api/home/bundle
```

**응답:**
```json
{
  "supportPosts": [
    {
      "id": "post_123",
      "thumbnailImageUrl": "https://...",
      "title": "이번주 나에게 온 편지!",
      "subtitle": "내 여자친구가 응원해줬어요",
      "author": "girlfriend_user",
      "authorProfileImageUrl": "https://..."
    }
  ],
  "promotionReport": {
    "hasReport": true,
    "thumbnailImageUrl": "https://...",
    "title": "진급 리포트 보기",
    "subtitle": "이번주 나의 발전"
  },
  "socialMemoryPosts": [
    {
      "id": "post_456",
      "thumbnailImageUrl": "https://...",
      "title": "입대 전 추억",
      "lifePhase": "LEAVE_OR_PRE_ENLISTMENT"
    }
  ]
}
```

**장점:**
- 단일 API 호출로 모든 홈 화면 데이터 로드
- 네트워크 요청 최소화
- 캐싱 용이

**단점:**
- 각 섹션별 독립적인 새로고침 불가
- API 응답 크기 증가

---

## 📝 구현 체크리스트

### 서버 구현
- [ ] `GET /api/posts/received-support` API 구현
- [ ] `GET /api/reports/promotion/status` API 구현 (또는 번들 API에 포함)
- [ ] `GET /api/profile/feed/{username}?lifePhase=LEAVE_OR_PRE_ENLISTMENT` 검증

### 클라이언트 구현
- [ ] `SupportPostsSection`에서 실제 API 호출하도록 수정
- [ ] `PromotionReportCTASection`에서 리포트 존재 여부 확인 로직 추가
- [ ] "사회에서의 추억" 섹션에서 서버 필터링 사용하도록 수정

---

## 🔍 참고사항

### 이미 구현된 API 활용
- **친구 포스트**: `GET /api/friends/bundle` (이미 사용 중)
- **친구 추천**: `GET /api/friends/bundle` (이미 사용 중)
- **프로필 피드**: `GET /api/profile/feed/{username}` (이미 사용 중, `lifePhase` 파라미터 지원)

### 불필요한 서버 구현
- **ThisWeekWriteButton**: 로컬 처리만 필요 (서버 불필요)
- **GirlfriendWriteCTASection**: 로컬 처리만 필요 (서버 불필요)
- **PreEnlistmentCTASection**: 로컬 처리만 필요 (서버 불필요)

---

## 📌 요약

**서버 구현 필수:**
1. 나에게 온 편지 API (`GET /api/posts/received-support`)
2. 진급 리포트 상태 API (`GET /api/reports/promotion/status`)

**클라이언트 수정만 필요:**
3. "사회에서의 추억" 섹션에서 서버 필터링 사용 (`lifePhase` 파라미터)

**최소 API 수:**
- **옵션 1**: 2개 API (나에게 온 편지, 진급 리포트)
- **옵션 2**: 1개 API (홈 화면 번들 API로 통합)

