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
          _NavyHero(onNavigate: onNavigate),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: _ActionGrid(onNavigate: onNavigate),
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SectionHeader(
              title: '최근 착장',
              onMoreTap: () => onNavigate(1),
            ),
          ),
          const SizedBox(height: 16),
          _RecentOutfits(onNavigate: onNavigate),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const _AiTipBanner(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── 네이비 히어로 (인사 + 날씨) ──────────────────────────
class _NavyHero extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _NavyHero({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안녕하세요',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '민준님, 좋은 아침입니다',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.person_outline, color: Colors.white60, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wb_sunny_outlined, color: Color(0xFFFCD34D), size: 15),
                const SizedBox(width: 8),
                const Text(
                  '22°C  맑음',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 12, color: Colors.white24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '가벼운 재킷 또는 긴팔이 적합한 날씨입니다',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ── 액션 카드 그리드 (버그 수정: IntrinsicHeight + stretch) ─
class _ActionGrid extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _ActionGrid({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight + crossAxisAlignment.stretch 로
    // 두 카드의 높이를 항상 동일하게 보장
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.camera_alt_outlined,
              label: '내 옷 등록',
              sublabel: '사진으로 간편 등록',
              isPrimary: false,
              onTap: () => onNavigate(1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionCard(
              icon: Icons.style_outlined,
              label: 'AI 피팅',
              sublabel: '쇼핑 매치 추천',
              isPrimary: true,
              badge: 'AI',
              onTap: () => onNavigate(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final bool isPrimary;
  final String? badge;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.isPrimary,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.navy : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: isPrimary
                  ? AppColors.navy.withValues(alpha: 0.28)
                  : AppColors.navy.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.12)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isPrimary ? Colors.white : AppColors.navy,
                    size: 21,
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? Colors.white.withValues(alpha: 0.18)
                          : AppColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: isPrimary ? Colors.white : AppColors.navy,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sublabel,
              style: TextStyle(
                color: isPrimary
                    ? Colors.white.withValues(alpha: 0.58)
                    : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 섹션 헤더 ────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onMoreTap;

  const _SectionHeader({required this.title, required this.onMoreTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        GestureDetector(
          onTap: onMoreTap,
          child: Row(
            children: [
              const Text(
                '전체 보기',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_forward_ios, color: AppColors.textMuted, size: 11),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 최근 착장 가로 스크롤 ──────────────────────────────
class _RecentOutfits extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _RecentOutfits({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 215,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _recentItems.length,
        itemBuilder: (context, i) {
          final item = _recentItems[i];
          return Container(
            width: 140,
            margin: EdgeInsets.only(right: i < _recentItems.length - 1 ? 12 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: item['img']!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppColors.background),
                          errorWidget: (_, __, ___) => Container(color: AppColors.background),
                        ),
                        // 하단 그라데이션
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xBB000000)],
                              stops: [0.45, 1.0],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Text(
                            item['date']!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  item['label']!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── AI 팁 배너 ───────────────────────────────────────────
class _AiTipBanner extends StatelessWidget {
  const _AiTipBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.tips_and_updates_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '오늘의 AI 코디 팁',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '화이트 셔츠에 슬림 청바지 조합을 오늘 추천합니다.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios, color: AppColors.textDisabled, size: 13),
        ],
      ),
    );
  }
}
