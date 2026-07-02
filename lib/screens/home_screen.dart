import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/status_bar.dart';
import '../widgets/bottom_nav.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final d = app.data;
    final mood = d.moods.isNotEmpty ? d.moods.first : '데일리';
    final color = d.preferColors.isNotEmpty ? d.preferColors.first : '뉴트럴';
    final items = [
      d.topTypes.isNotEmpty ? d.topTypes.first : '상의',
      d.bottomFits.isNotEmpty ? '${d.bottomFits.first} 팬츠' : '팬츠',
      '스니커즈',
    ];

    return Column(
      children: [
        const FakeStatusBar(),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.gray900, letterSpacing: -0.5),
                children: [
                  TextSpan(text: 'DOT'),
                  TextSpan(text: '.', style: TextStyle(color: AppColors.accent)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('오늘 뭐 입지?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.gray900, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text('$mood 무드 · $color 컬러 기반 추천', style: const TextStyle(fontSize: 14, color: Color(0xFF9A9A9A))),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEEEEEE))),
                  child: Row(
                    children: const [
                      Text('☀️', style: TextStyle(fontSize: 26)),
                      SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('서울 · 맑음 18°', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gray900)),
                          SizedBox(height: 3),
                          Text('가벼운 아우터 한 장이면 충분해요', style: TextStyle(fontSize: 12.5, color: Color(0xFFA0A0A0))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('오늘의 추천 코디', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Color(0xFF9A9A9A))),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFEEEEEE))),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 300,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE8E8E8), Color(0xFFD6D6D6)]),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined, size: 40, color: Color(0xFFA8A8A8)),
                              SizedBox(height: 8),
                              Text('추천 코디 이미지', style: TextStyle(fontSize: 13, color: Color(0xFF9A9A9A), fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$mood 데일리 셋업', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.gray900)),
                                const Text('3 items', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9A9A9A))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('선택하신 핏과 컬러에 맞춰 오늘 날씨에 어울리는 한 벌을 구성했어요.', style: TextStyle(fontSize: 13.5, color: Color(0xFF9A9A9A), height: 1.55)),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: [
                                for (final it in items)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(color: const Color(0xFFF4F4F4), borderRadius: BorderRadius.circular(9)),
                                    child: Text(it, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF444444))),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const BottomNav(current: AppView.home),
      ],
    );
  }
}
