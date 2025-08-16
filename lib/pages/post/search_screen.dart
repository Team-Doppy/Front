// lib/pages/post/search_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:doppy/data/services/api_service_base.dart';
import 'package:flutter/material.dart';

import '../../theme/app_text_styles.dart';
import '../components/custom_bottom_navigation_bar.dart';
import '../../data/services/auth_service.dart';

/// ===============================================================
/// Search Screen (계정/게시글)
/// - 사용자 검색 GET /api/friends/search?username=
/// - 사용자 조회 GET /api/auth/users/{username} → 프로필 이동
/// - 친구 신청/수락/거절/차단/삭제 등 Friend API 액션
/// - 요청/응답/에러 로깅 + JWT 형식 검증
/// - 커스텀 탭 인디케이터(화면 너비의 37.5%)
/// ===============================================================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// -------------------- 데이터 모델 --------------------
class AccountItem {
  final String nickname; // 서버는 username만 주므로 UI 편의상 nickname = username
  final String userId; // 화면 표기 '@username'
  final int neighbors; // 서버 응답에 없으므로 0으로 채움
  const AccountItem({
    required this.nickname,
    required this.userId,
    required this.neighbors,
  });
}

class PostItemData {
  final String title;
  final String author;
  final String preview;
  final String imageUrl;
  final int likes;
  const PostItemData({
    required this.title,
    required this.author,
    required this.preview,
    required this.imageUrl,
    required this.likes,
  });
}

/// -------------------- API DTO/결과 --------------------
class UserDto {
  final int id;
  final String username;
  final String role;
  const UserDto({required this.id, required this.username, required this.role});
}

class FriendSearchResult {
  final int? status;
  final List<String> usernames;
  final dynamic body;
  final Map<String, List<String>> headers;
  final Uri uri;
  final Duration elapsed;
  final String? serverMessage;
  bool get ok => status != null && status! >= 200 && status! < 300;
  const FriendSearchResult({
    required this.status,
    required this.usernames,
    required this.body,
    required this.headers,
    required this.uri,
    required this.elapsed,
    required this.serverMessage,
  });
}

/// -------------------- API 클라이언트 --------------------
class FriendSearchApi {
  final Dio _dio;
  FriendSearchApi()
      : _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (code) => true, // 4xx/5xx도 잡아서 로깅
      receiveDataWhenStatusError: true,
    ),
  );

  // ---- 공통 로깅 유틸
  static String _maskToken(String token) {
    if (token.isEmpty) return '(empty)';
    final n = token.length;
    final tail = token.substring(n - (n >= 6 ? 6 : n));
    return '***$tail';
  }

  static String _prettyJson(dynamic data) {
    try {
      if (data is String) {
        final obj = json.decode(data);
        return const JsonEncoder.withIndent('  ').convert(obj);
      }
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data?.toString() ?? '';
    }
  }

  static String _trimLong(String s, {int max = 3000}) {
    if (s.length <= max) return s;
    return s.substring(0, max) + '…(truncated)';
  }

  // ---- 사용자 검색
  Future<FriendSearchResult> searchUsers({
    required String baseUrl,
    required String token,
    required String query,
    CancelToken? cancelToken,
  }) async {
    final uri = '$baseUrl/api/friends/search';
    final sw = Stopwatch()..start();

    debugPrint('┌─[REQ] GET $uri?username=$query');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    final res = await _dio.get(
      uri,
      queryParameters: {'username': query},
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.json,
      ),
    );
    sw.stop();

    final status = res.statusCode;
    final body = res.data;
    final uriFinal = res.requestOptions.uri;
    final headers = res.headers.map.map((k, v) => MapEntry(k, v));

    debugPrint('┌─[RES] ${res.requestOptions.method} $uriFinal');
    debugPrint('│ status: $status');
    debugPrint('│ headers: ${_trimLong(headers.toString())}');
    debugPrint('│ body: ${_trimLong(_prettyJson(body))}');
    debugPrint('│ elapsed: ${sw.elapsedMilliseconds}ms');
    debugPrint('└────────────────────────────────');

    String? pickMessage(dynamic b) {
      try {
        if (b is Map<String, dynamic>) {
          return (b['message'] ?? b['error'] ?? b['detail'] ?? b['msg'])
              ?.toString();
        }
        if (b is String) return b;
      } catch (_) {}
      return null;
    }

    final usernames = <String>[];
    if (status == 200) {
      if (body is List) {
        for (final e in body) {
          if (e is Map<String, dynamic>) {
            final u = e['username']?.toString();
            if (u != null && u.isNotEmpty) usernames.add(u);
          }
        }
      } else {
        debugPrint('[-] WARN: 200인데 body가 List가 아님: ${body.runtimeType}');
      }
    }

    return FriendSearchResult(
      status: status,
      usernames: usernames,
      body: body,
      headers: headers,
      uri: uriFinal,
      elapsed: sw.elapsed,
      serverMessage: pickMessage(body),
    );
  }

  // ---- 사용자 정보 조회
  Future<UserDto?> getUserByUsername({
    required String baseUrl,
    required String token,
    required String username,
    CancelToken? cancelToken,
  }) async {
    final uri = '$baseUrl/api/auth/users/$username';
    final sw = Stopwatch()..start();

    debugPrint('┌─[REQ] GET $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');

    final res = await _dio.get(
      uri,
      cancelToken: cancelToken,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.json,
      ),
    );
    sw.stop();

    final status = res.statusCode;
    final body = res.data;
    final uriFinal = res.requestOptions.uri;

    debugPrint('┌─[RES] ${res.requestOptions.method} $uriFinal');
    debugPrint('│ status: $status');
    debugPrint('│ body: ${_trimLong(_prettyJson(body))}');
    debugPrint('│ elapsed: ${sw.elapsedMilliseconds}ms');
    debugPrint('└────────────────────────────────');

    if (status == 200 && body is Map<String, dynamic>) {
      try {
        return UserDto(
          id: (body['id'] as num).toInt(),
          username: body['username']?.toString() ?? '',
          role: body['role']?.toString() ?? '',
        );
      } catch (e) {
        debugPrint('[-] parse error: $e');
        return null;
      }
    }

    debugPrint('[-] getUserByUsername failed | code=$status');
    return null;
  }

  // ---- 친구 신청
  Future<Response> requestFriend({
    required String baseUrl,
    required String token,
    required String targetUsername,
  }) {
    final uri = '$baseUrl/api/friends/request';
    debugPrint('┌─[REQ] POST $uri | body={"targetUsername":"$targetUsername"}');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');
    return _dio.post(
      uri,
      data: {'targetUsername': targetUsername},
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  // ---- 친구 수락
  Future<Response> acceptFriend({
    required String baseUrl,
    required String token,
    required String requesterUsername,
  }) {
    final uri = '$baseUrl/api/friends/accept/$requesterUsername';
    debugPrint('┌─[REQ] POST $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');
    return _dio.post(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // ---- 친구 거절
  Future<Response> rejectFriend({
    required String baseUrl,
    required String token,
    required String requesterUsername,
  }) {
    final uri = '$baseUrl/api/friends/reject/$requesterUsername';
    debugPrint('┌─[REQ] POST $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');
    return _dio.post(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // ---- 친구 차단
  Future<Response> blockUser({
    required String baseUrl,
    required String token,
    required String targetUsername,
  }) {
    final uri = '$baseUrl/api/friends/block/$targetUsername';
    debugPrint('┌─[REQ] POST $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');
    return _dio.post(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  // ---- 친구 삭제
  Future<Response> deleteFriend({
    required String baseUrl,
    required String token,
    required String targetUsername,
  }) {
    final uri = '$baseUrl/api/friends/delete/$targetUsername';
    debugPrint('┌─[REQ] DELETE $uri');
    debugPrint('│ Authorization: Bearer ${_maskToken(token)}');
    debugPrint('└────────────────────────────────');
    return _dio.delete(
      uri,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}

/// -------------------- 메인 화면 --------------------
class _SearchScreenState extends State<SearchScreen> {
  // 하단 네비/정렬
  int _bottomIndex = 1;
  String _accountSort = '계정 이름';
  String _postSort = '인기순';

  // 선택 표시
  int? _selectedAccountIndex;
  int? _selectedPostIndex;

  // 검색 상태
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  // 서비스/백엔드
  final AuthService _authService = AuthService();
  final FriendSearchApi _friendApi = FriendSearchApi();
  final String _baseUrl = ApiServiceBase.baseUrl;

  // 네트워크 요청 상태(계정)
  bool _accountsLoading = false;
  String? _accountsError;
  CancelToken? _accountsCancelToken;

  // 로컬 더미 게시글
  late final List<PostItemData> _allPosts = [
    const PostItemData(
      title: '도피(doppy)로 기록하는 나의 일상',
      author: '푸른하늘',
      preview: '고정된 템플릿 없이 자유롭게 기록한 한 주의 일기.',
      imageUrl: 'https://picsum.photos/144/108?random=1',
      likes: 120,
    ),
    const PostItemData(
      title: '여행 준비 체크리스트 30가지',
      author: '여행러 민준',
      preview: '항공권, 숙소, eSIM, 환전, 보험까지 한 번에.',
      imageUrl: 'https://picsum.photos/144/108?random=2',
      likes: 320,
    ),
    const PostItemData(
      title: '사진 구도 10분 핵심',
      author: '사진찍는 수진',
      preview: '삼분할, 리드라인, 대칭. 초보도 바로 적용 가능.',
      imageUrl: 'https://picsum.photos/144/108?random=3',
      likes: 270,
    ),
    const PostItemData(
      title: 'Flutter로 감정 기록 앱 만들기',
      author: '코딩하는도치',
      preview: '탭, 달력 UI, 로컬 이미지 관리 팁 정리.',
      imageUrl: 'https://picsum.photos/144/108?random=4',
      likes: 410,
    ),
    const PostItemData(
      title: '제주살이 한 달 후기',
      author: '제주살이 현우',
      preview: '장단점, 예상비용, 지역별 추천.',
      imageUrl: 'https://picsum.photos/144/108?random=5',
      likes: 190,
    ),
    const PostItemData(
      title: '강아지 분리불안 훈련 루틴',
      author: '강아지훈련사',
      preview: '짧은 외출부터 점진적 거리두기, 보상 타이밍.',
      imageUrl: 'https://picsum.photos/144/108?random=6',
      likes: 450,
    ),
    const PostItemData(
      title: '최애 고양이 사료 비교',
      author: '고양이집사',
      preview: '원료, 기호성, 알레르기 유발성분 체크.',
      imageUrl: 'https://picsum.photos/144/108?random=7',
      likes: 210,
    ),
    const PostItemData(
      title: '도피(doppy) 시작 가이드',
      author: '도피 doppy',
      preview: '하고 싶은 말을, 하고 싶은 방식으로.',
      imageUrl: 'https://picsum.photos/144/108?random=8',
      likes: 999,
    ),
    for (int i = 1; i <= 8; i++)
      PostItemData(
        title: '테스트 포스트 $i',
        author: '이웃 $i',
        preview: '샘플 프리뷰 텍스트 $i 입니다.',
        imageUrl: 'https://picsum.photos/144/108?random=${15 + i}',
        likes: 50 + i * 7,
      ),
  ];

  // 표시 목록
  List<AccountItem> _accounts = [];
  List<PostItemData> _posts = [];

  @override
  void initState() {
    super.initState();
    _applySortAndResetInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _accountsCancelToken?.cancel('dispose');
    _searchController.dispose();
    super.dispose();
  }

  // -------------------- 검색/정렬 --------------------
  void _onSearchChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _performSearch);
  }

  void _onSearchSubmitted(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _performSearch();
  }

  Future<void> _performSearch() async {
    final q = _query.trim();
    debugPrint('[Search] perform | query="$q"');

    if (q.isEmpty) {
      setState(() {
        _accounts = [];
        _posts = _sortPosts(List.of(_allPosts));
        _selectedAccountIndex = null;
        _selectedPostIndex = null;
      });
      debugPrint('[Search] empty -> accounts cleared, posts=${_posts.length}');
      return;
    }

    await _searchAccountsRemote(q);
    _filterPostsLocal(q);
    setState(() {
      _selectedAccountIndex = null;
      _selectedPostIndex = null;
    });
  }

  Future<void> _searchAccountsRemote(String q) async {
    _accountsCancelToken?.cancel('new query: $q');
    _accountsCancelToken = CancelToken();

    final token = await _getAuthToken();

    setState(() {
      _accountsLoading = true;
      _accountsError = null;
    });

    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');

    if (token == null || token.isEmpty) {
      debugPrint('❌ JWT 없음: 요청 중단');
      setState(() {
        _accountsLoading = false;
        _accountsError = '로그인이 필요합니다(토큰 없음).';
        _accounts = [];
      });
      _showSnack('로그인이 필요합니다(토큰 없음).');
      return;
    }
    if (!jwtLike.hasMatch(token)) {
      debugPrint('❌ JWT 형식 불일치: "$token"');
      setState(() {
        _accountsLoading = false;
        _accountsError = '로그인 상태가 유효하지 않습니다(토큰 형식 오류).';
        _accounts = [];
      });
      _showSnack('로그인 상태가 유효하지 않습니다(토큰 형식 오류).');
      return;
    }

    final tail = token.substring(token.length - 6);
    debugPrint('🔑 Using JWT ***$tail');

    try {
      final res = await _friendApi.searchUsers(
        baseUrl: _baseUrl,
        token: token,
        query: q,
        cancelToken: _accountsCancelToken,
      );

      if (res.ok) {
        final items =
        res.usernames
            .map(
              (u) => AccountItem(nickname: u, userId: '@$u', neighbors: 0),
        )
            .toList();
        setState(() {
          _accountsLoading = false;
          _accountsError = null;
          _accounts = _sortAccounts(items);
        });
        debugPrint('[OK] accounts=${items.length}');
      } else {
        final code = res.status ?? -1;
        final serverMsg = res.serverMessage;
        final uiMsg =
            '계정 검색 실패 ($code)${serverMsg != null ? ' - $serverMsg' : ''}';

        debugPrint('[-] FAIL search users | code=$code');
        debugPrint(
          '[-] uri=${res.uri} | elapsed=${res.elapsed.inMilliseconds}ms',
        );

        setState(() {
          _accountsLoading = false;
          _accountsError = uiMsg;
          _accounts = [];
        });
        _showSnack(uiMsg);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        debugPrint('[CANCEL] ${e.message}');
        return;
      }
      final code = e.response?.statusCode;
      final body = e.response?.data;
      debugPrint('┌─[DIO ERROR]');
      debugPrint('│ type=${e.type} code=$code');
      debugPrint(
        '│ body=${FriendSearchApi._trimLong(FriendSearchApi._prettyJson(body))}',
      );
      debugPrint('└─────────────────');

      setState(() {
        _accountsLoading = false;
        _accountsError = '계정 검색 실패${code != null ? ' ($code)' : ''}';
        _accounts = [];
      });
      _showSnack(_accountsError!);
    } catch (e) {
      debugPrint('[UNEXPECTED] $e');
      setState(() {
        _accountsLoading = false;
        _accountsError = '계정 검색 중 알 수 없는 오류';
        _accounts = [];
      });
      _showSnack('계정 검색 중 알 수 없는 오류');
    }
  }

  void _filterPostsLocal(String q) {
    final lower = q.toLowerCase();
    List<PostItemData> pst =
    _allPosts
        .where(
          (p) =>
      p.title.toLowerCase().contains(lower) ||
          p.author.toLowerCase().contains(lower),
    )
        .toList();
    pst = _sortPosts(pst);
    setState(() => _posts = pst);
    debugPrint('[Search] posts filtered | count=${pst.length}');
  }

  void _applySortAndResetInitial() {
    setState(() {
      _accounts = [];
      _posts = _sortPosts(List.of(_allPosts));
      _selectedAccountIndex = null;
      _selectedPostIndex = null;
    });
  }

  List<AccountItem> _sortAccounts(List<AccountItem> list) {
    if (_accountSort == '계정 이름') {
      list.sort((a, b) => a.nickname.compareTo(b.nickname));
    }
    return list;
  }

  List<PostItemData> _sortPosts(List<PostItemData> list) {
    if (_postSort == '인기순') {
      list.sort((b, a) => a.likes.compareTo(b.likes)); // desc
    }
    return list;
  }

  Future<String?> _getAuthToken() async {
    try {
      final t = await _authService.getToken();
      final trimmed = t?.trim();
      debugPrint('[AuthService] token(raw)="${trimmed ?? 'null'}"');
      return trimmed;
    } catch (e) {
      debugPrint('[AuthService] getToken failed: $e');
      return null;
    }
  }

  void _clearSearch() {
    debugPrint('[Search] clear');
    _searchController.clear();
    setState(() => _query = '');
    _performSearch();
  }

  // -------------------- 선택/네비게이션 & Friend 액션 --------------------
  Future<void> _onTapAccount(int index, AccountItem item) async {
    setState(() => _selectedAccountIndex = index);

    // 액션 시트: 프로필 방문 / 친구 신청 / 차단
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final username =
        item.userId.startsWith('@')
            ? item.userId.substring(1)
            : item.userId;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text('프로필 방문 (@$username)'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _goToProfile(username);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: const Text('친구 신청 보내기'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _friendAction(
                      actionName: '친구 신청',
                      run:
                          (baseUrl, token) => _friendApi.requestFriend(
                        baseUrl: baseUrl,
                        token: token,
                        targetUsername: username,
                      ),
                      successMsg: '친구 신청이 완료되었습니다.',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('사용자 차단'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _friendAction(
                      actionName: '차단',
                      run:
                          (baseUrl, token) => _friendApi.blockUser(
                        baseUrl: baseUrl,
                        token: token,
                        targetUsername: username,
                      ),
                      successMsg: '사용자를 차단했습니다.',
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _goToProfile(String username) async {
    _showSnack('계정 정보 불러오는 중…');
    final token = await _getAuthToken();
    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (token == null || token.isEmpty || !jwtLike.hasMatch(token)) {
      debugPrint('❌ 프로필 이동 불가 - JWT 문제');
      _showSnack('로그인이 필요합니다(토큰 오류).');
      return;
    }
    try {
      final dto = await _friendApi.getUserByUsername(
        baseUrl: _baseUrl,
        token: token,
        username: username,
      );
      if (dto == null) {
        _showSnack('사용자 정보를 찾지 못했습니다.');
        return;
      }
      debugPrint(
        '[NAV] /profile | id=${dto.id}, username=${dto.username}, role=${dto.role}',
      );
      Navigator.pushNamed(
        context,
        '/profile',
        arguments: {'id': dto.id, 'username': dto.username, 'role': dto.role},
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      debugPrint('[-] 프로필 조회 실패 | code=$code | ${e.message}');
      _showSnack('프로필 조회 실패${code != null ? ' ($code)' : ''}');
    } catch (e) {
      debugPrint('[-] 프로필 조회 예외: $e');
      _showSnack('프로필 조회 중 알 수 없는 오류');
    }
  }

  /// 공통 Friend 액션 실행기 (신청/수락/거절/차단/삭제)
  Future<void> _friendAction({
    required String actionName,
    required Future<Response> Function(String baseUrl, String token) run,
    required String successMsg,
  }) async {
    final token = await _getAuthToken();
    final jwtLike = RegExp(r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$');
    if (token == null || token.isEmpty || !jwtLike.hasMatch(token)) {
      _showSnack('로그인이 필요합니다(토큰 오류).');
      return;
    }
    try {
      final res = await run(_baseUrl, token);
      final code = res.statusCode ?? -1;
      final bodyStr = FriendSearchApi._prettyJson(res.data);
      debugPrint('[Friend:$actionName] code=$code body=$bodyStr');

      if (code >= 200 && code < 300) {
        _showSnack(successMsg);
      } else {
        // 서버가 문자열 메시지를 반환한다는 명세에 맞춰 처리
        final msg =
        res.data is String
            ? res.data as String
            : (res.data?['message'] ?? res.data?.toString() ?? '');
        _showSnack('실패 ($code) ${msg.toString()}');
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final msg =
      e.response?.data is String
          ? e.response?.data
          : FriendSearchApi._prettyJson(e.response?.data);
      debugPrint('[Friend:$actionName][DIO] code=$code body=$msg');
      _showSnack('$actionName 실패${code != null ? ' ($code)' : ''}');
    } catch (e) {
      debugPrint('[Friend:$actionName][UNEXPECTED] $e');
      _showSnack('$actionName 중 알 수 없는 오류');
    }
  }

  void _onTapPost(int index, PostItemData item) {
    setState(() => _selectedPostIndex = index);
    _showSnack('게시글 선택: "${item.title}" - ${item.author} (♥${item.likes})');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _SearchTopBar(
                controller: _searchController,
                query: _query,
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchSubmitted,
                onClear: _clearSearch,
              ),
              const _SearchTabBar(),
              Expanded(
                child: TabBarView(
                  children: [
                    _AccountsTab(
                      accounts: _accounts,
                      accountSort: _accountSort,
                      loading: _accountsLoading,
                      errorText: _accountsError,
                      onChangeSort: (v) {
                        setState(() => _accountSort = v);
                        _accounts = _sortAccounts(List.of(_accounts));
                        debugPrint('[Sort] account sort -> "$_accountSort"');
                      },
                      selectedIndex: _selectedAccountIndex,
                      onTapItem:
                          (i, item) => _onTapAccount(i, item as AccountItem),
                    ),
                    _PostsTab(
                      posts: _posts,
                      postSort: _postSort,
                      onChangeSort: (v) {
                        setState(() => _postSort = v);
                        _posts = _sortPosts(List.of(_posts));
                        debugPrint('[Sort] post sort -> "$_postSort"');
                      },
                      selectedIndex: _selectedPostIndex,
                      onTapItem:
                          (i, item) => _onTapPost(i, item as PostItemData),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: CustomBottomNavigationBar(
          currentIndex: _bottomIndex,
          onTap: (i) {
            setState(() => _bottomIndex = i);
            debugPrint('BottomNav 탭 변경: index=$i');
          },
        ),
      ),
    );
  }
}

/// -------------------- 상단 바(로고+검색창) --------------------
class _SearchTopBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchTopBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset('assets/images/doppy_logo.png', width: 32, height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyLarge.copyWith(color: Colors.black),
                decoration: InputDecoration(
                  hintText: '검색',
                  hintStyle: AppTextStyles.withWeight(
                    AppTextStyles.bodyLarge,
                    FontWeight.w500,
                  ).copyWith(color: const Color(0xFF989898)),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 22,
                    color: Color(0xFF989898),
                  ),
                  suffixIcon:
                  query.isNotEmpty
                      ? IconButton(
                    tooltip: '지우기',
                    onPressed: onClear,
                    icon: const Icon(
                      Icons.clear,
                      color: Color(0xFF989898),
                    ),
                  )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFF989898), width: 1),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Colors.black, width: 1.5),
                  ),
                ),
                onChanged: onChanged,
                onSubmitted: onSubmitted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// -------------------- 탭바(커스텀 인디케이터) --------------------
class _SearchTabBar extends StatelessWidget {
  const _SearchTabBar();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: 46,
        child: TabBar(
          dividerColor: Colors.transparent,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black,
          labelStyle: AppTextStyles.withWeight(
            AppTextStyles.headlineMedium,
            FontWeight.w600,
          ),
          unselectedLabelStyle: AppTextStyles.withWeight(
            AppTextStyles.headlineMedium,
            FontWeight.w600,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 32),
          indicator: _FixedUnderlineTabIndicator(
            color: Colors.black,
            thickness: 2.0,
            bottomInset: 0.0,
            screenWidth: w,
            fraction: 0.375, // 화면 너비의 37.5%
          ),
          tabs: const [Tab(text: '계정'), Tab(text: '게시글')],
        ),
      ),
    );
  }
}

class _FixedUnderlineTabIndicator extends Decoration {
  final Color color;
  final double thickness;
  final double bottomInset;
  final double screenWidth; // 스크린 전체 폭
  final double fraction; // 스크린 폭 대비 길이 비율 (0.375 = 37.5%)

  const _FixedUnderlineTabIndicator({
    required this.color,
    required this.screenWidth,
    this.fraction = 0.375,
    this.thickness = 2.0,
    this.bottomInset = 0.0,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _FixedUnderlinePainter(
      color: color,
      thickness: thickness,
      bottomInset: bottomInset,
      indicatorWidth: screenWidth * fraction,
    );
  }
}

class _FixedUnderlinePainter extends BoxPainter {
  final Color color;
  final double thickness;
  final double bottomInset;
  final double indicatorWidth;

  _FixedUnderlinePainter({
    required this.color,
    required this.thickness,
    required this.bottomInset,
    required this.indicatorWidth,
  });

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    if (configuration.size == null) return;
    final Rect rect = offset & configuration.size!;
    final double cx = rect.center.dx; // 활성 탭 중앙
    final double half = indicatorWidth / 2;
    final double y = rect.bottom - bottomInset - thickness / 2;
    final Paint p =
    Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(cx - half, y), Offset(cx + half, y), p);
  }
}

/// -------------------- 계정 탭 --------------------
class _AccountsTab extends StatelessWidget {
  final List<AccountItem> accounts;
  final String accountSort;
  final bool loading;
  final String? errorText;
  final ValueChanged<String> onChangeSort;
  final int? selectedIndex;
  final void Function(int index, AccountItem item) onTapItem;

  const _AccountsTab({
    required this.accounts,
    required this.accountSort,
    required this.loading,
    required this.errorText,
    required this.onChangeSort,
    required this.selectedIndex,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: accountSort,
                items:
                const ['계정 이름']
                    .map(
                      (v) => DropdownMenuItem(
                    value: v,
                    child: Text(
                      v,
                      style: AppTextStyles.withWeight(
                        AppTextStyles.bodyLarge,
                        FontWeight.w600,
                      ).copyWith(color: Colors.black),
                    ),
                  ),
                )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChangeSort(v);
                },
                underline: const SizedBox.shrink(),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.black,
                ),
              ),
              if (errorText == null)
                Text(
                  '결과 ${accounts.length}건',
                  style: AppTextStyles.withWeight(
                    AppTextStyles.bodySmall,
                    FontWeight.w500,
                  ).copyWith(color: Colors.black54),
                )
              else
                Text(
                  errorText!,
                  style: AppTextStyles.withWeight(
                    AppTextStyles.bodySmall,
                    FontWeight.w600,
                  ).copyWith(color: Colors.red),
                ),
            ],
          ),
        ),
        Expanded(
          child:
          accounts.isEmpty
              ? const _EmptyResult(message: '계정 결과가 없습니다.')
              : ListView.builder(
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final item = accounts[index];
              return _AccountListItem(
                index: index,
                nickname: item.nickname,
                userId: item.userId,
                neighborCount: '이웃 ${item.neighbors}명',
                selected: selectedIndex == index,
                onTap: () => onTapItem(index, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AccountListItem extends StatelessWidget {
  final int index;
  final String nickname;
  final String userId;
  final String neighborCount;
  final bool selected;
  final VoidCallback onTap;

  const _AccountListItem({
    required this.index,
    required this.nickname,
    required this.userId,
    required this.neighborCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.black.withOpacity(0.06) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Image.asset(
                    'assets/images/profile_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            flex: 0,
                            child: Text(
                              nickname,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.withSize(
                                  AppTextStyles.bodyMedium,
                                  15,
                                ),
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              userId,
                              style: AppTextStyles.withWeight(
                                AppTextStyles.withSize(
                                  AppTextStyles.bodySmall,
                                  11,
                                ),
                                FontWeight.w600,
                              ).copyWith(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        neighborCount,
                        style: AppTextStyles.withSize(
                          AppTextStyles.labelSmall,
                          10,
                        ).copyWith(color: Colors.black54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.more_vert, color: Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// -------------------- 게시글 탭 --------------------
class _PostsTab extends StatelessWidget {
  final List<PostItemData> posts;
  final String postSort;
  final ValueChanged<String> onChangeSort;
  final int? selectedIndex;
  final void Function(int index, PostItemData item) onTapItem;

  const _PostsTab({
    required this.posts,
    required this.postSort,
    required this.onChangeSort,
    required this.selectedIndex,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DropdownButton<String>(
                value: postSort,
                items:
                const ['인기순']
                    .map(
                      (v) => DropdownMenuItem(
                    value: v,
                    child: Text(
                      v,
                      style: AppTextStyles.withWeight(
                        AppTextStyles.bodyLarge,
                        FontWeight.w600,
                      ).copyWith(color: Colors.black),
                    ),
                  ),
                )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChangeSort(v);
                },
                underline: const SizedBox.shrink(),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.black,
                ),
              ),
              Text(
                '결과 ${posts.length}건',
                style: AppTextStyles.withWeight(
                  AppTextStyles.bodySmall,
                  FontWeight.w500,
                ).copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
        Expanded(
          child:
          posts.isEmpty
              ? const _EmptyResult(message: '게시글 결과가 없습니다.')
              : ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final item = posts[index];
              return _PostListItem(
                index: index,
                title: item.title,
                author: item.author,
                preview: item.preview,
                imageUrl: item.imageUrl,
                likes: item.likes,
                selected: selectedIndex == index,
                onTap: () => onTapItem(index, item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PostListItem extends StatelessWidget {
  final int index;
  final String title;
  final String author;
  final String preview;
  final String imageUrl;
  final int likes;
  final bool selected;
  final VoidCallback onTap;

  const _PostListItem({
    required this.index,
    required this.title,
    required this.author,
    required this.preview,
    required this.imageUrl,
    required this.likes,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.black.withOpacity(0.06) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  width: 144,
                  height: 108,
                  decoration: ShapeDecoration(
                    image: DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 20,
                        child: Text(
                          title,
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodyLarge, 15),
                            FontWeight.w500,
                          ).copyWith(color: Colors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 14,
                        child: Text(
                          '$author · ♥$likes',
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodySmall, 10),
                            FontWeight.w500,
                          ).copyWith(color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 32,
                        child: Text(
                          preview,
                          style: AppTextStyles.withWeight(
                            AppTextStyles.withSize(AppTextStyles.bodySmall, 11),
                            FontWeight.w400,
                          ).copyWith(color: Colors.black54),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.check_circle,
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// -------------------- 공통: 결과 없음 --------------------
class _EmptyResult extends StatelessWidget {
  final String message;
  const _EmptyResult({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: AppTextStyles.withWeight(
          AppTextStyles.bodyMedium,
          FontWeight.w500,
        ).copyWith(color: Colors.black54),
      ),
    );
  }
}