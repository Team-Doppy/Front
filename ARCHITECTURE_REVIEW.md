# PostwriteScreen 탭 감지 구조 개선 방안

## 현재 구조 분석

### 현재 방식
1. **전체 화면 GestureDetector** (`postwrite_screen.dart` 1191-1218줄)
   - `Positioned.fill`로 전체 화면을 덮는 `GestureDetector`
   - `onTapDown`: 탭 위치 저장 (`_lastTapPosition`)
   - `onTap`: `_handleTap` 호출
   - `onLongPressStart`: `_handleLongPressStart` 호출

2. **간접적 노드 찾기** (`_handleTapAfterLayout`)
   - `editorService.findNodeByHitTest()`로 탭 위치에 있는 노드 찾기
   - 복잡한 경계 판단 로직 (텍스트 노드 근처 20px 여유 등)
   - 여러 특수 케이스 처리 (세로 노드 사이, 이미지행 경계, 마지막 노드 아래 등)

### 현재 구조의 문제점
1. **정확도 문제**: Hit test 기반 간접 감지로 인한 부정확성
2. **복잡한 로직**: 경계 판단, 텍스트 노드 근처 감지 등 복잡한 조건문
3. **성능**: 매번 모든 노드의 rect를 계산하여 비교
4. **유지보수성**: 로직이 한 곳에 집중되어 복잡함

### 각 컴포넌트별 현재 상태
- ✅ **LinkComponent**: 이미 `GestureDetector` 사용 중 (386-400줄)
  - `onTap`: 노드 선택
  - `onLongPressStart`: 편집 모드가 아닐 때만 프리뷰
  - 편집 모드에서는 롱프레스 비활성화

- ✅ **ClipComponent**: `GestureDetector` 사용 중 (1540, 1587줄)
  - 음소거 토글용으로만 사용

- ❌ **SingleImageComponent**: `GestureDetector` 없음
  - 전체 화면 GestureDetector에 의존

- ❌ **ImageRowComponent**: `GestureDetector` 없음
  - 전체 화면 GestureDetector에 의존

## 개선 방안

### 제안: 각 컴포넌트에서 직접 GestureDetector 사용

#### 장점
1. **정확도 향상**: 각 컴포넌트가 자신의 영역을 정확히 알고 있음
2. **코드 명확성**: 각 컴포넌트가 자신의 제스처를 처리
3. **유지보수성**: 로직이 각 컴포넌트에 분산되어 이해하기 쉬움
4. **성능**: 불필요한 hit test 제거

#### 구현 방법

##### 1. SingleImageComponent
```dart
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: widget.isEditing ? () {
    context.read<NodeComponentService>().selectImage(widget.nodeId);
  } : null,
  onLongPressStart: widget.isEditing ? (details) {
    widget.dragService?.startDrag(
      widget.nodeId,
      context,
      details.globalPosition,
    );
  } : null,
  onLongPressMoveUpdate: widget.isEditing ? (details) {
    widget.dragService?.updateDrag(details.globalPosition, context);
    // Auto-scroll 로직은 DragService로 위임
  } : null,
  onLongPressEnd: widget.isEditing ? (_) {
    widget.dragService?.endDrag();
  } : null,
  child: // 기존 이미지 위젯
)
```

##### 2. ImageRowComponent
```dart
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: widget.isEditing ? () {
    context.read<NodeComponentService>().selectImage(widget.nodeId);
  } : null,
  onLongPressStart: widget.isEditing ? (details) {
    // 이미지행 내부 이미지 인덱스 찾기
    final imageIndex = _findClickedImageIndex(
      widget.nodeId,
      details.globalPosition,
    );
    widget.dragService?.startDrag(
      widget.nodeId,
      context,
      details.globalPosition,
    );
    if (imageIndex != null) {
      widget.dragService?.setSplitImageInfo(widget.nodeId, imageIndex);
    }
  } : null,
  onLongPressMoveUpdate: widget.isEditing ? (details) {
    widget.dragService?.updateDrag(details.globalPosition, context);
  } : null,
  onLongPressEnd: widget.isEditing ? (_) {
    widget.dragService?.endDrag();
  } : null,
  child: // 기존 Row 위젯
)
```

##### 3. ClipComponent
- 이미 GestureDetector가 있지만, 편집 모드에서 탭/롱프레스 처리 추가 필요

##### 4. LinkComponent
- 이미 GestureDetector가 있지만, 롱프레스 드래그 추가 필요

#### 전체 화면 GestureDetector의 역할 변경

**유지해야 할 기능:**
1. **텍스트 노드 영역**: SuperEditor가 직접 처리
2. **빈 공간 클릭**: 노드 선택 해제
3. **세로 노드 사이 클릭**: 빈 문단 삽입
4. **마지막 노드 아래 클릭**: 새 빈 문단 추가

**제거할 기능:**
1. 특수 노드(Image, ImageRow, Link, Clip)의 탭/롱프레스 처리
   - 각 컴포넌트로 이동

#### 롱프레스 드래그 처리

**각 컴포넌트에서 처리:**
- `onLongPressStart`: `dragService.startDrag()` 호출
- `onLongPressMoveUpdate`: `dragService.updateDrag()` 호출
- `onLongPressEnd`: `dragService.endDrag()` 호출

**Auto-scroll:**
- `DragService.updateDrag()` 내부에서 처리
- 또는 `postwrite_screen.dart`의 `_handleDragMoveAndAutoScroll` 로직을 `DragService`로 이동

#### 충돌 방지

**텍스트 노드와의 충돌:**
- 각 컴포넌트의 `GestureDetector`는 `HitTestBehavior.opaque` 사용
- 텍스트 노드 영역은 SuperEditor가 우선 처리
- 컴포넌트의 `GestureDetector`는 자신의 영역에서만 동작

**전체 화면 GestureDetector:**
- `HitTestBehavior.translucent` 유지
- 컴포넌트가 처리하지 않은 영역만 처리

## 마이그레이션 계획

### 1단계: SingleImageComponent에 GestureDetector 추가
- 탭: 노드 선택
- 롱프레스: 드래그 시작

### 2단계: ImageRowComponent에 GestureDetector 추가
- 탭: 노드 선택
- 롱프레스: 드래그 시작 (이미지 분리 정보 포함)

### 3단계: ClipComponent에 편집 모드 제스처 추가
- 탭: 노드 선택
- 롱프레스: 드래그 시작

### 4단계: LinkComponent에 롱프레스 드래그 추가
- 편집 모드에서 롱프레스 시 드래그 시작

### 5단계: 전체 화면 GestureDetector 정리
- 특수 노드 처리 로직 제거
- 빈 공간/텍스트 노드 처리만 유지

## 결론

**각 컴포넌트에서 직접 GestureDetector를 사용하는 것이 더 나은 구조입니다.**

**이유:**
1. 더 정확한 탭 감지
2. 코드가 더 명확하고 유지보수하기 쉬움
3. 각 컴포넌트가 자신의 책임을 가짐
4. 롱프레스 드래그도 자연스럽게 처리 가능

**롱프레스 드래그는 문제없습니다:**
- 각 컴포넌트의 `onLongPressStart`에서 `dragService.startDrag()` 호출
- `onLongPressMoveUpdate`에서 `dragService.updateDrag()` 호출
- 기존 드래그 로직과 동일하게 동작

