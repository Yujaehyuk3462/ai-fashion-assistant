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
import '../services/agent_activity.dart';
import '../services/agent_planner.dart';
import '../services/firestore_service.dart';
import '../services/weather_service.dart';
import 'agent_log_screen.dart';

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
        if (entry != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _RecommendationCardBody(
              key: ValueKey(entry.id),
              entry: entry,
              onOpenFittingRoom: onOpenFittingRoom,
            ),
          );
        }
        // 추천 카드가 아직 없을 때만 "에이전트 작업 중" 인디케이터를 보여준다.
        // 파이프라인이 끝나 추천이 저장되면 위 스트림이 갱신되며 자연스럽게
        // 카드로 교체된다.
        return ValueListenableBuilder<String?>(
          valueListenable: AgentActivity.current,
          builder: (context, activity, _) {
            if (activity == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _AgentActivityIndicator(message: activity),
            );
          },
        );
      },
    );
  }
}

// 능동 추천 파이프라인이 도는 동안 카드 자리에 보여주는 얇은 상태 표시.
// 실패로 끝나면(AgentActivity가 null이 되면) 조용히 사라진다 — 별도의
// 에러 카드는 없다.
class _AgentActivityIndicator extends StatefulWidget {
  final String message;

  const _AgentActivityIndicator({required this.message});

  @override
  State<_AgentActivityIndicator> createState() => _AgentActivityIndicatorState();
}

class _AgentActivityIndicatorState extends State<_AgentActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.bluePale,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, color: AppColors.blue, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = (_controller.value - i * 0.2) % 1.0;
                  final opacity = (t < 0.5 ? t * 2 : 2 - t * 2).clamp(0.25, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
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

  // 자기 평가 루프 결과 한 줄. 일정 기반 선제 추천은 "준비해뒀어요" 어투로,
  // 새 옷 추천은 "선정/찾았어요" 어투로 구분한다.
  static String _loopSummary(RecommendationEntry entry) {
    final score = entry.colorScore;
    // 진단-수리 루프가 실제로 조합을 교체했다면 그 사실을 가장 먼저 보여준다.
    if (entry.repairAttempted && score != null) {
      return '조합을 한 번 다듬어 $score점으로 완성했어요';
    }
    if (entry.targetDate != null) {
      final tpo = entry.targetTpoTag != null ? '[${entry.targetTpoTag}]' : '이 일정';
      // 레벨 4: 차선 조합은 솔직하게 표시(거짓 만족 금지).
      if (entry.isFallback) {
        return '$tpo에 딱 맞는 조합은 없었지만, 옷장에서 가장 가까운 조합을 준비했어요 ($score점)';
      }
      // 날씨 관찰 — 이 날짜 예보가 특이했다면(비/극한 기온) 그 사실을 우선 보여준다.
      if (entry.weatherNote != null) {
        final rel = AgentPlanner.relativeLabel(entry.targetDate!);
        return '$rel $tpo — ${entry.weatherNote}';
      }
      // 레벨 3: 과거 피드백이 실제 반영된 경우에만 표시.
      if (entry.reflectedFeedback) {
        return '지난번 선택하신 스타일을 반영했어요 ($score점)';
      }
      final rel = AgentPlanner.relativeLabel(entry.targetDate!);
      return '$rel ${entry.targetTpoTag != null ? '[${entry.targetTpoTag}] ' : ''}일정을 위해 코디를 준비해뒀어요 ($score점)';
    }
    return (entry.evaluatedCount ?? 0) > 1
        ? '${entry.evaluatedCount}개 조합을 비교 평가해 $score점 조합을 선정했어요'
        : '옷장 분석 결과 $score점 조합을 찾았어요';
  }

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
                    // 일정 기반 선제 추천(targetDate 있음)은 "왜 이 카드가 떴는지"를
                    // 제목에서 바로 보여준다 — 예약 cron이 아니라 일정을 관찰한 결과임.
                    Expanded(
                      child: Text(
                        entry.targetDate != null
                            ? '${AgentPlanner.relativeLabel(entry.targetDate!)}'
                                '${entry.targetTpoTag != null ? ' [${entry.targetTpoTag}]' : ''} 일정 추천'
                            : '회원님을 위한 추천 코디',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
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
                          .map((item) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: item.cutoutImageUrl ?? item.imageUrl,
                                      width: double.infinity,
                                      height: 64,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(color: AppColors.background),
                                      errorWidget: (_, __, ___) =>
                                          Container(color: AppColors.background),
                                    ),
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
                // 자기 평가 루프가 돌았다는 것을 사용자에게 한 줄로 보여준다
                // (루프 도입 전 문서는 evaluatedCount가 없어 자동 생략).
                if (entry.evaluatedCount != null && entry.colorScore != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.autorenew, color: AppColors.blue, size: 12),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _loopSummary(entry),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // 채택률 지표 기반 자기 성능 인지 문구(선제 추천에서만 채워짐).
                if (entry.confidenceNote != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.insights_outlined, color: AppColors.textMuted, size: 12),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          entry.confidenceNote!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // "방금 한 일 보기" — 카드 하단에서 에이전트 활동 로그로 진입.
                // 카드 본체 탭(피팅룸 열기)과 겹치지 않게 자체 GestureDetector가
                // 탭을 소비한다(안쪽 제스처가 우선).
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AgentLogScreen()),
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'AI 비서가 방금 한 일 보기',
                        style: TextStyle(
                          color: AppColors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward, color: AppColors.blue, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 네이비 히어로 (인사 + 날씨) ──────────────────────────
// 날씨는 WeatherService(Open-Meteo, 서울 좌표 고정)에서 가져온다. 실패하면
// 하드코딩된 값으로 폴백하지 않고 "불러오지 못했다"고 정직하게 표시한다.
class _NavyHero extends StatefulWidget {
  final ValueChanged<int> onNavigate;

  const _NavyHero({required this.onNavigate});

  @override
  State<_NavyHero> createState() => _NavyHeroState();
}

class _NavyHeroState extends State<_NavyHero> {
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
      return '비 예보가 있어요 — 우산과 함께 어두운 톤 추천';
    }
    final tempC = w.current.tempC;
    if (tempC >= 28) return '더운 날씨예요 — 가볍고 통풍 잘 되는 소재가 좋아요';
    if (tempC >= 23) return '반팔이나 얇은 셔츠가 적당한 날씨입니다';
    if (tempC >= 17) return '가벼운 재킷 또는 긴팔이 적합한 날씨입니다';
    if (tempC >= 9) return '니트나 가디건 등 보온에 신경 써주세요';
    return '두꺼운 아우터가 필요한 쌀쌀한 날씨예요';
  }

  Widget _buildWeatherRow() {
    if (_loading) {
      return const SizedBox(
        height: 15,
        width: 15,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
      );
    }
    final weather = _weather;
    if (weather == null) {
      return const Text(
        '날씨 정보를 불러오지 못했어요',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      );
    }
    final condition = weather.current.condition;
    return Row(
      children: [
        Icon(condition.icon, color: const Color(0xFFFCD34D), size: 15),
        const SizedBox(width: 8),
        Text(
          '${weather.current.tempC.round()}°C  ${condition.label}',
          style: const TextStyle(
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
            _adviceFor(weather),
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
    );
  }

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
            child: _buildWeatherRow(),
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
