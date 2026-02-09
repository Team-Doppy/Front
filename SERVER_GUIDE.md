# 서버 측 변경 가이드 - 군도피 모드

## 📋 개요

**서버 중심 구조**: 입대일, 진급일, 휴가 정보 등 모든 군인 관련 데이터는 서버에서 관리합니다.
- 클라이언트는 서버에서 받은 데이터를 그대로 사용합니다
- 클라이언트에서 계산하거나 로컬에서 관리하지 않습니다
- 모든 변경사항은 서버에 전송하여 서버에서 관리합니다

이 가이드는 클라이언트에서 구현한 군인 정보 기능을 서버에서 지원하기 위한 변경 가이드입니다.

---

## 1. 데이터베이스 스키마 변경

### 1.1 User 테이블에 military_info 필드 추가

```sql
-- 예시: PostgreSQL
ALTER TABLE users ADD COLUMN military_info JSONB;

-- 또는 별도 테이블로 분리 (권장)
CREATE TABLE military_infos (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_type VARCHAR(20) NOT NULL CHECK (user_type IN ('military', 'girlfriend', 'family')),
    branch VARCHAR(20) NOT NULL CHECK (branch IN ('army', 'navy', 'airForce', 'marines', 'other')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('beforeEnlistment', 'afterEnlistment')),
    enlistment_date TIMESTAMP,
    current_rank VARCHAR(20) CHECK (current_rank IN ('trainee', 'private', 'privateFirstClass', 'corporal', 'sergeant')),
    planned_enlistment_date TIMESTAMP,
    manual_promotion_dates JSONB, -- { "trainee": "2024-01-01T00:00:00Z", ... }
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id)
);

-- 곰신/가족 모드 연결 관계 테이블
CREATE TABLE military_connections (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- 곰신/가족 사용자
    connected_military_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- 연결된 군인
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, connected_military_user_id)
);

-- 휴가 정보 테이블 (서버에서 관리)
CREATE TABLE vacations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    type VARCHAR(50), -- 'annual', 'reward', 'sick' 등
    memo TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    CHECK (end_date >= start_date)
);

-- 인덱스 추가
CREATE INDEX idx_military_infos_user_id ON military_infos(user_id);
CREATE INDEX idx_military_connections_user_id ON military_connections(user_id);
CREATE INDEX idx_military_connections_connected_id ON military_connections(connected_military_user_id);
CREATE INDEX idx_vacations_user_id ON vacations(user_id);
CREATE INDEX idx_vacations_dates ON vacations(user_id, start_date, end_date);
```

---

## 2. API 엔드포인트 변경

### 2.1 GET /api/users/bundle

**응답에 militaryInfo 추가**

```json
{
  "username": "user123",
  "alias": "별명",
  "profileImageUrl": "https://...",
  "onboardingCompleted": true,
  "militaryInfo": {
    "userType": "military",
    "branch": "army",
    "status": "afterEnlistment",
    "enlistmentDate": "2024-01-15T00:00:00Z",
    "currentRank": "private",
    "plannedEnlistmentDate": null,
    "connectedMilitaryUserIds": null,
    "manualPromotionDates": {
      "private": "2024-02-01T00:00:00Z"
    }
  }
}
```

**곰신/가족 모드인 경우:**

```json
{
  "militaryInfo": {
    "userType": "girlfriend",
    "branch": "army",
    "status": "afterEnlistment",
    "enlistmentDate": null,
    "currentRank": null,
    "connectedMilitaryUserIds": ["military_user_123"]
  }
}
```

**구현 예시 (Python/Django):**

```python
def get_user_bundle(request):
    user = request.user
    military_info = get_military_info(user)
    
    return Response({
        "username": user.username,
        "alias": user.alias,
        "profileImageUrl": user.profile_image_url,
        "onboardingCompleted": user.onboarding_completed,
        "militaryInfo": serialize_military_info(military_info) if military_info else None,
    })

def serialize_military_info(military_info):
    result = {
        "userType": military_info.user_type,
        "branch": military_info.branch,
        "status": military_info.status,
    }
    
    if military_info.enlistment_date:
        result["enlistmentDate"] = military_info.enlistment_date.isoformat()
    if military_info.current_rank:
        result["currentRank"] = military_info.current_rank
    if military_info.planned_enlistment_date:
        result["plannedEnlistmentDate"] = military_info.planned_enlistment_date.isoformat()
    if military_info.manual_promotion_dates:
        result["manualPromotionDates"] = {
            k: v.isoformat() if isinstance(v, datetime) else v
            for k, v in military_info.manual_promotion_dates.items()
        }
    
    # 곰신/가족 모드: 연결된 군인 ID 목록
    if military_info.user_type in ['girlfriend', 'family']:
        connections = MilitaryConnection.objects.filter(user_id=military_info.user_id)
        result["connectedMilitaryUserIds"] = [
            conn.connected_military_user.username
            for conn in connections
        ]
    
    return result
```

---

### 2.2 PUT /api/profile/info

**요청에 militaryInfo 추가 지원**

```json
{
  "alias": "별명",
  "militaryInfo": {
    "userType": "military",
    "branch": "army",
    "status": "afterEnlistment",
    "enlistmentDate": "2024-01-15T00:00:00Z",
    "currentRank": "private",
    "plannedEnlistmentDate": null,
    "connectedMilitaryUserIds": null,
    "manualPromotionDates": {
      "private": "2024-02-01T00:00:00Z"
    }
  }
}
```

**구현 예시:**

```python
@api_view(['PUT'])
def update_profile_info(request):
    user = request.user
    data = request.data
    
    # 기존 alias 업데이트
    if 'alias' in data:
        user.alias = data['alias']
        user.save()
    
    # militaryInfo 업데이트
    if 'militaryInfo' in data:
        military_info_data = data['militaryInfo']
        update_military_info(user, military_info_data)
    
    return Response({"success": True})

def update_military_info(user, data):
    military_info, created = MilitaryInfo.objects.get_or_create(user_id=user.id)
    
    military_info.user_type = data['userType']
    military_info.branch = data['branch']
    military_info.status = data['status']
    
    if data.get('enlistmentDate'):
        military_info.enlistment_date = parse_iso_datetime(data['enlistmentDate'])
    if data.get('currentRank'):
        military_info.current_rank = data['currentRank']
    if data.get('plannedEnlistmentDate'):
        military_info.planned_enlistment_date = parse_iso_datetime(data['plannedEnlistmentDate'])
    if data.get('manualPromotionDates'):
        military_info.manual_promotion_dates = {
            k: parse_iso_datetime(v) if isinstance(v, str) else v
            for k, v in data['manualPromotionDates'].items()
        }
    
    military_info.save()
    
    # 곰신/가족 모드: 연결 관계 업데이트
    if data['userType'] in ['girlfriend', 'family']:
        connected_ids = data.get('connectedMilitaryUserIds', [])
        update_military_connections(user, connected_ids, data['userType'])
    else:
        # 군인 모드: 연결 관계 삭제
        MilitaryConnection.objects.filter(user_id=user.id).delete()

def update_military_connections(user, connected_usernames, user_type):
    # 기존 연결 삭제
    MilitaryConnection.objects.filter(user_id=user.id).delete()
    
    # 곰신 모드: 1명만 허용
    if user_type == 'girlfriend' and len(connected_usernames) > 1:
        raise ValidationError("곰신 모드는 1명만 연결할 수 있습니다")
    
    # 가족 모드: 여러 명 가능
    if user_type == 'family' and len(connected_usernames) == 0:
        raise ValidationError("가족 모드는 최소 1명 이상 연결해야 합니다")
    
    # 연결 관계 생성
    for username in connected_usernames:
        try:
            connected_user = User.objects.get(username=username)
            # 연결된 사용자가 군인 모드인지 확인
            connected_military_info = MilitaryInfo.objects.filter(
                user_id=connected_user.id,
                user_type='military'
            ).first()
            if not connected_military_info:
                raise ValidationError(f"{username}은(는) 군인 모드가 아닙니다")
            
            MilitaryConnection.objects.create(
                user_id=user.id,
                connected_military_user_id=connected_user.id
            )
        except User.DoesNotExist:
            raise ValidationError(f"사용자를 찾을 수 없습니다: {username}")
```

---

### 2.3 새로운 엔드포인트 (선택사항)

#### GET /api/military/info

**현재 사용자의 군인 정보 조회**

```json
{
  "militaryInfo": {
    "userType": "military",
    "branch": "army",
    "status": "afterEnlistment",
    "enlistmentDate": "2024-01-15T00:00:00Z",
    "currentRank": "private",
    "connectedMilitaryUserIds": null,
    "manualPromotionDates": {}
  }
}
```

#### GET /api/military/connected

**곰신/가족 모드: 연결된 군인들의 정보 조회**

```json
{
  "connectedMilitaryUsers": [
    {
      "username": "military_user_123",
      "alias": "군인별명",
      "militaryInfo": {
        "branch": "army",
        "enlistmentDate": "2024-01-15T00:00:00Z",
        "currentRank": "private"
      }
    }
  ]
}
```

---

### 2.4 휴가 관리 API (서버에서 관리)

#### GET /api/military/vacations

**휴가 목록 조회**

```json
{
  "vacations": [
    {
      "id": "vacation_123",
      "startDate": "2024-03-01T00:00:00Z",
      "endDate": "2024-03-05T00:00:00Z",
      "type": "annual",
      "memo": "연가",
      "createdAt": "2024-02-15T00:00:00Z",
      "updatedAt": "2024-02-15T00:00:00Z"
    }
  ]
}
```

#### POST /api/military/vacations

**휴가 등록**

요청:
```json
{
  "startDate": "2024-03-01T00:00:00Z",
  "endDate": "2024-03-05T00:00:00Z",
  "type": "annual",
  "memo": "연가"
}
```

응답:
```json
{
  "vacation": {
    "id": "vacation_123",
    "startDate": "2024-03-01T00:00:00Z",
    "endDate": "2024-03-05T00:00:00Z",
    "type": "annual",
    "memo": "연가",
    "createdAt": "2024-02-15T00:00:00Z",
    "updatedAt": "2024-02-15T00:00:00Z"
  }
}
```

#### PUT /api/military/vacations/:id

**휴가 수정**

요청:
```json
{
  "startDate": "2024-03-02T00:00:00Z",
  "endDate": "2024-03-06T00:00:00Z",
  "type": "annual",
  "memo": "연가 (수정)"
}
```

응답:
```json
{
  "vacation": {
    "id": "vacation_123",
    "startDate": "2024-03-02T00:00:00Z",
    "endDate": "2024-03-06T00:00:00Z",
    "type": "annual",
    "memo": "연가 (수정)",
    "createdAt": "2024-02-15T00:00:00Z",
    "updatedAt": "2024-02-20T00:00:00Z"
  }
}
```

#### DELETE /api/military/vacations/:id

**휴가 삭제**

응답: 200 OK 또는 204 No Content

**구현 예시 (Python/Django):**

```python
from rest_framework.decorators import api_view
from rest_framework.response import Response
from .models import Vacation

@api_view(['GET'])
def get_vacations(request):
    vacations = Vacation.objects.filter(user_id=request.user.id).order_by('start_date')
    return Response({
        'vacations': [serialize_vacation(v) for v in vacations]
    })

@api_view(['POST'])
def create_vacation(request):
    data = request.data
    vacation = Vacation.objects.create(
        user_id=request.user.id,
        start_date=parse_iso_datetime(data['startDate']).date(),
        end_date=parse_iso_datetime(data['endDate']).date(),
        type=data.get('type'),
        memo=data.get('memo')
    )
    return Response({'vacation': serialize_vacation(vacation)}, status=201)

@api_view(['PUT'])
def update_vacation(request, vacation_id):
    try:
        vacation = Vacation.objects.get(id=vacation_id, user_id=request.user.id)
    except Vacation.DoesNotExist:
        return Response({'error': '휴가를 찾을 수 없습니다'}, status=404)
    
    data = request.data
    if 'startDate' in data:
        vacation.start_date = parse_iso_datetime(data['startDate']).date()
    if 'endDate' in data:
        vacation.end_date = parse_iso_datetime(data['endDate']).date()
    if 'type' in data:
        vacation.type = data['type']
    if 'memo' in data:
        vacation.memo = data['memo']
    
    vacation.save()
    return Response({'vacation': serialize_vacation(vacation)})

@api_view(['DELETE'])
def delete_vacation(request, vacation_id):
    try:
        vacation = Vacation.objects.get(id=vacation_id, user_id=request.user.id)
        vacation.delete()
        return Response(status=204)
    except Vacation.DoesNotExist:
        return Response({'error': '휴가를 찾을 수 없습니다'}, status=404)

def serialize_vacation(vacation):
    return {
        'id': str(vacation.id),
        'startDate': vacation.start_date.isoformat() + 'T00:00:00Z',
        'endDate': vacation.end_date.isoformat() + 'T00:00:00Z',
        'type': vacation.type,
        'memo': vacation.memo,
        'createdAt': vacation.created_at.isoformat(),
        'updatedAt': vacation.updated_at.isoformat()
}
```

---

## 3. 데이터 검증 로직

### 3.1 군인 모드 검증

```python
def validate_military_info(data):
    user_type = data.get('userType')
    status = data.get('status')
    
    if user_type == 'military':
        if status == 'beforeEnlistment':
            if not data.get('plannedEnlistmentDate'):
                raise ValidationError("입대 전인 경우 예정 입대일이 필요합니다")
        elif status == 'afterEnlistment':
            if not data.get('enlistmentDate'):
                raise ValidationError("입대 후인 경우 입대일이 필요합니다")
            if not data.get('currentRank'):
                raise ValidationError("입대 후인 경우 현재 계급이 필요합니다")
```

### 3.2 곰신/가족 모드 검증

```python
def validate_connection_info(data):
    user_type = data.get('userType')
    connected_ids = data.get('connectedMilitaryUserIds', [])
    
    if user_type == 'girlfriend':
        if len(connected_ids) != 1:
            raise ValidationError("곰신 모드는 정확히 1명만 연결해야 합니다")
    
    if user_type == 'family':
        if len(connected_ids) == 0:
            raise ValidationError("가족 모드는 최소 1명 이상 연결해야 합니다")
    
    # 연결된 사용자들이 실제로 존재하고 군인 모드인지 확인
    for username in connected_ids:
        try:
            connected_user = User.objects.get(username=username)
            military_info = MilitaryInfo.objects.filter(
                user_id=connected_user.id,
                user_type='military'
            ).first()
            if not military_info:
                raise ValidationError(f"{username}은(는) 군인 모드가 아닙니다")
        except User.DoesNotExist:
            raise ValidationError(f"사용자를 찾을 수 없습니다: {username}")
```

---

## 4. 마이그레이션 전략

### 4.1 기존 사용자 처리

```python
# 기존 사용자는 militaryInfo가 null이므로 문제없음
# 클라이언트에서 온보딩 시 입력받음
```

### 4.2 하위 호환성

```python
# 클라이언트에서 connectedMilitaryUserId (단수)도 지원하므로
# 서버에서도 단수 형태를 리스트로 변환하여 처리

def parse_connected_ids(data):
    if 'connectedMilitaryUserIds' in data:
        return data['connectedMilitaryUserIds']
    elif 'connectedMilitaryUserId' in data:
        return [data['connectedMilitaryUserId']]  # 단수를 리스트로 변환
    return None
```

---

## 5. 보안 고려사항

### 5.1 권한 검증

```python
# 곰신/가족 모드 사용자가 연결하려는 군인 사용자가
# 실제로 존재하고 공개 설정이 되어있는지 확인

def can_connect_to_military_user(request_user, target_username):
    try:
        target_user = User.objects.get(username=target_username)
        # 친구 관계 또는 공개 프로필인지 확인
        if not is_friend(request_user, target_user) and not target_user.is_public:
            return False
        return True
    except User.DoesNotExist:
        return False
```

### 5.2 데이터 무결성

```python
# 연결 관계 삭제 시 CASCADE 처리
# 군인 사용자가 탈퇴하면 연결된 곰신/가족 사용자의 연결도 삭제
```

---

## 6. 성능 최적화

### 6.1 인덱스

```sql
-- 이미 위에서 생성한 인덱스들
CREATE INDEX idx_military_infos_user_id ON military_infos(user_id);
CREATE INDEX idx_military_connections_user_id ON military_connections(user_id);
CREATE INDEX idx_military_connections_connected_id ON military_connections(connected_military_user_id);
CREATE INDEX idx_vacations_user_id ON vacations(user_id);
CREATE INDEX idx_vacations_dates ON vacations(user_id, start_date, end_date);
```

### 6.2 쿼리 최적화

```python
# 연결된 군인 정보를 한 번에 조회
def get_connected_military_users(user_id):
    return User.objects.filter(
        id__in=Subquery(
            MilitaryConnection.objects.filter(user_id=user_id)
            .values('connected_military_user_id')
        )
    ).select_related('military_info')
```

---

## 7. 테스트 케이스

### 7.1 군인 모드

```python
def test_military_mode():
    data = {
        "userType": "military",
        "branch": "army",
        "status": "afterEnlistment",
        "enlistmentDate": "2024-01-15T00:00:00Z",
        "currentRank": "private"
    }
    # 검증 통과
```

### 7.2 곰신 모드

```python
def test_girlfriend_mode():
    data = {
        "userType": "girlfriend",
        "branch": "army",
        "status": "afterEnlistment",
        "connectedMilitaryUserIds": ["military_user_123"]
    }
    # 1명만 연결 가능
```

### 7.3 가족 모드

```python
def test_family_mode():
    data = {
        "userType": "family",
        "branch": "army",
        "status": "afterEnlistment",
        "connectedMilitaryUserIds": ["military_user_123", "military_user_456"]
    }
    # 여러 명 연결 가능
```

---

## 8. 체크리스트

- [ ] 데이터베이스 스키마 변경 (military_infos, military_connections, vacations 테이블)
- [ ] GET /api/users/bundle 응답에 militaryInfo 추가
- [ ] PUT /api/profile/info 요청에 militaryInfo 처리 추가
- [ ] 휴가 관리 API 구현 (GET, POST, PUT, DELETE /api/military/vacations)
- [ ] 데이터 검증 로직 구현
- [ ] 곰신/가족 모드 연결 관계 관리
- [ ] 하위 호환성 처리 (connectedMilitaryUserId 단수 형태)
- [ ] 인덱스 추가
- [ ] 보안 검증 (권한, 데이터 무결성)
- [ ] 테스트 케이스 작성
- [ ] API 문서 업데이트

---

## 9. 참고사항

### 9.1 서버 중심 구조 원칙

- **입대일, 진급일, 휴가 정보는 모두 서버에서 관리**
- 클라이언트는 서버에서 받은 데이터를 그대로 사용
- 클라이언트에서 계산하거나 로컬에서 관리하지 않음
- 모든 변경사항은 서버에 전송하여 서버에서 관리

### 9.2 데이터 형식

- 모든 날짜는 ISO 8601 형식 (UTC)으로 전송/수신
- manualPromotionDates는 Map<String, DateTime> 형태
- connectedMilitaryUserIds는 List<String> 형태 (username 배열)
- vacations는 List<Vacation> 형태 (서버에서 관리)

### 9.3 제약사항

- 곰신 모드는 정확히 1명만, 가족 모드는 1명 이상 연결 가능
- 연결된 군인 사용자는 반드시 userType='military'여야 함
- 휴가는 사용자 본인만 등록/수정/삭제 가능 (권한 검증 필요)

### 9.4 휴가 관리

- 휴가는 별도 API로 관리 (GET /api/military/vacations 등)
- GET /api/users/bundle 응답에 포함할 수도 있고, 별도로 조회할 수도 있음
- 클라이언트는 두 가지 방식 모두 지원

### 9.5 서버 자동 상태 관리

**서버에서 자동으로 처리하는 상태 관리:**
- ✅ 입대 예정 → 입대 전환 (planned_enlistment_date가 오늘이 되는 날 자정)
- ✅ 자동 진급 처리 (매월 1일 진급 규칙, 배치 작업으로 처리)
- ✅ 수동 진급일 조정 반영
- ✅ 전역일 계산 및 확인
- ✅ 휴가 정보 관리 (사용자 등록/수정/삭제)

**상세한 구현 가이드는 `SERVER_AUTO_STATE_MANAGEMENT.md` 참조**

**클라이언트는:**
- 서버에서 받은 최신 상태를 그대로 사용
- 계산하지 않음
- 상태 변경 요청만 전송

