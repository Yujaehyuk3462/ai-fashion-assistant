import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../constants/style_tips.dart';
import '../models/outfit_history_entry.dart';
import '../models/recommendation_entry.dart';
import '../models/wardrobe_item.dart';
import '../services/firestore_service.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final ValueChanged<List<WardrobeItem>> onOpenFittingRoom;

  const HomeScreen({super.key, required this.onNavigate, required this.onOpenFittingRoom});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavyHero(onNavigate: onNavigate),
          _RecommendationCard(onOpenFittingRoom: onOpenFittingRoom),
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

// ── 능동 추천 카드: 새 옷 등록을 계기로 백그라운드에서 자동 생성된
// 코디 1건을 dismissed==false 중 최신 것만 노출한다. 없으면 자리 자체를
// 차지하지 않는다.
class _RecommendationCard extends StatelessWidget {
  final ValueChanged<List<WardrobeItem>> onOpenFittingRoom;

  const _RecommendationCard({required this.onOpenFittingRoom});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<RecommendationEntry?>(
      stream: FirestoreService.recommendationStream(uid),
      builder: (context, snapshot) {
        final entry = snapshot.data;
        if (entry == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: _RecommendationCardBody(
            key: ValueKey(entry.id),
            entry: entry,
            onOpenFittingRoom: onOpenFittingRoom,
          ),
        );
      },
    );
  }
}

class _RecommendationCardBody extends StatelessWidget {
  final RecommendationEntry entry;
  final ValueChanged<List<WardrobeItem>> onOpenFittingRoom;

  const _RecommendationCardBody({
    super.key,
    required this.entry,
    required this.onOpenFittingRoom,
  });

  // 닫기는 사용자가 직접 트리거한 부가 동작이라, 실패해도 카드가 조금 더
  // 남아있는 정도라 조용히 무시한다(로컬 캐시로 보통 즉시 반영된다).
  void _dismiss() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    unawaited(FirestoreService.dismissRecommendation(uid, entry.id).catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WardrobeItem>>(
      stream: FirestoreService.wardrobeStream(),
      builder: (context, snapshot) {
        final byId = {for (final i in snapshot.data ?? const <WardrobeItem>[]) i.id: i};
        final matchedItems =
            entry.itemIds.map((id) => byId[id]).whereType<WardrobeItem>().toList();

        return GestureDetector(
          onTap: matchedItems.isEmpty ? null : () => onOpenFittingRoom(matchedItems),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.bluePale,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome, color: AppColors.blue, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '회원님을 위한 추천 코디',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (entry.colorScore != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${entry.colorScore}점',
                          style: const TextStyle(
                            color: AppColors.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(Icons.close, color: AppColors.textDisabled, size: 18),
                    ),
                  ],
                ),
                if (matchedItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 64,
                    child: Row(
                      children: matchedItems
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: item.cutoutImageUrl ?? item.imageUrl,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(color: AppColors.background),
                                    errorWidget: (_, __, ___) =>
                                        Container(color: AppColors.background),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
                if (entry.summaryText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    entry.summaryText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
              sublabel: '가상 피팅·코디 분석',
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
// users/{uid}/history 중 type == fitting && fittingImageUrl != null인
// 항목만 최신순으로 골라 보여준다. 새 쿼리를 만들지 않고 기존
// getRecentHistorySilently를 재사용해 클라이언트에서 걸러낸다.
class _RecentOutfits extends StatefulWidget {
  final ValueChanged<int> onNavigate;

  const _RecentOutfits({required this.onNavigate});

  @override
  State<_RecentOutfits> createState() => _RecentOutfitsState();
}

class _RecentOutfitsState extends State<_RecentOutfits> {
  static const _maxItems = 8;

  List<OutfitHistoryEntry>? _entries; // null = 로딩 중

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _entries = const []);
      return;
    }
    // 전체 이력 중 일부만 fitting 타입일 수 있으니 넉넉히 가져와서 거른다.
    final history = await FirestoreService.getRecentHistorySilently(uid, limit: 30);
    final fittingEntries = history
        .where((e) => e.type == OutfitHistoryEntry.typeFitting && e.fittingImageUrl != null)
        .take(_maxItems)
        .toList();
    if (mounted) setState(() => _entries = fittingEntries);
  }

  String _relativeDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(that).inDays;
    if (diff <= 0) return '오늘';
    if (diff == 1) return '어제';
    return '$diff일 전';
  }

  // 저장된 코디명이 없으므로 아이템 스냅샷에서 "블랙 상의 + 그레이 하의"
  // 처럼 짧은 설명을 즉석에서 만든다.
  String _outfitLabel(OutfitHistoryEntry entry) {
    final parts = entry.items.take(2).map((i) {
      final color = i.color;
      return (color != null && color.isNotEmpty) ? '$color ${i.category}' : i.category;
    }).toList();
    return parts.isEmpty ? '코디 조합' : parts.join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null) {
      return const SizedBox(
        height: 215,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.navy, strokeWidth: 2),
        ),
      );
    }

    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.checkroom_outlined, color: AppColors.textDisabled, size: 28),
            const SizedBox(height: 10),
            const Text(
              '아직 저장된 착장이 없어요',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'AI 피팅을 먼저 사용해 보세요',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => widget.onNavigate(2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'AI 피팅 하러 가기',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 215,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final entry = entries[i];
          return Container(
            width: 140,
            margin: EdgeInsets.only(right: i < entries.length - 1 ? 12 : 0),
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
                          imageUrl: entry.fittingImageUrl!,
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
                            entry.createdAt != null ? _relativeDateLabel(entry.createdAt!) : '',
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
                  _outfitLabel(entry),
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
// fitting_room_screen.dart의 로딩 팁과 같은 풀(lib/constants/style_tips.dart)에서
// 홈 화면에 들어올 때마다 하나를 랜덤으로 뽑아 보여준다. State에 보관해
// 같은 화면에 머무는 동안(리빌드가 일어나도) 문구가 계속 바뀌지 않게 한다.
class _AiTipBanner extends StatefulWidget {
  const _AiTipBanner();

  @override
  State<_AiTipBanner> createState() => _AiTipBannerState();
}

class _AiTipBannerState extends State<_AiTipBanner> {
  final String _tip = allStyleTips[math.Random().nextInt(allStyleTips.length)];

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '오늘의 AI 코디 팁',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _tip,
                  style: const TextStyle(
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
