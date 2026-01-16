# 홈피드 API - 섹션별 JSON 예시

이 문서는 각 섹션별로 독립적인 JSON 예시를 제공합니다.

---

## Section1: 시간/기간 개념 카드

### 기본 구조
```json
{
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
      "subtitle": "추가 설명 텍스트"
    }
  ]
}
```

### headerLine1이 없는 경우
```json
{
  "headerLine1": null,
  "headerLine2": [
    {
      "text": "이번주",
      "bold": true
    }
  ],
  "cards": [...]
}
```

### 빈 상태 (cards가 빈 배열)
```json
{
  "headerLine1": null,
  "headerLine2": [],
  "cards": []
}
```

### 여러 카드 예시
```json
{
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
    },
    {
      "postId": "post_125",
      "imageUrl": "https://example.com/image3.jpg",
      "title": [
        {
          "text": "기억에 ",
          "bold": false
        },
        {
          "text": "남는 순간",
          "bold": true
        }
      ],
      "subtitle": null
    }
  ]
}
```

### title이 없는 경우 (이미지만 표시)
```json
{
  "postId": "post_126",
  "imageUrl": "https://example.com/image4.jpg",
  "title": null,
  "subtitle": null
}
```

---

## Section2: 군집 캐러셀

### 기본 구조
```json
{
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
```

### 여러 슬라이드 예시
```json
{
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
    },
    {
      "groupId": "group_125",
      "imageUrl": "https://example.com/slide3.jpg",
      "line1": [
        {
          "text": "왕창 마셨던",
          "bold": false
        }
      ],
      "line2": [
        {
          "text": "그 ",
          "bold": false
        },
        {
          "text": "날들",
          "bold": true
        }
      ]
    }
  ]
}
```

### 빈 상태 (slides가 빈 배열)
```json
{
  "slides": []
}
```

---

## Friends Posts: 친구 글 섹션

### 기본 구조
```json
{
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
}
```

### 여러 친구 글 예시
```json
{
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
      "friendName": "친구이름1",
      "subtitle": null
    },
    {
      "postId": "post_457",
      "imageUrl": "https://example.com/friend_post2.jpg",
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
      "friendName": "친구이름2",
      "subtitle": null
    },
    {
      "postId": "post_458",
      "imageUrl": "https://example.com/friend_post3.jpg",
      "title": [
        {
          "text": "기억에 ",
          "bold": false
        },
        {
          "text": "남는 순간",
          "bold": true
        }
      ],
      "friendName": "친구이름3",
      "subtitle": null
    }
  ]
}
```

### 빈 상태 (cards가 빈 배열)
```json
{
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
}
```

---

## Recommended Friends: 친구 추천 섹션

### 기본 구조
```json
{
  "header": [],
  "friends": [
    {
      "userId": "user_789",
      "username": "affection_jh",
      "avatarUrl": "https://example.com/avatar1.jpg",
      "hasUnreadStory": true
    }
  ]
}
```

### 여러 친구 추천 예시
```json
{
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
    },
    {
      "userId": "user_791",
      "username": "doppy_user",
      "avatarUrl": "https://example.com/avatar3.jpg",
      "hasUnreadStory": true
    },
    {
      "userId": "user_792",
      "username": "friend_user",
      "avatarUrl": "https://example.com/avatar4.jpg",
      "hasUnreadStory": false
    }
  ]
}
```

### 빈 상태 (friends가 빈 배열)
```json
{
  "header": [],
  "friends": []
}
```

### hasUnreadStory 예시
- `hasUnreadStory: true` → 원형 테두리 표시 (스토리가 있음을 나타냄)
- `hasUnreadStory: false` → 일반 원형 아바타

```json
{
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
```

---

## 전체 응답 통합 예시

### 모든 섹션에 데이터가 있는 경우
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
        "friendName": "친구이름"
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
      }
    ]
  }
}
```

---

## 참고사항

1. **텍스트 청크 배열**: 볼드와 일반 텍스트를 섞어서 사용할 수 있습니다.
   ```json
   [
     { "text": "일반 텍스트 ", "bold": false },
     { "text": "볼드 텍스트", "bold": true }
   ]
   ```

2. **빈 배열**: 데이터가 없을 때는 빈 배열 `[]`을 사용하세요. `null`은 사용하지 않습니다.

3. **이미지 URL**: 모든 이미지는 HTTPS를 사용해야 하며, CDN을 통해 제공되는 것이 권장됩니다.

4. **헤더 처리**: 
   - Section1의 `headerLine1`은 선택 필드 (null 가능)
   - Recommended Friends의 `header`는 클라이언트에서 처리하므로 빈 배열로 보내면 됩니다.

