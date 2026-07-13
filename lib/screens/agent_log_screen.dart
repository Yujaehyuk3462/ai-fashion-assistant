import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/agent_log_entry.dart';
import '../services/agent_stats.dart';
import '../services/firestore_service.dart';

// 설정 "앱 설정" > "AI 비서 활동 내역"에서 진입. agent_logs 컬렉션(에이전트의
// 행동 서사)을 createdAt 내림차순으로 구독해, 날짜별 구분선과 함께 타임라인으로
// 보여준다. 같은 파이프라인(같은 relatedDocId)에 속한 연속 이벤트는 왼쪽
// 연결선으로 묶어 "한 번의 자율 작업"임을 시각적으로 드러낸다.
class AgentLogScreen extends StatelessWidget {
  const AgentLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('AI 비서 활동 내역',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: uid == null
          ? const _EmptyState()
          : Column(
              children: [
                _StatsCard(uid: uid),
                Expanded(
                  child: StreamBuilder<List<AgentLogEntry>>(
                    stream: FirestoreService.agentLogStream(uid),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.navy, strokeWidth: 2));
                      }
                      final logs = snapshot.data ?? const <AgentLogEntry>[];
                      // createdAt이 아직 서버에서 확정되지 않은 문서(로컬 쓰기 직후)는
                      // 정렬 기준이 없어 잠시 건너뛴다 — 곧 서버 타임스탬프로 채워진다.
                      final events = logs.where((e) => e.createdAt != null).toList();
                      if (events.isEmpty) return const _EmptyState();
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: events.length,
                        itemBuilder: (context, i) {
                          final event = events[i];
                          final prev = i > 0 ? events[i - 1] : null;
                          final next = i < events.length - 1 ? events[i + 1] : null;
                          final showDateHeader = prev == null ||
                              _dateLabel(prev.createdAt!) != _dateLabel(event.createdAt!);

                          // 같은 relatedDocId가 연속되면 하나의 파이프라인으로 묶는다.
                          // 목록은 최신순이라 위(prev)가 더 나중, 아래(next)가 더 이전 이벤트다.
                          final rid = event.relatedDocId;
                          final linkedToPrev =
                              rid != null && prev?.relatedDocId == rid && !showDateHeader;
                          final linkedToNext = rid != null && next?.relatedDocId == rid;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showDateHeader)
                                Padding(
                                  padding:
                                      EdgeInsets.only(top: i == 0 ? 0 : 18, bottom: 10, left: 4),
                                  child: Text(
                                    _dateLabel(event.createdAt!),
                                    style: const TextStyle(
                                      color: AppColors.textPlaceholder,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              _TimelineRow(
                                event: event,
                                timeLabel: _timeLabel(event.createdAt!),
                                linkedToPrev: linkedToPrev,
                                linkedToNext: linkedToNext,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(that).inDays;
    if (diff <= 0) return '오늘';
    if (diff == 1) return '어제';
    return '${dt.month}월 ${dt.day}일';
  }

  String _timeLabel(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// 최근 30일 채택률을 숫자로 보여주는 요약 카드 — "에이전트가 실제로
// 학습하고 있는지"를 심사/시연에서 즉시 증명하는 용도. 활동 로그
// 스트림(agentLogStream)을 같이 구독해 로그 건수가 바뀔 때마다(새 착장
// 기록 → detectFeedbackForCalendarEntry가 로그를 남기는 시점) 재계산한다
// — 화면에 머무른 채로도 최신 채택률이 반영된다.
class _StatsCard extends StatefulWidget {
  final String uid;

  const _StatsCard({required this.uid});

  @override
  State<_StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<_StatsCard> {
  Future<AgentStats>? _future;
  int? _lastLogCount;

  void _recomputeIfLogCountChanged(int logCount) {
    if (_lastLogCount == logCount) return;
    _lastLogCount = logCount;
    _future = AgentStats.compute(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AgentLogEntry>>(
      stream: FirestoreService.agentLogStream(widget.uid),
      builder: (context, logSnapshot) {
        _recomputeIfLogCountChanged(logSnapshot.data?.length ?? _lastLogCount ?? 0);
        return FutureBuilder<AgentStats>(
          future: _future,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            if (stats == null) return const SizedBox.shrink(); // 로딩 중/실패 시 조용히 생략

            if (stats.overallTotal == 0) {
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insights_outlined, color: AppColors.textDisabled, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '추천을 캘린더에 기록하면 에이전트의 학습 성과가 여기 표시돼요',
                        style:
                            const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              );
            }

            final overallPercent = ((stats.overallRate ?? 0) * 100).round();
            final tagLine = stats.byTag
                .map((t) => '[${t.tag}] ${(t.rate * 100).round()}%')
                .join(' · ');

            return Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bluePale,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.insights_outlined, color: AppColors.blue, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '이번 달 추천 채택률 $overallPercent% '
                          '(${stats.overallTotal}건 중 ${stats.overallAccepted}건)',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (tagLine.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      tagLine,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// eventType → 아이콘. 감지=눈, 생성=조합, 평가=저울, 등록=체크, 분석=두뇌, 피팅=옷.
IconData _iconFor(String eventType) {
  switch (eventType) {
    case AgentLogEntry.typeNewItemDetected:
      return Icons.visibility_outlined;
    case AgentLogEntry.typeCandidatesGenerated:
      return Icons.auto_awesome_motion_outlined;
    case AgentLogEntry.typeCandidateEvaluated:
      return Icons.balance;
    case AgentLogEntry.typeRecommendationRegistered:
      return Icons.check_circle_outline;
    case AgentLogEntry.typeAnalysisCompleted:
      return Icons.psychology_outlined;
    case AgentLogEntry.typeFittingGenerated:
      return Icons.style_outlined;
    case AgentLogEntry.typeCalendarLogged:
      return Icons.event_available_outlined;
    case AgentLogEntry.typeTaskRecovered:
      return Icons.replay_outlined;
    case AgentLogEntry.typeWeatherChecked:
      return Icons.wb_cloudy_outlined;
    default:
      return Icons.smart_toy_outlined;
  }
}

// 추천 파이프라인 이벤트는 파란색으로 강조(에이전트의 자율 작업), 분석/피팅
// 같은 단발 이벤트는 중립 톤으로 구분한다.
bool _isPipeline(String eventType) =>
    eventType == AgentLogEntry.typeNewItemDetected ||
    eventType == AgentLogEntry.typeCandidatesGenerated ||
    eventType == AgentLogEntry.typeCandidateEvaluated ||
    eventType == AgentLogEntry.typeRecommendationRegistered;

class _TimelineRow extends StatelessWidget {
  final AgentLogEntry event;
  final String timeLabel;
  final bool linkedToPrev;
  final bool linkedToNext;

  const _TimelineRow({
    required this.event,
    required this.timeLabel,
    required this.linkedToPrev,
    required this.linkedToNext,
  });

  @override
  Widget build(BuildContext context) {
    final isPipeline = _isPipeline(event.eventType);
    final accent = isPipeline ? AppColors.blue : AppColors.textMuted;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 왼쪽 레일: 점(아이콘) + 위/아래 연결선. 같은 파이프라인 이벤트끼리 잇는다.
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(width: 2, height: 6, color: linkedToPrev ? AppColors.blue.withValues(alpha: 0.3) : Colors.transparent),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isPipeline ? AppColors.bluePale : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: isPipeline ? AppColors.blue.withValues(alpha: 0.25) : AppColors.border),
                  ),
                  child: Icon(_iconFor(event.eventType), color: accent, size: 15),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: linkedToNext ? AppColors.blue.withValues(alpha: 0.3) : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 오른쪽: 메시지 카드. 묶인 이벤트는 살짝 들여쓰기해 소속을 드러낸다.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: 8, left: (linkedToPrev || linkedToNext) ? 8 : 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPipeline ? AppColors.blue.withValues(alpha: 0.18) : AppColors.border,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.message,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeLabel,
                      style: const TextStyle(color: AppColors.textPlaceholder, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.smart_toy_outlined,
                  color: AppColors.textDisabled, size: 28),
            ),
            const SizedBox(height: 18),
            const Text('아직 활동 내역이 없어요',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('AI 비서는 새 옷 등록, 코디 분석 시\n자동으로 일해요',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
