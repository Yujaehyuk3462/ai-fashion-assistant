import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'constants/app_colors.dart';
import 'models/wardrobe_item.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/wardrobe_screen.dart';
import 'screens/fitting_room_screen.dart';
import 'screens/coord_board_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'services/agent_planner.dart';
import 'services/fitting_job_controller.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 디버그 전용 로컬 검증 경로 — `--dart-define=USE_EMULATOR=true`로 실행하면
  // 배포된 프로젝트 대신 로컬 Firebase Emulator에 붙어, 로컬 firestore.rules로
  // 저장 기능을 검증한다. 기본값 false라 일반 빌드/배포에는 전혀 영향 없음.
  // 안드로이드 에뮬레이터에서 호스트 PC는 10.0.2.2로 접근한다.
  const useEmulator = bool.fromEnvironment('USE_EMULATOR');
  if (useEmulator) {
    FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);
    await FirebaseAuth.instance.useAuthEmulator('10.0.2.2', 9099);
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
  }

  // 착장 캘린더(table_calendar)의 한국어 월/요일 표기를 위해 로케일 데이터 초기화.
  await initializeDateFormatting('ko_KR', null);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const AiFashionAssistantApp());
}

class AiFashionAssistantApp extends StatelessWidget {
  const AiFashionAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StyleAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(
                    color: AppColors.navy, strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasData) return const AppShell();
          return const LoginScreen();
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;
  bool _showItemDetail = false;

  // ── 피팅룸 아이템 상태 ──────────────────────────────────
  final Map<String, WardrobeItem?> _fittingItems = {
    '상의': null,
    '하의': null,
    '아우터': null,
  };
  WardrobeItem? _fittingUserPhoto; // 전신 사진

  // AppShell(탭 전환에도 살아있는 레벨)에서 보관 → 다른 탭으로 이동해도
  // 진행 중인 AI 분석/가상 피팅 작업과 결과가 유지된다.
  final FittingJobController _fittingJob = FittingJobController();

  @override
  void initState() {
    super.initState();
    // 레벨 1 선제 추천: 앱 진입 시 1회, 다가오는 일정을 감지해 백그라운드에서
    // 미리 추천을 준비한다. 부가 기능이라 실패해도 조용히 무시한다.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      unawaited(AgentPlanner.runProactiveCheck(uid));
    }
  }

  @override
  void dispose() {
    _fittingJob.dispose();
    super.dispose();
  }

  // 옷장 탭에서 선택 → 피팅룸 이동
  void _sendToFittingRoom(WardrobeItem item) {
    setState(() {
      _fittingItems[item.category] = item;
      _tabIndex = 2;
    });
  }

  // 홈 화면의 추천 코디 카드 탭 → 조합에 포함된 아이템들을 피팅룸 슬롯에
  // 한 번에 채우고 이동. 피팅룸은 상의/하의/아우터 슬롯만 가지므로 그 외
  // 카테고리(예: 신발)는 자연스럽게 무시된다.
  void _sendRecommendationToFittingRoom(List<WardrobeItem> items) {
    setState(() {
      for (final item in items) {
        if (_fittingItems.containsKey(item.category)) {
          _fittingItems[item.category] = item;
        }
      }
      _tabIndex = 2;
    });
  }

  // 피팅룸 인라인: 슬롯에 아이템 설정
  void _setFittingItem(String category, WardrobeItem item) {
    setState(() => _fittingItems[category] = item);
  }

  // 피팅룸 인라인: 슬롯 비우기
  void _clearFittingItem(String category) {
    setState(() => _fittingItems[category] = null);
  }

  // 피팅룸 인라인: 전신 사진 설정
  void _setFittingUserPhoto(WardrobeItem item) {
    setState(() => _fittingUserPhoto = item);
  }

  // 피팅룸 인라인: 전신 사진 초기화
  void _clearFittingUserPhoto() {
    setState(() => _fittingUserPhoto = null);
  }

  void _navigateToDetail() => setState(() {
        _showItemDetail = true;
        _tabIndex = 2;
      });

  void _backFromDetail() => setState(() => _showItemDetail = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _showItemDetail
          ? null
          : _BottomNav(
              activeIndex: _tabIndex,
              onTap: (i) => setState(() {
                _tabIndex = i;
                _showItemDetail = false;
              }),
            ),
    );
  }

  Widget _buildBody() {
    if (_showItemDetail) return ItemDetailScreen(onBack: _backFromDetail);
    switch (_tabIndex) {
      case 0:
        return HomeScreen(
          onNavigate: (i) => setState(() => _tabIndex = i),
          onOpenFittingRoom: _sendRecommendationToFittingRoom,
        );
      case 1:
        // 옷장: 아이템 선택 콜백 전달
        return WardrobeScreen(onSelectItem: _sendToFittingRoom);
      case 2:
        return FittingRoomScreen(
          jobController: _fittingJob,
          selectedItems: Map.from(_fittingItems),
          userPhoto: _fittingUserPhoto,
          onSetItem: _setFittingItem,
          onClearItem: _clearFittingItem,
          onSetUserPhoto: _setFittingUserPhoto,
          onClearUserPhoto: _clearFittingUserPhoto,
          onNavigateToDetail: _navigateToDetail,
        );
      case 3:
        return const CoordBoardScreen();
      case 4:
        return const CalendarScreen();
      case 5:
        return const SettingsScreen();
      default:
        return HomeScreen(
          onNavigate: (i) => setState(() => _tabIndex = i),
          onOpenFittingRoom: _sendRecommendationToFittingRoom,
        );
    }
  }
}

// ── 하단 네비게이션 바 ─────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.activeIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: '홈'),
    _NavItem(
        icon: Icons.checkroom_outlined,
        activeIcon: Icons.checkroom,
        label: '옷장'),
    _NavItem(
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome,
        label: 'AI 피팅'),
    _NavItem(
        icon: Icons.dashboard_customize_outlined,
        activeIcon: Icons.dashboard_customize,
        label: '코디보드'),
    _NavItem(
        icon: Icons.calendar_month_outlined,
        activeIcon: Icons.calendar_month,
        label: '캘린더'),
    _NavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = activeIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.bluePale
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive
                              ? AppColors.blue
                              : AppColors.textPlaceholder,
                          size: 21,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive
                              ? AppColors.blue
                              : AppColors.textPlaceholder,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem(
      {required this.icon, required this.activeIcon, required this.label});
}
