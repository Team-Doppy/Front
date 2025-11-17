# 그룹/친구 데이터 로드 시점 최적화 전략

## 📊 현재 상황 분석

### 1. 공개범위 변경 시 (`access_level_sheet.dart`)
- ✅ **좋음**: 그룹 데이터가 없을 때만 로드
- ✅ **좋음**: 캐시가 있으면 재조회하지 않음
- ⚠️ **개선 필요**: 공개범위 변경 후 그룹 데이터 동기화 없음 (postCount 업데이트 필요할 수 있음)

### 2. 친구 수락/취소 시 (`friend_provider.dart`)
- ⚠️ **문제**: 낙관적 업데이트만 하고 그룹 데이터 동기화 없음
- ⚠️ **영향**: allFriends 그룹의 `memberCount`가 실제와 불일치할 수 있음
- ❌ **현재**: 전체 그룹 목록 재조회 없음 → memberCount 미반영

### 3. 포스트 삭제/생성 시
- ❌ **비효율**: 전체 그룹 목록을 재조회함 (`fetchMyGroups`)
- ⚠️ **문제**: 관련 그룹의 `postCount`만 업데이트하면 되는데 전체 재조회
- 📍 **위치**: `post_reader_screen.dart`, `grid_category_section.dart`, `post_export_screen.dart`

### 4. 그룹 멤버 추가/제거 시 (`group_provider.dart`)
- ❌ **비효율**: 전체 그룹 목록을 재조회함 (`_invalidateAndRefreshGroups`)
- ⚠️ **문제**: 해당 그룹의 `memberCount`만 업데이트하면 되는데 전체 재조회

### 5. 그룹 생성/수정/삭제 시
- ✅ **필요**: 전체 그룹 목록 재조회 필요 (정상)

## 🎯 최적화 전략

### 전략 1: 선택적 그룹 스키마 업데이트
전체 재조회 대신 특정 그룹의 특정 필드만 업데이트

**적용 케이스:**
- 그룹 멤버 추가/제거 → `memberCount`만 업데이트
- 포스트 삭제/생성 → 관련 그룹의 `postCount`만 업데이트
- 친구 수락/취소 → allFriends 그룹의 `memberCount`만 업데이트

### 전략 2: 낙관적 업데이트 + 선택적 동기화
로컬 업데이트 후 필요할 때만 서버 동기화

**적용 케이스:**
- 친구 수락/취소 → 로컬 memberCount 업데이트, 캐시 무효화하지 않음
- 그룹 멤버 변경 → 로컬 memberCount 업데이트, 전체 재조회 생략

### 전략 3: 배치 업데이트 및 중복 방지
여러 작업이 연속으로 발생할 때 마지막 요청만 실행

### 전략 4: 스마트 캐시 전략
- 캐시 유효 시간 기반 (현재 1분 - FriendProvider)
- 데이터 변경 시에만 캐시 무효화
- 불필요한 전체 재조회 최소화

## 📝 구현 계획

### Phase 1: 그룹 Provider 개선
1. `updateGroupMemberCount(int groupId, int delta)` 메서드 추가
   - 멤버 추가/제거 시 memberCount만 업데이트
   - 전체 재조회 생략

2. `updateGroupPostCount(int groupId, int delta)` 메서드 추가
   - 포스트 생성/삭제 시 postCount만 업데이트
   - 관련 그룹만 선택적 업데이트

3. `updateAllFriendsMemberCount(int delta)` 메서드 추가
   - 친구 수락/취소 시 allFriends 그룹의 memberCount만 업데이트

### Phase 2: 친구 Provider 개선
1. 친구 수락/취소 시 GroupProvider와 연동
   - `acceptFriendRequest` → allFriends memberCount +1
   - `deleteFriend` → allFriends memberCount -1

### Phase 3: 포스트 관련 최적화
1. 포스트 삭제/생성 시 관련 그룹만 업데이트
   - 포스트의 `sharedGroupIds` 확인
   - 해당 그룹들의 `postCount`만 업데이트
   - 전체 재조회 생략

### Phase 4: 공개범위 변경 최적화
1. 공개범위 변경 시 그룹 데이터 동기화 조건부 실행
   - GROUPS로 변경된 경우에만 관련 그룹 postCount 업데이트
   - PUBLIC/PRIVATE/FRIENDS 변경 시 그룹 데이터 업데이트 불필요

## 🔄 엣지 케이스 처리

### 케이스 1: 친구 수락 후 바로 공개범위 변경
- 친구 수락 → allFriends memberCount 로컬 업데이트
- 공개범위 변경 시 이미 캐시된 그룹 데이터 사용
- 서버 동기화는 필요 시에만 수행

### 케이스 2: 그룹 멤버 제거 후 포스트 삭제
- 멤버 제거 → memberCount 로컬 업데이트
- 포스트 삭제 → postCount 로컬 업데이트
- 두 작업 연속 시 배치 처리로 서버 요청 최소화

### 케이스 3: 포스트 생성 후 공개범위 변경
- 포스트 생성 → 관련 그룹 postCount 로컬 업데이트
- 공개범위 변경 → 관련 그룹 postCount 다시 업데이트
- 중복 업데이트 방지 로직 필요

### 케이스 4: 그룹 삭제 후 공개범위 변경
- 그룹 삭제 → 전체 그룹 목록 재조회 (필수)
- 공개범위 변경 시 이미 최신 그룹 데이터 사용

## 📈 예상 효과

### 서버 요청 감소
- 기존: 그룹 멤버 변경 시마다 전체 그룹 목록 재조회
- 개선: 로컬 업데이트만 수행, 전체 재조회 생략
- **예상 감소율: 약 70-80%**

### UI 반응성 향상
- 기존: 서버 응답 대기 후 UI 업데이트
- 개선: 낙관적 업데이트로 즉시 UI 반영
- **예상 개선: 즉시 피드백**

### 데이터 일관성 유지
- 로컬 업데이트와 서버 동기화 균형
- 캐시 무효화 시점 최적화
- **예상 효과: UI와 서버 데이터 일치율 향상**

## ✅ 구현 완료 사항

### 1. GroupProvider 최적화
- ✅ `updateGroupMemberCount`: 특정 그룹의 memberCount만 로컬 업데이트
- ✅ `updateGroupPostCount`: 특정 그룹의 postCount만 로컬 업데이트
- ✅ `updateMultipleGroupsPostCount`: 여러 그룹의 postCount 일괄 업데이트
- ✅ `updateAllFriendsMemberCount`: allFriends 그룹의 memberCount만 업데이트

### 2. 그룹 멤버 관리 최적화
- ✅ `addMember`: 전체 재조회 생략, memberCount만 로컬 업데이트
- ✅ `removeMember`: 전체 재조회 생략, memberCount만 로컬 업데이트
- ✅ `removeMembersBatch`: 전체 재조회 생략, memberCount만 로컬 업데이트

### 3. 친구 관리 최적화
- ✅ `acceptFriendRequest`: allFriends 그룹 memberCount +1 로컬 업데이트
- ✅ `acceptFriendRequestOptimistic`: allFriends 그룹 memberCount +1 로컬 업데이트
- ✅ `deleteFriend`: allFriends 그룹 memberCount -1 로컬 업데이트
- ✅ `deleteFriendsBatch`: allFriends 그룹 memberCount 배치 업데이트

### 4. 포스트 관리 최적화
- ✅ 포스트 삭제 시: GROUPS 공개범위인 경우에만 관련 그룹의 postCount -1 업데이트
- ✅ 포스트 생성 시: GROUPS 공개범위인 경우에만 관련 그룹의 postCount +1 업데이트

### 5. 공개범위 변경 최적화
- ✅ GROUPS → PUBLIC/FRIENDS/PRIVATE 변경 시: 관련 그룹의 postCount -1 업데이트
- ✅ 그룹 선택/해제 시: 추가/제거된 그룹의 postCount +1/-1 업데이트
- ✅ 전체 공개/친구 공개/나만보기 변경 시: GROUPS였던 경우에만 관련 그룹 postCount 업데이트

## 📋 최적화된 로드 시점 정리

### 그룹 데이터 로드
1. **최초 로드**: 공개범위 시트가 열릴 때 캐시가 없을 때만 로드
2. **멤버 추가/제거**: 서버 재조회 없이 로컬 memberCount만 업데이트
3. **포스트 생성/삭제**: GROUPS 공개범위인 경우에만 관련 그룹 postCount 업데이트
4. **공개범위 변경**: GROUPS 관련 변경 시에만 관련 그룹 postCount 업데이트
5. **친구 수락/취소**: allFriends 그룹 memberCount만 로컬 업데이트
6. **그룹 생성/수정/삭제**: 전체 재조회 필요 (필수)

### 친구 데이터 로드
1. **1분 캐시 기반**: 타이밍 기반 캐시 사용 (현재 유지)
2. **친구 수락/취소**: 낙관적 업데이트 + allFriends 그룹 memberCount 동기화

### 전체 재조회가 필요한 경우
- 그룹 생성/수정/삭제
- 그룹 순서 변경
- 그룹 이미지/설명 변경
- 초기 로드 시 캐시가 없을 때

## 🔍 엣지 케이스 처리 확인

### 케이스 1: 친구 수락 후 바로 공개범위 변경 ✅
- 친구 수락 → allFriends memberCount 로컬 업데이트
- 공개범위 변경 시 이미 캐시된 그룹 데이터 사용
- ✅ 처리됨: 로컬 업데이트만 수행

### 케이스 2: 그룹 멤버 제거 후 포스트 삭제 ✅
- 멤버 제거 → memberCount 로컬 업데이트
- 포스트 삭제 → postCount 로컬 업데이트
- ✅ 처리됨: 각각 로컬 업데이트만 수행

### 케이스 3: 포스트 생성 후 공개범위 변경 ✅
- 포스트 생성 → 관련 그룹 postCount +1 로컬 업데이트
- 공개범위 변경 → 변경 전 그룹 postCount -1, 변경 후 그룹 postCount +1
- ✅ 처리됨: 변경 전후 그룹 ID 비교하여 delta 계산

### 케이스 4: 그룹 삭제 후 공개범위 변경 ✅
- 그룹 삭제 → 전체 그룹 목록 재조회 (필수)
- 공개범위 변경 시 이미 최신 그룹 데이터 사용
- ✅ 처리됨: 전체 재조회 후 로컬 업데이트

### 케이스 5: 여러 그룹에 공유된 포스트 삭제 ✅
- 포스트 삭제 시 여러 그룹 ID 확인
- 각 그룹의 postCount -1 일괄 업데이트
- ✅ 처리됨: `updateMultipleGroupsPostCount` 사용

