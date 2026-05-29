import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';

const _recentItems = [
  {'label': '캐주얼 데일리', 'date': '오늘', 'img': 'https://images.unsplash.com/photo-1532332248682-206cc786359f?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=400&w=300&q=80'},
  {'label': '블랙 스트릿', 'date': '어제', 'img': 'https://images.unsplash.com/photo-1586231912972-d0970f9ce787?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=400&w=300&q=80'},
  {'label': '시크 코디', 'date': '2일 전', 'img': 'https://images.unsplash.com/photo-1579883180654-695b7f038d4c?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=400&w=300&q=80'},
  {'label': '모던 룩', 'date': '3일 전', 'img': 'https://images.unsplash.com/photo-1541980161-32fe8af73880?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=400&w=300&q=80'},
  {'label': '스트릿 웨어', 'date': '4일 전', 'img': 'https://images.unsplash.com/photo-1689044611227-3267fabaf76a?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=400&w=300&q=80'},
];

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(onNavigate: onNavigate),
          _ActionCards(onNavigate: onNavigate),
          const SizedBox(height: 24),
          _RecentOutfits(onNavigate: onNavigate),
          const SizedBox(height: 16),
          const _AiTipCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _Header({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyLight],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안녕하세요',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '민준님, 좋은 아침이에요 👋',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('😎', style: TextStyle(fontSize: 18))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.wb_sunny, color: Color(0xFFFCD34D), size: 18),
                const SizedBox(width: 6),
                const Text(
                  '22°C 맑음',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 16, color: Colors.white30),
                const SizedBox(width: 8),
                const Icon(Icons.water_drop, color: Color(0xFF93C5FD), size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '가벼운 재킷 or 긴팔 딱 좋은 날씨예요',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCards extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _ActionCards({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Transform.translate(
        offset: const Offset(0, -16),
        child: Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.camera_alt,
                iconBg: AppColors.bluePale,
                iconColor: AppColors.blue,
                title: '내 옷\n등록하기',
                subtitle: '사진으로 간편 등록',
                titleColor: AppColors.textPrimary,
                subtitleColor: AppColors.textPlaceholder,
                bg: AppColors.surface,
                shadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 4))],
                onTap: () => onNavigate(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                children: [
                  _ActionCard(
                    icon: Icons.auto_awesome,
                    iconBg: Colors.white.withValues(alpha: 0.2),
                    iconColor: Colors.white,
                    title: '쇼핑 매치\n피팅하기',
                    subtitle: 'AI 코디 추천',
                    titleColor: Colors.white,
                    subtitleColor: Colors.white.withValues(alpha: 0.7),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1D4ED8), AppColors.blue, AppColors.blueLight],
                    ),
                    shadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 4))],
                    onTap: () => onNavigate(2),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color titleColor;
  final Color subtitleColor;
  final Color? bg;
  final Gradient? gradient;
  final List<BoxShadow>? shadow;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.subtitleColor,
    this.bg,
    this.gradient,
    this.shadow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: shadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: titleColor, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: subtitleColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentOutfits extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _RecentOutfits({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '최근 착장',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              GestureDetector(
                onTap: () => onNavigate(1),
                child: const Row(
                  children: [
                    Text('전체 보기', style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, color: AppColors.blue, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recentItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final item = _recentItems[i];
                return SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(
                                imageUrl: item['img']!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: AppColors.background),
                                errorWidget: (_, __, ___) => Container(color: AppColors.background),
                              ),
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Color(0x80000000)],
                                    stops: [0.5, 1.0],
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item['date']!,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['label']!,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AiTipCard extends StatelessWidget {
  const _AiTipCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEEF4FF), Color(0xFFDBEAFE)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘의 AI 코디 팁',
                    style: TextStyle(color: Color(0xFF1E3A8A), fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '화이트 셔츠 + 슬림 청바지 = 데이트룩으로 완벽해요 ✨',
                    style: TextStyle(color: AppColors.blue, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}