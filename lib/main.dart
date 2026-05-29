import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'constants/app_colors.dart';
import 'screens/home_screen.dart';
import 'screens/wardrobe_screen.dart';
import 'screens/fitting_room_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check: 개발 중에는 디버그 프로바이더 사용
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );

  // 익명 로그인 (Firebase Storage 업로드 권한 확보)
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {
      // 네트워크 오류 시 무시하고 앱 계속 실행
    }
  }

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
      home: const AppShell(),
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
        return HomeScreen(onNavigate: (i) => setState(() => _tabIndex = i));
      case 1:
        return const WardrobeScreen();
      case 2:
        return FittingRoomScreen(onNavigateToDetail: _navigateToDetail);
      case 3:
        return const SettingsScreen();
      default:
        return HomeScreen(onNavigate: (i) => setState(() => _tabIndex = i));
    }
  }
}

class _BottomNav extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.activeIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: '홈'),
    _NavItem(icon: Icons.checkroom_outlined, activeIcon: Icons.checkroom, label: '옷장'),
    _NavItem(icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome, label: 'AI 피팅'),
    _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: '설정'),
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
                        width: 48,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.bluePale : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive ? AppColors.blue : AppColors.textPlaceholder,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? AppColors.blue : AppColors.textPlaceholder,
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

  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
