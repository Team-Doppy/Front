# 홈피드 API 명세서

## 개요
홈 화면의 피드 섹션 데이터를 제공하는 API입니다. 총 4개의 섹션으로 구성되어 있으며, 각 섹션은 독립적으로 데이터를 받아 표시됩니다.

---

## API 엔드포인트

### 홈피드 조회
```
GET /api/home/feed
```

**요청 헤더:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

**응답 코드:**
- `200 OK`: 성공
- `401 Unauthorized`: 인증 실패
- `500 Internal Server Error`: 서버 오류

---

## 응답 데이터 구조

### 전체 응답 형식
```json
{
  "section1": {
    "headerLine1": [...],
    "headerLine2": [...],
    "cards": [...]
  },
  "section2": {
    "slides": [...]
  },
  "friendsPosts": {
    "headerLine2": [...],
    "cards": [...]
  },
  "recommendedFriends": {
    "header": [...],
    "friends": [...]
  }
}
```

---

## 섹션별 상세 명세

### 1. Section1: 시간/기간 개념 카드 섹션

**설명:** 특정 기간(작년 여름, 올해 봄, 이번주, 저번주 등)의 포스트를 카드 형태로 표시합니다.

**빈 상태 처리:**
- 데이터가 없으면 헤더에 빈 상태 메시지 표시 + ">" 버튼 표시
- 빈 상태 메시지는 클라이언트에서 로케일 기반으로 처리

**JSON 구조:**
```json
{
  "section1": {
    "headerLine1": [
      {
        "text": "잼얘기 많았던.",
        "bold": false
      }
    ],
    "headerLine2": [
      {
        "text": "지난주",
        "bold": true
      }
    ],
    "cards": [
      {
        "postId": "post_123",
        "imageUrl": "https://example.com/image1.jpg",
        "title": [
          {
            "text": "바다 보며 ",
            "bold": false
          },
          {
            "text": "산책",
            "bold": true
          }
        ],
        "subtitle": "추가 설명 텍스트 (옵션)"
      }
    ]
  }
}
```

**필드 설명:**

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `headerLine1` | Array | 선택 | 섹션 헤더 첫 번째 줄 (텍스트 청크 배열) |
| `headerLine2` | Array | 필수 | 섹션 헤더 두 번째 줄 (텍스트 청크 배열) |
| `cards` | Array | 필수 | 카드 데이터 배열 (빈 배열 가능) |

**텍스트 청크 (HomeTextChunk):**
| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `text` | String | 필수 | 표시할 텍스트 |
| `bold` | Boolean | 필수 | 볼드 여부 (true: 볼드, false: 일반) |

**카드 데이터 (Section1CardData):**
| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `postId` | String | 필수 | 포스트 ID (클릭 시 상세 페이지 이동용) |
| `imageUrl` | String | 필수 | 카드 이미지 URL |
| `title` | Array | 선택 | 카드 제목 (텍스트 청크 배열, 없으면 이미지만 표시) |
| `subtitle` | String | 선택 | 서브텍스트 (카드 하단에 표시될 추가 설명) |

---

### 2. Section2: 군집 캐러셀

**설명:** 특정 주제로 군집화된 포스트들을 캐러셀 형태로 표시합니다. (예: "도파민 터졌던", "왕창 마셨던" 등)

**빈 상태 처리:**
- 데이터가 없으면 섹션 전체를 숨김 (UI에서 완전히 제거)

**JSON 구조:**
```json
{
  "section2": {
    "slides": [
      {
        "groupId": "group_123",
        "imageUrl": "https://example.com/slide1.jpg",
        "line1": [
          {
            "text": "2주 연속 기록",
            "bold": false
          }
        ],
        "line2": [
          {
            "text": "도파민 ",
            "bold": false
          },
          {
            "text": "터졌던",
            "bold": true
          }
        ]
      }
    ]
  }
}
```

**필드 설명:**

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `slides` | Array | 필수 | 슬라이드 데이터 배열 (빈 배열 가능) |

**슬라이드 데이터 (Section2SlideData):**
| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `groupId` | String | 필수 | 그룹 ID (클릭 시 그룹 상세 페이지 이동용) |
| `imageUrl` | String | 필수 | 슬라이드 배경 이미지 URL |
| `line1` | Array | 필수 | 첫 번째 줄 텍스트 (텍스트 청크 배열) |
| `line2` | Array | 필수 | 두 번째 줄 텍스트 (텍스트 청크 배열) |

---

### 3. Friends Posts: 친구 글 섹션

**설명:** 최근 친구들이 작성한 포스트를 Section1과 동일한 카드 형태로 표시합니다.

**빈 상태 처리:**
- 데이터가 없으면 섹션 전체를 숨김 (UI에서 완전히 제거)

**JSON 구조:**
```json
{
  "friendsPosts": {
    "headerLine2": [
      {
        "text": "요근래",
        "bold": true
      },
      {
        "text": " 내 친구들",
        "bold": false
      }
    ],
    "cards": [
      {
        "postId": "post_456",
        "imageUrl": "https://example.com/friend_post1.jpg",
        "title": [
          {
            "text": "하늘이 ",
            "bold": false
          },
          {
            "text": "미쳤던 날",
            "bold": true
          }
        ],
        "friendName": "친구이름 (옵션)",
        "subtitle": null
      }
    ]
  }
}
```

**필드 설명:**

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `headerLine2` | Array | 필수 | 섹션 헤더 두 번째 줄 (텍스트 청크 배열) |
| `cards` | Array | 필수 | 친구 포스트 카드 데이터 배열 (빈 배열 가능) |

**카드 데이터:** Section1과 동일한 구조이며, 추가로 `friendName` 필드를 사용할 수 있습니다. `postId`, `imageUrl`, `title`, `subtitle` 필드가 포함되어야 합니다.

---

### 4. Recommended Friends: 친구 추천 섹션

**설명:** 추천 친구 목록을 원형 아바타 형태로 표시합니다.

**빈 상태 처리:**
- 데이터가 없으면 섹션 전체를 숨김 (UI에서 완전히 제거)
- 헤더는 클라이언트에서 로케일 기반으로 자동 처리 ("아는 친구인가요?" / "Do you know them?")

**JSON 구조:**
```json
{
  "recommendedFriends": {
    "header": [],  // 클라이언트에서 처리하므로 빈 배열 또는 무시
    "friends": [
      {
        "userId": "user_789",
        "username": "affection_jh",
        "avatarUrl": "https://example.com/avatar1.jpg",
        "hasUnreadStory": true
      }
    ]
  }
}
```

**필드 설명:**

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `header` | Array | 선택 | 헤더는 클라이언트에서 처리하므로 빈 배열 또는 무시 가능 |
| `friends` | Array | 필수 | 추천 친구 데이터 배열 (빈 배열 가능) |

**친구 데이터 (Section3FriendData):**
| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `userId` | String | 필수 | 사용자 ID |
| `username` | String | 필수 | 사용자 이름 (아바타 아래 표시) |
| `avatarUrl` | String | 필수 | 프로필 이미지 URL |
| `hasUnreadStory` | Boolean | 필수 | 읽지 않은 스토리가 있는지 여부 (true면 원형 테두리 표시) |

---

## 전체 JSON 예시

### 예시 1: 모든 섹션에 데이터가 있는 경우

```json
{
  "section1": {
    "headerLine1": [
      {
        "text": "잼얘기 많았던.",
        "bold": false
      }
    ],
    "headerLine2": [
      {
        "text": "지난주",
        "bold": true
      }
    ],
    "cards": [
      {
        "postId": "post_123",
        "imageUrl": "https://example.com/image1.jpg",
        "title": [
          {
            "text": "바다 보며 ",
            "bold": false
          },
          {
            "text": "산책",
            "bold": true
          }
        ],
        "subtitle": "추가 설명"
      },
      {
        "postId": "post_124",
        "imageUrl": "https://example.com/image2.jpg",
        "title": [
          {
            "text": "하늘이 ",
            "bold": false
          },
          {
            "text": "미쳤던 날",
            "bold": true
          }
        ],
        "subtitle": null
      }
    ]
  },
  "section2": {
    "slides": [
      {
        "groupId": "group_123",
        "imageUrl": "https://example.com/slide1.jpg",
        "line1": [
          {
            "text": "2주 연속 기록",
            "bold": false
          }
        ],
        "line2": [
          {
            "text": "도파민 ",
            "bold": false
          },
          {
            "text": "터졌던",
            "bold": true
          }
        ]
      },
      {
        "groupId": "group_124",
        "imageUrl": "https://example.com/slide2.jpg",
        "line1": [
          {
            "text": "이번 주 하이라이트",
            "bold": false
          }
        ],
        "line2": [
          {
            "text": "기록이 ",
            "bold": false
          },
          {
            "text": "쌓이는 중",
            "bold": true
          }
        ]
      }
    ]
  },
  "friendsPosts": {
    "headerLine2": [
      {
        "text": "요근래",
        "bold": true
      },
      {
        "text": " 내 친구들",
        "bold": false
      }
    ],
    "cards": [
      {
        "postId": "post_456",
        "imageUrl": "https://example.com/friend_post1.jpg",
        "title": [
          {
            "text": "바다 보며 ",
            "bold": false
          },
          {
            "text": "산책",
            "bold": true
          }
        ],
        "friendName": "친구이름",
        "subtitle": null
      }
    ]
  },
  "recommendedFriends": {
    "header": [],
    "friends": [
      {
        "userId": "user_789",
        "username": "affection_jh",
        "avatarUrl": "https://example.com/avatar1.jpg",
        "hasUnreadStory": true
      },
      {
        "userId": "user_790",
        "username": "akdslk.dk",
        "avatarUrl": "https://example.com/avatar2.jpg",
        "hasUnreadStory": false
      }
    ]
  }
}
```

### 예시 2: Section1만 데이터가 있고 나머지는 빈 경우

```json
{
  "section1": {
    "headerLine1": [
      {
        "text": "잼얘기 많았던.",
        "bold": false
      }
    ],
    "headerLine2": [
      {
        "text": "지난주",
        "bold": true
      }
    ],
    "cards": [
      {
        "postId": "post_123",
        "imageUrl": "https://example.com/image1.jpg",
        "title": [
          {
            "text": "바다 보며 ",
            "bold": false
          },
          {
            "text": "산책",
            "bold": true
          }
        ],
        "subtitle": null
      }
    ]
  },
  "section2": {
    "slides": []
  },
  "friendsPosts": {
    "headerLine2": [
      {
        "text": "요근래",
        "bold": true
      },
      {
        "text": " 내 친구들",
        "bold": false
      }
    ],
    "cards": []
  },
  "recommendedFriends": {
    "header": [],
    "friends": []
  }
}
```

### 예시 3: 모든 섹션이 빈 경우

```json
{
  "section1": {
    "headerLine1": null,
    "headerLine2": [],
    "cards": []
  },
  "section2": {
    "slides": []
  },
  "friendsPosts": {
    "headerLine2": [],
    "cards": []
  },
  "recommendedFriends": {
    "header": [],
    "friends": []
  }
}
```

---

## 빈 상태 처리 규칙

### Section1 (시간/기간 카드)
- `cards`가 빈 배열이면:
  - 헤더에 빈 상태 메시지 표시 (클라이언트에서 로케일 기반 처리)
  - ">" 버튼 표시하여 글 작성 유도
  - 섹션은 표시됨

### Section2 (군집 캐러셀)
- `slides`가 빈 배열이면:
  - 섹션 전체를 숨김 (UI에서 완전히 제거)

### Friends Posts (친구 글)
- `cards`가 빈 배열이면:
  - 섹션 전체를 숨김 (UI에서 완전히 제거)

### Recommended Friends (친구 추천)
- `friends`가 빈 배열이면:
  - 섹션 전체를 숨김 (UI에서 완전히 제거)
  - 헤더는 클라이언트에서 처리 ("아는 친구인가요?" / "Do you know them?")

---

## 주의사항

1. **텍스트 청크 배열**: 헤더나 제목에서 볼드/일반 텍스트를 섞어서 사용할 수 있습니다. 각 청크는 `text`와 `bold` 필드를 가집니다.

2. **이미지 URL**: 모든 이미지 URL은 HTTPS를 사용해야 하며, CDN을 통해 제공되는 것이 권장됩니다.

3. **빈 배열 vs null**: 
   - 빈 배열 `[]`을 사용하세요. `null`은 사용하지 않습니다.
   - `section1.headerLine1`만 예외적으로 `null` 가능 (선택 필드)

4. **로케일**: 
   - 헤더 텍스트는 서버에서 내려주는 그대로 사용됩니다.
   - 빈 상태 메시지와 친구 추천 헤더는 클라이언트에서 로케일 기반으로 처리됩니다.

5. **포스트 ID**: 각 카드는 `postId`를 필수로 포함해야 하며, 클릭 시 상세 페이지로 이동할 때 사용됩니다. 상세 정보는 별도 API로 조회합니다.

---

## 에러 응답

### 401 Unauthorized
```json
{
  "error": "Unauthorized",
  "message": "인증 토큰이 유효하지 않습니다."
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal Server Error",
  "message": "서버 오류가 발생했습니다."
}
```

---

## 추가 참고사항

- 모든 날짜/시간은 ISO 8601 형식을 권장합니다.
- 이미지 최적화: 썸네일 이미지는 적절한 크기로 리사이즈하여 제공하는 것이 좋습니다.
- 캐싱: 클라이언트에서 적절한 캐싱 전략을 사용하므로, 서버에서도 Cache-Control 헤더를 적절히 설정해주세요.

