import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/recommendation_entry.dart';
import '../models/wardrobe_item.dart';
import '../services/agent_activity.dart';
import '../services/firestore_service.dart';
import '../services/weather_service.dart';
import '../widgets/calendar_record_sheet.dart';

// ── 홈 화면: "DOT." 레퍼런스 디자인에 맞춰 단순화한 버전.
// 인사/날씨 히어로, 액션 그리드, 최근 착장 레일, AI 팁 배너를 하나의
// 미니멀한 세로 흐름(로고 → 오늘의 인사 → 날씨 → 추천 코디 카드)으로 정리했다.
class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  final ValueChanged<List<WardrobeItem>> onOpenFittingRoom;

  const HomeScreen({super.key, required this.onNavigate, required this.onOpenFittingRoom});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(onNavigate: onNavigate),
                const SizedBox(height: 28),
                const Text(
                  '오늘 뭐 입지?',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'AI가 옷장 속 아이템을 분석해 오늘의 코디를 추천해요',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                const _WeatherRow(),
                const SizedBox(height: 30),
                const Text(
                  '오늘의 추천 코디',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _RecommendationCard(onOpenFittingRoom: onOpenFittingRoom, onNavigate: onNavigate),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 상단 바: 로고 ──────────────────────────────────────
class _TopBar extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _TopBar({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'DOT.',
      style: TextStyle(
        color: Colors.black,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
    );
  }
}

// ── 날씨 한 줄 ────────────────────────────────────────────
// WeatherService(Open-Meteo, 서울 좌표 고정)에서 가져온다. 실패하면 하드코딩된
// 값으로 폴백하지 않고 "불러오지 못했다"고 정직하게 표시한다.
class _WeatherRow extends StatefulWidget {
  const _WeatherRow();

  @override
  State<_WeatherRow> createState() => _WeatherRowState();
}

class _WeatherRowState extends State<_WeatherRow> {
  WeatherSnapshot? _weather;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await WeatherService.fetch();
    if (!mounted) return;
    setState(() {
      _weather = snapshot;
      _loading = false;
    });
  }

  // 로컬 규칙 기반 한 줄 조언(Gemini 호출 없음) — 오늘 강수확률이 높으면
  // 비 관련 조언을 우선하고, 아니면 현재 기온대에 맞는 옷차림을 안내한다.
  String _adviceFor(WeatherSnapshot w) {
    final today = w.forDate(DateTime.now());
    if (today != null && today.precipitationProbability >= WeatherService.rainProbabilityThreshold) {
      return '비 예보가 있어요, 우산을 챙기세요';
    }
    final tempC = w.current.tempC;
    if (tempC >= 28) return '가볍고 통풍 잘 되는 소재가 좋아요';
    if (tempC >= 23) return '반팔이나 얇은 셔츠면 충분해요';
    if (tempC >= 17) return '가벼운 아우터 한 장이면 충분해요';
    if (tempC >= 9) return '니트나 가디건 등 보온에 신경 써주세요';
    return '두꺼운 아우터가 필요한 쌀쌀한 날씨예요';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
      );
    }
    final weather = _weather;
    if (weather == null) {
      return const Text(
        '날씨 정보를 불러오지 못했어요',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }
    final condition = weather.current.condition;
    return Row(
      children: [
        Icon(condition.icon, color: const Color(0xFFF59E0B), size: 18),
        const SizedBox(width: 8),
        Text(
          '서울 · ${condition.label} ${weather.current.tempC.round()}°',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _adviceFor(weather),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── 추천 코디 카드: 새 옷 등록을 계기로 백그라운드에서 자동 생성된
// 코디 1건을 큰 사진 카드로 보여준다. 없으면 AI 피팅을 유도하는 빈 상태를
// 보여준다.
class _RecommendationCard extends StatelessWidget {
  final ValueChanged<List<WardrobeItem>> onOpenFittingRoom;
  final ValueChanged<int> onNavigate;

  const _RecommendationCard({required this.onOpenFittingRoom, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _EmptyCard(onNavigate: onNavigate);

    return StreamBuilder<RecommendationEntry?>(
      stream: FirestoreService.recommendationStream(uid),
      builder: (context, snapshot) {
        final entry = snapshot.data;
        if (entry != null) {
          return StreamBuilder<List<WardrobeItem>>(
            stream: FirestoreService.wardrobeStream(),
            builder: (context, wardrobeSnapshot) {
              final byId = {
                for (final i in wardrobeSnapshot.data ?? const <WardrobeItem>[]) i.id: i,
              };
              final matchedItems =
                  entry.itemIds.map((id) => byId[id]).whereType<WardrobeItem>().toList();
              if (matchedItems.isEmpty) return _EmptyCard(onNavigate: onNavigate);
              return _RecommendationCardBody(
                key: ValueKey(entry.id),
                entry: entry,
                matchedItems: matchedItems,
                onTap: () => onOpenFittingRoom(matchedItems),
              );
            },
          );
        }
        return ValueListenableBuilder<String?>(
          valueListenable: AgentActivity.current,
          builder: (context, activity, _) {
            if (activity == null) return _EmptyCard(onNavigate: onNavigate);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      activity,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RecommendationCardBody extends StatefulWidget {
  final RecommendationEntry entry;
  final List<WardrobeItem> matchedItems;
  final VoidCallback onTap;

  const _RecommendationCardBody({
    super.key,
    required this.entry,
    required this.matchedItems,
    required this.onTap,
  });

  @override
  State<_RecommendationCardBody> createState() => _RecommendationCardBodyState();
}

class _RecommendationCardBodyState extends State<_RecommendationCardBody> {
  final _pageController = PageController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.matchedItems.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!_pageController.hasClients) return;
        final next = ((_pageController.page ?? 0).round() + 1) % widget.matchedItems.length;
        _pageController.animateToPage(next,
            duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // 추천 조합을 그대로 캘린더 착장 기록 시트에 프리필해서 연다 — 사용자가
  // 조합을 외워서 옷장에서 하나씩 다시 고르지 않아도 되게 한다(scrap_screen의
  // "캘린더에 기록"과 동일한 패턴).
  Future<void> _recordToCalendar(BuildContext context) async {
    final first = widget.matchedItems.first;
    final saved = await showCalendarRecordSheet(
      context,
      date: widget.entry.targetDate ?? DateTime.now(),
      prefillImageUrl: first.cutoutImageUrl ?? first.imageUrl,
      prefillItemIds: widget.entry.itemIds,
      prefillItemSummaries: widget.entry.itemSummaries,
      recommendationId: widget.entry.id,
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('캘린더에 착장을 기록했어요'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.blue,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final items = widget.matchedItems;
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: Container(
                color: AppColors.background,
                child: items.length <= 1
                    ? _RecommendationItemImage(item: items.first)
                    : Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          PageView.builder(
                            controller: _pageController,
                            itemCount: items.length,
                            itemBuilder: (context, i) =>
                                _RecommendationItemImage(item: items[i]),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < items.length; i++)
                                  AnimatedBuilder(
                                    animation: _pageController,
                                    builder: (context, _) {
                                      final page = _pageController.hasClients
                                          ? (_pageController.page ?? 0).round()
                                          : 0;
                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 3),
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: page == i
                                              ? Colors.white
                                              : Colors.white.withValues(alpha: 0.4),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '오늘의 추천 셋업',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${entry.itemIds.length} items',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                  if (entry.summaryText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.summaryText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _recordToCalendar(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_available_outlined,
                            color: AppColors.blue, size: 15),
                        const SizedBox(width: 6),
                        const Text('캘린더에 기록',
                            style: TextStyle(
                                color: AppColors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
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

// 추천 조합 슬라이드 한 장 — 배경 제거본이 있으면 우선 사용.
class _RecommendationItemImage extends StatelessWidget {
  final WardrobeItem item;

  const _RecommendationItemImage({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: CachedNetworkImage(
        imageUrl: item.cutoutImageUrl ?? item.imageUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) =>
            const Icon(Icons.image_not_supported_outlined, color: AppColors.textDisabled),
      ),
    );
  }
}

// ── 추천 코디가 아직 없을 때의 빈 상태 ────────────────────
class _EmptyCard extends StatelessWidget {
  final ValueChanged<int> onNavigate;

  const _EmptyCard({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.checkroom_outlined, color: AppColors.textDisabled, size: 30),
          const SizedBox(height: 12),
          const Text(
            '아직 추천 코디가 없어요',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'AI 피팅을 먼저 사용해 보세요',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => onNavigate(2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'AI 피팅 하러 가기',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
