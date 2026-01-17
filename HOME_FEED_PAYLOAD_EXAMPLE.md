# 홈피드 Payload 예시

## 서버 응답 JSON 구조

서버에서 `HomeFeedPayload`로 변환할 JSON 응답 예시입니다.

### 전체 응답 형식

```json
{
  "greetingMessage": {
    "line1": [
      {
        "text": "3주 연속 기록",
        "bold": true
      }
    ],
    "line2": [
      {
        "text": "이번 주도 한 번만"
      }
    ]
  },
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
  },
  "section2": {
    "slides": [
      {
        "slideId": "slide_1",
        "title": "군집 제목",
        "posts": [
          {
            "postId": "post_456",
            "imageUrl": "https://example.com/image2.jpg"
          }
        ]
      }
    ]
  },
  "friendsPosts": {
    "headerLine2": [
      {
        "text": "친구들의 글",
        "bold": true
      }
    ],
    "cards": [
      {
        "postId": "post_789",
        "imageUrl": "https://example.com/image3.jpg",
        "title": [
          {
            "text": "친구 글 제목"
          }
        ]
      }
    ]
  },
  "recommendedFriends": {
    "header": [
      {
        "text": "친구 추천",
        "bold": false
      }
    ],
    "friends": [
      {
        "userId": "user_123",
        "username": "friend_user",
        "profileImageUrl": "https://example.com/profile.jpg",
        "alias": "친구 별명"
      }
    ]
  }
}
```

## 인사말 (greetingMessage) 상세

### 구조
```json
{
  "greetingMessage": {
    "line1": [
      {
        "text": "텍스트 내용",
        "bold": true  // 선택적, 기본값 false
      }
    ],
    "line2": [
      {
        "text": "텍스트 내용",
        "bold": false
      }
    ]
  }
}
```

### 예시 케이스

#### 1. 기본 상태 (이번 주 채워짐)
```json
{
  "greetingMessage": {
    "line1": [
      {
        "text": "3주 연속 기록",
        "bold": true
      }
    ],
    "line2": [
      {
        "text": "이번 주도 한 번만"
      }
    ]
  }
}
```

#### 2. 이번 주 비어있음
```json
{
  "greetingMessage": {
    "line1": [
      {
        "text": "이번 주는 조용하네요"
      }
    ],
    "line2": [
      {
        "text": "한 번만 채워도 돼요"
      }
    ]
  }
}
```

#### 3. 공백 후 복귀
```json
{
  "greetingMessage": {
    "line1": [
      {
        "text": "5주차로 돌아왔어요"
      }
    ],
    "line2": [
      {
        "text": "이번 주부터 다시"
      }
    ]
  }
}
```

#### 4. 완전 빈 그리드
```json
{
  "greetingMessage": {
    "line1": [
      {
        "text": "처음은 가볍게"
      }
    ],
    "line2": [
      {
        "text": "첫 주를 채워봐요"
      }
    ]
  }
}
```

## 클라이언트에서의 처리

### 1. 서버 응답 파싱
```dart
// 서버 응답을 HomeFeedPayload로 변환
final payload = HomeFeedPayload(
  greetingMessage: HomeGreetingMessage(
    line1: json['greetingMessage']['line1']
        .map((chunk) => HomeGreetingChunk(
              chunk['text'],
              bold: chunk['bold'] ?? false,
            ))
        .toList(),
    line2: json['greetingMessage']['line2']
        .map((chunk) => HomeGreetingChunk(
              chunk['text'],
              bold: chunk['bold'] ?? false,
            ))
        .toList(),
  ),
  // ... 나머지 섹션들
);
```

### 2. 로컬 보상 멘트 오버라이드
```dart
// 이번 주 방금 채웠을 때만 로컬 보상 멘트로 오버라이드
final localRewardMessage = _justFilledThisWeek
    ? const HomeGreetingMessage(
        line1: [HomeGreetingChunk('이번 주, 체크 완료')],
        line2: [HomeGreetingChunk('잘 했어요')],
      )
    : null;

final homeData = _homeFeedService.buildHomeData(
  payload: payload,
  // ...
  localRewardMessage: localRewardMessage, // null이면 서버 메시지 사용
);
```

## 주의사항

1. **인사말은 항상 2줄**: `line1`과 `line2` 모두 필수
2. **각 줄은 배열**: 여러 청크로 구성 가능 (bold 처리 등)
3. **로컬 오버라이드**: `_justFilledThisWeek == true`일 때만 로컬 보상 멘트 사용
4. **서버 로직**: 서버에서 사용자 상태(연속 주차, 공백 기간 등)를 계산해서 적절한 인사말 반환

