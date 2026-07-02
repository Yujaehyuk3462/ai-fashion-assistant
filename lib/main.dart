import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/fitting_chip.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_summary_screen.dart';
import 'screens/home_screen.dart';
import 'screens/fitting_screen.dart';
import 'screens/closet_screen.dart';
import 'screens/add_item_screen.dart';
import 'screens/care_screen.dart';
import 'screens/more_screen.dart';
import 'screens/prefs_screen.dart';
import 'screens/doc_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const DotApp(),
    ),
  );
}

class DotApp extends StatelessWidget {
  const DotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DOT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RootShell(),
    );
  }
}

/// 현재 뷰에 맞는 화면을 그리고, 전역 AI 피팅 칩을 오버레이한다.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final Widget screen = switch (app.view) {
      AppView.login => const LoginScreen(),
      AppView.onboarding => const OnboardingScreen(),
      AppView.profile => const ProfileSummaryScreen(),
      AppView.home => const HomeScreen(),
      AppView.fitting => const FittingScreen(),
      AppView.closet => const ClosetScreen(),
      AppView.addItem => const AddItemScreen(),
      AppView.care => const CareScreen(),
      AppView.more => const MoreScreen(),
      AppView.prefs => const PrefsScreen(),
      AppView.doc => const DocScreen(),
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(child: screen),
            if (app.showFitChip) const FittingChip(),
          ],
        ),
      ),
    );
  }
}
