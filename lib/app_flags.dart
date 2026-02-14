/// 앱 전역 플래그. main()에서 값을 설정해 사용.

/// 그래프 검색: true = 서버 mock 데이터, false = 실제 시맨틱 검색
bool kGraphSearchMock = true;

/// Mock 모드일 때 그래프 로드 시 가져올 노드 수 (GET /api/graph?mode=mock&count=...)
int kGraphMockNodeCount = 200;

/// 검색 시 결과로 받을 최대 노드 개수 (GET /api/graph/search?limit=...)
int kGraphSearchResultLimit = 30;
