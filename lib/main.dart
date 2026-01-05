import 'package:doppy/data/services/upload_service.dart';
import 'package:doppy/data/models/friend_model.dart';
import 'package:doppy/editor/postwrite_screen.dart';
import 'package:doppy/editor/service/node_component_service.dart';
import 'package:doppy/editor/service/sticker_service.dart';
import 'package:doppy/pages/screens/search_screen.dart';
import 'package:doppy/providers/feed_provider/feed_ui_service.dart';
import 'package:doppy/pages/screens/home_screen.dart';
import 'package:doppy/data/services/home_data_service.dart';
import 'package:doppy/pages/components/custom_bottom_navigation_bar.dart';
import 'package:doppy/pages/components/received_request_bottom_sheet.dart';
import 'package:doppy/pages/screens/splash_screen.dart';
import 'package:doppy/pages/screens/user_profile_screen.dart';
import 'package:doppy/pages/screens/email_verification_screen.dart';

import 'package:doppy/pages/screens/onboarding_screen.dart';
import 'package:doppy/providers/auth_provider.dart';
import 'package:doppy/providers/friend_provider.dart';
import 'package:doppy/providers/group_provider.dart';
import 'package:doppy/providers/feed_provider/other_profile_feed_provider.dart';
import 'package:doppy/providers/theme_provider.dart';
import 'package:doppy/providers/user_provider.dart';
import 'package:doppy/providers/locale_provider.dart';
// import 'package:doppy/providers/feed_provider.dart';
import 'package:doppy/providers/feed_provider/my_profile_feed_provider.dart';
import 'package:doppy/providers/search_provider.dart';
import 'package:doppy/data/services/search_service.dart';
import 'package:doppy/utils/network_utils.dart';
import 'package:doppy/l10n/app_localizations.dart';
import 'package:doppy/data/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:overlay_support/overlay_support.dart';
import 'firebase_options.dart';
import 'theme/theme.dart';
import 'utils/route_observer.dart';
import 'utils/deep_link_ingress.dart';
import 'utils/deep_link_store.dart';
import 'data/services/deep_link_service.dart';
import 'package:doppy/image/media_picker_screen.dart';

// Global NavigatorKey for accessing context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🎯 테스트용 OS 언어 설정 플래그 (나중에는 동적으로 결정)
// true: 한국어 강제, false: 영어 강제, null: 실제 OS 언어 사용
const bool? kTestForceKorean = true; // null이면 실제 OS 언어 사용

/// 위로 스와이프하여 닫을 수 있는 알림 위젯
class _DismissibleNotification extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _DismissibleNotification({
    required this.child,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_DismissibleNotification> createState() =>
      _DismissibleNotificationState();
}

class _DismissibleNotificationState extends State<_DismissibleNotification> {
  double _dragOffset = 0.0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onVerticalDragStart: (_) {
        setState(() {
          _isDragging = true;
        });
      },
      onVerticalDragUpdate: (details) {
        // 위로만 드래그 가능 (음수 방향)
        if (details.primaryDelta! < 0) {
          setState(() {
            _dragOffset += details.primaryDelta!;
            // 최대 드래그 거리 제한
            if (_dragOffset < -200) {
              _dragOffset = -200;
            }
          });
        }
      },
      onVerticalDragEnd: (details) {
        setState(() {
          _isDragging = false;
        });
        // 일정 거리 이상 위로 드래그하면 닫기
        if (_dragOffset < -80) {
          widget.onDismiss();
        } else {
          // 원위치로 복귀
          setState(() {
            _dragOffset = 0.0;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _dragOffset, 0),
        child: Opacity(
          opacity:
              _isDragging ? (1.0 + _dragOffset / 200).clamp(0.0, 1.0) : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}

// 🎯 FCM Background 메시지 핸들러 (top-level 함수로 선언)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase 초기화 필요 (background isolate에서는 별도로 초기화해야 함)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM] 백그라운드 메시지 수신: ${message.messageId}');
  debugPrint('[FCM] 데이터: ${message.data}');
  debugPrint(
    '[FCM] 알림: ${message.notification?.title} - ${message.notification?.body}',
  );
}

// 앱 버전 및 상수
class AppConstants {
  static const String appVersion = '1.0.1';

  // 🎯 웹 도메인 (Universal Links/App Links용)
  static const String webDomain = 'www.doppy.app';
  static const String webBaseUrl = 'https://www.doppy.app';

  // 🎯 이용약관 및 개인정보 처리방침 URL
  static const String termsOfServiceUrl =
      'https://www.notion.so/doppy-2a594e338df780e1b6b9fddb9753e728';
  static const String privacyPolicyUrl =
      'https://www.notion.so/doppy-2a594e338df780e1b6b9fddb9753e728'; // TODO: 개인정보 처리방침 URL로 변경 필요

  // 🎯 문의하기 이메일 주소
  static const String contactEmail = 'app.doppy@gmail.com';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🎯 Firebase 초기화
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    debugPrint('[Firebase] 플랫폼: ${defaultTargetPlatform}');

    await Firebase.initializeApp(options: options);

    // 🎯 FCM 백그라운드 메시지 핸들러 등록 (Firebase 초기화 후)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 🎯 FCM 포그라운드 메시지 핸들러 등록
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] 포그라운드 메시지 수신: ${message.messageId}');
      debugPrint('[FCM] 데이터: ${message.data}');
      debugPrint(
        '[FCM] 알림: ${message.notification?.title} - ${message.notification?.body}',
      );

      // 🎯 포그라운드에서도 앱 내부 알림 표시
      final notification = message.notification;
      if (notification != null) {
        final context = navigatorKey.currentContext;
        if (context != null) {
          showOverlayNotification((context) {
            return _DismissibleNotification(
              onTap: () {
                // ✅ 알림 탭 시: pending 저장 → /splash로 스택 리셋 (항상 Splash부터)
                final deepLink = message.data['deepLink'] as String?;
                if (deepLink != null && deepLink.isNotEmpty) {
                  DeepLinkIngress().ingestUrl(
                    deepLink,
                    source: 'fcm_foreground',
                  );
                } else {
                  // 🎯 type 필드로 처리 (딥링크가 없는 경우)
                  final type = message.data['type'] as String?;
                  if (type == 'FRIEND_REQUEST') {
                    DeepLinkIngress().ingestUrl(
                      'doppy://friends/requests',
                      source: 'fcm_foreground',
                    );
                  }
                }
                // 알림 닫기
                OverlaySupportEntry.of(context)?.dismiss();
              },
              onDismiss: () {
                OverlaySupportEntry.of(context)?.dismiss();
              },
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  notification.title ?? '알림',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    letterSpacing: -0.3,
                                    height: 1.3,
                                  ),
                                ),
                                if (notification.body != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    notification.body!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
                                      height: 1.4,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.4),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }, duration: const Duration(seconds: 3));
        }
      }
    });

    // ✅ 앱 종료 상태 초기 진입(푸시/딥링크) 캡처
    await DeepLinkIngress().captureInitialEntry();
  } catch (e) {
    debugPrint('[Firebase] 초기화 실패: $e');
  }

  // 1. FlutterSecureStorage 인스턴스를 생성합니다.
  const storage = FlutterSecureStorage();

  // 2. 'hasSeenOnboarding' 키의 값을 문자열로 읽어옵니다.
  final String? hasSeenOnboardingStr = await storage.read(
    key: 'hasSeenOnboarding',
  );

  // 3. 읽어온 값이 'true' 문자열인지 확인합니다.
  final bool hasSeenOnboarding = hasSeenOnboardingStr == 'true';

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (_) => OtherProfileFeedProvider(),
        ), // 싱글톤 인스턴스 사용
        ChangeNotifierProvider(
          create: (_) => MyProfileFeedProvider(),
        ), // 내 피드용 (싱글톤 인스턴스 사용)
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => CategoryOverlayProvider()),
        ChangeNotifierProvider(create: (_) => PostDragDropService()),

        ChangeNotifierProvider(create: (_) => SearchService()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => NodeComponentService()),
        ChangeNotifierProvider(create: (_) => StickerService()),
        ChangeNotifierProvider(create: (_) => UploadService()),
      ],
      child: MyApp(
        hasSeenOnboarding: hasSeenOnboarding,
      ), // MyApp 위젯을 child로 감싸줍니다.
    ),
  );

  // ✅ 앱 실행 중 진입 이벤트는 "pending 저장 → /splash로 스택 리셋"으로 통일
  // 플랫폼 pushRoute(/334, /username 등)가 매우 이른 타이밍에 들어오는 케이스가 있어
  // 가능한 한 빨리 observer/stream을 붙여 Navigator가 라우트를 push하는 것을 막는다.
  DeepLinkIngress().start();

  // 전역 1회: 네트워크 모니터/재로딩 코디네이터 시작
  try {
    NetworkManager.initConnectivityMonitor();
  } catch (_) {}
  ConnectivityReloadCoordinator().start();
}

class MyApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  const MyApp({super.key, required this.hasSeenOnboarding});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return OverlaySupport(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Doppy',
            debugShowCheckedModeBanner: false,

            // 다국어 설정
            locale: localeProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              const AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],

            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: context.watch<ThemeProvider>().themeMode,
            // onGenerateInitialRoutes를 사용하므로 home는 사용하지 않는다.
            // (Flutter assert: home == null || onGenerateInitialRoutes == null)
            initialRoute: '/splash',
            navigatorObservers: [routeObserver],
            // ✅ IMPORTANT:
            // Flutter 엔진 initialRoute가 /334 같은 "경로(path-only)"로 들어오면,
            // Navigator가 기본 규칙에 따라 `['/', '/334']`처럼 "2개 라우트"를 초기 스택에 생성할 수 있다.
            // 그러면 RootShell(Home)이 "pop 가능한 화면"처럼 보이며(뒤로가기 아이콘),
            // 딥링크 진입 시 홈이 push된 것 같은 증상이 발생한다.
            //
            // 따라서 어떤 진입 경로든 초기 스택은 "Splash 1장"으로 강제하고,
            // initialRoute는 pending 딥링크로만 저장한 뒤 Splash bootstrap 완료 후 처리한다.
            onGenerateInitialRoutes: (String initialRouteName) {
              try {
                // captureInitialEntry()가 이미 pending을 저장했을 수도 있으므로 중복 저장은 피한다.
                if (!DeepLinkStore.hasPending &&
                    initialRouteName.isNotEmpty &&
                    initialRouteName != Navigator.defaultRouteName &&
                    // ✅ 앱 내부 라우트는 딥링크로 취급하지 않는다.
                    // (예: '/splash'가 포스트ID로 오인되어 "포스트를 불러올 수 없습니다" 스낵바가 뜨는 문제 방지)
                    initialRouteName != '/splash' &&
                    initialRouteName != '/login' &&
                    initialRouteName != '/post-write') {
                  final result = DeepLinkService.parseDeepLink(
                    initialRouteName,
                  );
                  if (result != null && result.type != DeepLinkType.unknown) {
                    debugPrint(
                      '[Navigator] 🔗 engine initialRoute captured: $initialRouteName',
                    );
                    DeepLinkStore.setPending(
                      result,
                      source: 'engine_initial_route',
                    );
                  }
                }
              } catch (e) {
                debugPrint(
                  '[Navigator] onGenerateInitialRoutes failed (ignored): $e',
                );
              }

              return <Route<dynamic>>[
                MaterialPageRoute<dynamic>(
                  settings: const RouteSettings(name: '/splash'),
                  builder: (_) => const SplashScreen(),
                ),
              ];
            },
            routes: {
              '/splash': (_) => const SplashScreen(),
              '/login': (_) => const LoginScreen(),
              '/post-write': (_) => PostwriteScreen(isEditingMode: false),
              '/email-verify': (_) => const EmailVerificationScreen(),
            },

            // ✅ IMPORTANT: iOS/Android App Links가 "엔진 initialRoute"로 들어올 수 있음 (예: /334)
            // Flutter 엔진은 딥링크 URL(https://www.doppy.app/334)을 받아서 경로(/334)만 추출해
            // MaterialApp.initialRoute로 설정하는데, 이건 Flutter의 기본 동작이라 네이티브 설정으로는 막을 수 없음.
            // 따라서 여기서 fallback으로 처리: 경로를 synthetic URL로 복원해 딥링크로 파싱하고 Splash로 보냄.
            // (정상 케이스는 captureInitialEntry()의 getInitialLink()가 먼저 처리함)
            onGenerateRoute: (settings) {
              final name = settings.name;
              // 이미 pending이 있으면 무시 (captureInitialEntry()가 이미 처리했을 가능성)
              if (DeepLinkStore.hasPending) {
                debugPrint(
                  '[Navigator] ⏭️ onGenerateRoute skipped (pending exists): $name',
                );
                return MaterialPageRoute(
                  settings: const RouteSettings(name: '/splash'),
                  builder: (_) => const SplashScreen(),
                );
              }
              if (name != null && name != '/' && name.startsWith('/')) {
                // 예: /334, /334/slug, /profile/username 등
                // parseDeepLink()가 경로만 들어와도 자동으로 보정하므로 그대로 전달
                final result = DeepLinkService.parseDeepLink(name);
                if (result != null && result.type != DeepLinkType.unknown) {
                  debugPrint('[Navigator] 🔗 engine route as deep link: $name');
                  DeepLinkStore.setPending(
                    result,
                    source: 'engine_initial_route',
                  );
                  return MaterialPageRoute(
                    settings: const RouteSettings(name: '/splash'),
                    builder: (_) => const SplashScreen(),
                  );
                }
              }
              return null; // 기본 routing 유지
            },

            // ✅ 어떤 경로로 들어오든 Splash부터 다시 밟는 정책:
            // 등록되지 않은 라우트로 pushNamed가 호출되면 HomeScreen으로 떨어지지 않도록 한다.
            onUnknownRoute: (settings) {
              debugPrint('[Navigator] ❓ unknown route: ${settings.name}');
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            },
          ),
        );
      },
    );
  }
}

class RootShell extends StatefulWidget {
  final int initialIndex; // 0:홈,1:검색,2:작성,3:프로필
  final HomeData? preloadedHomeData; // 스플래시 선로딩 데이터 전달용
  const RootShell({super.key, this.initialIndex = 0, this.preloadedHomeData});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  late int _index;
  // 🎯 탭 활성 인덱스 (IndexedStack 하위 위젯들이 외부 변화(키보드 등)로 불필요하게 rebuild되지 않도록 제어)
  late final ValueNotifier<int> _activeIndexNotifier;

  // 🎯 검색 탭에 "명령"으로 전달할 초기 검색어 (위젯 파라미터로 rebuild 유발하지 않음)
  late final ValueNotifier<String?> _searchInitialQueryNotifier;

  // 🎯 탭 위젯은 한 번만 생성해서 재사용 (Element.updateChild에서 동일 인스턴스면 update 스킵)
  late final Widget _homeTab;
  late final Widget _searchTab;
  late final Widget _profileTab;
  late final List<Widget> _tabs;

  bool _isCheckingRequests = false; // 🎯 요청 확인 중인지 추적

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _activeIndexNotifier = ValueNotifier<int>(_index);
    _searchInitialQueryNotifier = ValueNotifier<String?>(null);

    // ✅ 홈 탭: 활성 여부는 notifier로만 갱신 (RootShell rebuild와 분리)
    _homeTab = ValueListenableBuilder<int>(
      valueListenable: _activeIndexNotifier,
      builder: (context, idx, _) {
        return HomeScreen(
          key: HomeScreenState.globalKey,
          preloadedHomeData: widget.preloadedHomeData,
          isActive: idx == 0,
          onOpenSearchScreen: (query) => _openSearchScreen(query),
        );
      },
    );

    // ✅ 검색 탭: 비활성 상태면 내부에서 즉시 return하도록 위젯 자체가 제어
    _searchTab = SearchScreenOverlay(
      activeIndexListenable: _activeIndexNotifier,
      tabIndex: 1,
      initialQueryListenable: _searchInitialQueryNotifier,
      onClose: _closeSearchScreen,
      onTabChange: _handleTabChange,
    );

    _profileTab = const UserProfileScreen(isFromBottomTab: true);
    _tabs = <Widget>[
      _homeTab,
      _searchTab,
      const SizedBox.shrink(),
      _profileTab,
    ];
    // 라이프사이클 옵저버 등록
    WidgetsBinding.instance.addObserver(this);

    // 🎯 앱 진입 시 받은 요청 확인 및 바텀시트 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowReceivedRequests();
    });
  }

  /// 🎯 받은 요청 확인 및 바텀시트 표시
  Future<void> _checkAndShowReceivedRequests() async {
    if (!mounted || _isCheckingRequests) return;

    final friendProvider = context.read<FriendProvider>();

    // 🎯 받은 요청 데이터가 아직 로드되지 않았을 수 있으므로, 먼저 로드 시도
    // 캐시가 있으면 즉시 반환되고, 없으면 서버에서 로드
    try {
      await friendProvider.fetchAllFriendData(forceRefresh: false);
    } catch (e) {
      debugPrint('[RootShell] 받은 요청 로드 실패: $e');
    }

    if (!mounted) return;

    final receivedRequests = friendProvider.receivedRequests;
    debugPrint('[RootShell] 받은 요청 개수: ${receivedRequests.length}');

    // 받은 요청이 있으면 리스트로 한 번에 표시
    if (receivedRequests.isNotEmpty) {
      _isCheckingRequests = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder:
              (context) => ReceivedRequestBottomSheet(
                requests: List<Friend>.from(receivedRequests),
              ),
        ).then((_) {
          if (mounted) {
            _isCheckingRequests = false;
          }
        });
      });
    } else {
      // 받은 요청이 없으면 FriendProvider를 listen하여 나중에 업데이트 확인
      friendProvider.addListener(_onFriendProviderChanged);
    }
  }

  /// 🎯 FriendProvider 변경 시 받은 요청 확인
  void _onFriendProviderChanged() {
    if (!mounted || _isCheckingRequests) return;

    final friendProvider = context.read<FriendProvider>();
    final receivedRequests = friendProvider.receivedRequests;

    debugPrint(
      '[RootShell] FriendProvider 변경 - 받은 요청 개수: ${receivedRequests.length}',
    );

    if (receivedRequests.isNotEmpty) {
      friendProvider.removeListener(_onFriendProviderChanged);
      _isCheckingRequests = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder:
              (context) => ReceivedRequestBottomSheet(
                requests: List<Friend>.from(receivedRequests),
              ),
        ).then((_) {
          if (mounted) {
            _isCheckingRequests = false;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    // 라이프사이클 옵저버 해제
    WidgetsBinding.instance.removeObserver(this);
    // FriendProvider 리스너 해제
    try {
      context.read<FriendProvider>().removeListener(_onFriendProviderChanged);
    } catch (_) {}
    _activeIndexNotifier.dispose();
    _searchInitialQueryNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 포그라운드로 전환 시 FCM 토큰 검사 및 필요시 재발급
    if (state == AppLifecycleState.resumed) {
      _checkAndSyncFcmTokenOnForeground();
      // 🎯 MediaPickerScreen이 열려있으면 첫 페이지 새로고침
      MediaPickerScreen.refreshCurrentInstance();
    }
  }

  /// 포그라운드 전환 시 인증 토큰 및 FCM 토큰 검사 및 필요시 재발급
  void _checkAndSyncFcmTokenOnForeground() {
    // 로그인 상태 확인 후 토큰 검사
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isLoggedIn) {
      try {
        // 🎯 1. 인증 토큰 검증 및 갱신 (세션 만료 다이얼로그 표시 전에 미리 갱신)
        // 비동기로 처리하여 UI를 막지 않음
        authProvider
            .validateAndRefreshToken()
            .then((isValid) {
              if (!isValid) {
                debugPrint(
                  '[RootShell] 포그라운드 전환 시 인증 토큰 갱신 실패 - 세션이 만료되었을 수 있음',
                );
                // 토큰 갱신 실패 시 다음 API 호출 시 세션 만료 다이얼로그가 표시됨
                return;
              }
              debugPrint('[RootShell] ✅ 포그라운드 전환 시 인증 토큰 검증 완료');
            })
            .catchError((e) {
              debugPrint('[RootShell] 포그라운드 전환 시 인증 토큰 검증 오류 (무시): $e');
            });

        // 🎯 2. FCM 토큰 검사 및 필요시 재발급 후 서버에 전송
        // 비동기로 처리하여 UI를 막지 않음
        final authService = AuthService();
        authService
            .syncFcmTokenAndSettings()
            .then((permissionGranted) {
              // 🎯 알림 권한이 허용되었으면 로컬 설정도 on으로 동기화
              if (permissionGranted == true && mounted) {
                try {
                  final userProvider = Provider.of<UserProvider>(
                    context,
                    listen: false,
                  );
                  userProvider
                      .loadSettings()
                      .then((_) {
                        userProvider.updateNotificationEnabled(true);
                      })
                      .catchError((e) {});
                } catch (e) {}
              }
            })
            .catchError((e) {
              debugPrint('[RootShell] 포그라운드 전환 시 FCM 토큰 검사 및 동기화 실패 (무시): $e');
            });

        // 🎯 3. 피드 데이터 자동 새로고침 (홈 화면이 활성화되어 있을 때만)
        _refreshFeedOnForeground();

        // 🎯 4. 사용자 프로필 정보 재동기화
        _refreshProfileOnForeground();

        // 🎯 5. 친구 요청 자동 확인 (비활성화)
        // _checkFriendRequestsOnForeground();
      } catch (e) {
        debugPrint('[RootShell] 포그라운드 전환 시 토큰 검사 오류 (무시): $e');
      }
    }
  }

  /// 🎯 포그라운드 복귀 시 내 프로필 피드 데이터 새로고침
  void _refreshFeedOnForeground() {
    try {
      final myProfileFeedProvider = Provider.of<MyProfileFeedProvider>(
        context,
        listen: false,
      );
      // ✅ 피드가 이미 메모리에 있으면(캐시/인메모리) 강제 새로고침 금지
      // - 백그라운드 복귀 때마다 invalidateCache + force load를 하면
      //   화면이 비었다가(shimmer) 다시 채워지는 현상이 무조건 발생함.
      final hasFeedData =
          myProfileFeedProvider.categories.isNotEmpty ||
          myProfileFeedProvider.posts.isNotEmpty;
      if (hasFeedData) {
        debugPrint('[RootShell] ⏭️ 포그라운드 복귀 - 내 프로필 피드가 있어 새로고침 스킵');
        return;
      }

      // 데이터가 없을 때만 초기 로드
      myProfileFeedProvider
          .loadInitial(force: true)
          .then((_) {
            debugPrint('[RootShell] ✅ 포그라운드 복귀 - 내 프로필 피드 로드 완료');
          })
          .catchError((e) {
            debugPrint('[RootShell] 포그라운드 복귀 - 내 프로필 피드 로드 실패 (무시): $e');
          });
    } catch (e) {
      debugPrint('[RootShell] 포그라운드 복귀 - 내 프로필 피드 새로고침 오류 (무시): $e');
    }
  }

  /// 🎯 포그라운드 복귀 시 사용자 프로필 정보 재동기화
  void _refreshProfileOnForeground() {
    try {
      // 🎯 피드 정보가 이미 있으면 프로필 재로드 불필요
      final myProfileFeedProvider = Provider.of<MyProfileFeedProvider>(
        context,
        listen: false,
      );
      final bool hasFeedData =
          myProfileFeedProvider.categories.isNotEmpty ||
          myProfileFeedProvider.posts.isNotEmpty;

      if (hasFeedData) {
        debugPrint('[RootShell] ⏭️ 피드 정보가 이미 있어 프로필 재로드 건너뜀');
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider
          .fetchMyProfile()
          .then((_) {
            debugPrint('[RootShell] ✅ 포그라운드 복귀 - 프로필 정보 재동기화 완료');
          })
          .catchError((e) {
            debugPrint('[RootShell] 포그라운드 복귀 - 프로필 정보 재동기화 실패 (무시): $e');
          });
    } catch (e) {
      debugPrint('[RootShell] 포그라운드 복귀 - 프로필 정보 재동기화 오류 (무시): $e');
    }
  }

  // 검색 화면 열기
  void _openSearchScreen([String? initialQuery]) {
    if (!mounted) return;
    // ✅ "명령" 전달 (위젯 파라미터 변경으로 rebuild 유발하지 않음)
    _searchInitialQueryNotifier.value = initialQuery;

    setState(() {
      _index = 1; // 검색 탭으로 전환
    });
    _activeIndexNotifier.value = 1;
  }

  void _closeSearchScreen() {
    if (!mounted) return;
    _searchInitialQueryNotifier.value = null;
    setState(() {
      _index = 0;
    });
    _activeIndexNotifier.value = 0;
  }

  // 탭 변경 처리 (검색 화면에서 호출)
  void _handleTabChange(int index) {
    if (!mounted) return;

    // 글쓰기 탭(2)은 글쓰기 화면 열기
    if (index == 2) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  PostwriteScreen(isEditingMode: false),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    // 일반 탭 전환
    setState(() {
      _index = index;
    });
    _activeIndexNotifier.value = index;
    if (index != 1) {
      _searchInitialQueryNotifier.value = null;
    }
  }

  void _onTap(int i) {
    final searchResultProvider = context.read<SearchProvider>();

    // 홈 탭 클릭
    if (i == 0) {
      if (searchResultProvider.isSearchOverlayVisible) {
        searchResultProvider.setSearchOverlayVisible(false);
      }
      setState(() {
        _index = 0;
      });
      _activeIndexNotifier.value = 0;
      _searchInitialQueryNotifier.value = null;
      return;
    }

    // 검색 탭 클릭
    if (i == 1) {
      _openSearchScreen();
      return;
    }

    // 글쓰기 탭 클릭
    if (i == 2) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  PostwriteScreen(isEditingMode: false),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }

    // 프로필 탭 클릭
    setState(() {
      _index = i;
    });
    _activeIndexNotifier.value = i;
    if (i != 1) {
      _searchInitialQueryNotifier.value = null;
    }

    // 다른 탭으로 이동 시 검색 오버레이 상태 해제
    if (i != 0) {
      searchResultProvider.setSearchOverlayVisible(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 각 탭의 화면을 IndexedStack으로 재사용 (새로 만들어지지 않음)
    // 🎯 adjustResize 모드에서는 MediaQuery.size가 변경되므로, LayoutBuilder로 실제 제약 사용
    return Material(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 🎯 View.of로 실제 물리적 화면 크기 가져오기 (adjustResize 영향을 받지 않음)
          final view = View.of(context);
          final viewSize = view.physicalSize / view.devicePixelRatio;
          final bottomBarHeight = 72.0; // CustomBottomNavigationBar의 고정 높이

          return Stack(
            children: [
              // 모든 탭 화면을 미리 생성하고 IndexedStack으로 관리 (상태 유지)
              IndexedStack(index: _index, children: _tabs),
              // 플로팅 바텀 네비게이션 바
              // 🎯 View.of로 가져온 실제 물리적 화면 크기를 기준으로 절대 위치 계산
              // adjustResize로 Stack 크기가 변경되어도 실제 화면 하단에 고정
              // 키보드가 올라와도 실제 화면 하단에 고정 (키보드가 바텀바를 덮고 올라옴)
              Positioned(
                left: 0,
                right: 0,
                top: viewSize.height - bottomBarHeight,
                child: CustomBottomNavigationBar(
                  currentIndex: _index,
                  actualIndex: _index,
                  onTap: _onTap,
                  isSearching: context.watch<SearchProvider>().isSearchActive,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
