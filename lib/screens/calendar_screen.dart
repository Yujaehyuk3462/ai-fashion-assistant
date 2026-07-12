import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import '../constants/app_colors.dart';
import '../constants/tpo_tags.dart';
import '../models/agent_log_entry.dart';
import '../models/outfit_calendar_entry.dart';
import '../services/agent_planner.dart';
import '../services/firestore_service.dart';
import '../widgets/calendar_record_sheet.dart';
import '../widgets/weekly_plan_sheet.dart';

// 착장 캘린더(OOTD 기록) 탭. 월간 뷰에서 기록 있는 날에 마커를 찍고,
// 날짜를 누르면 그날 기록을 아래에 보여준다. 기록이 없으면 추가 버튼.
// 이 데이터는 이후 에이전트가 선제 추천/주간 플랜에 활용한다.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = OutfitCalendarEntry.normalizeDate(DateTime.now());
  bool _planning = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // 오늘 자정 기준. 미래 날짜인지 판정에 쓴다.
  DateTime get _today => OutfitCalendarEntry.normalizeDate(DateTime.now());
  bool _isFuture(DateTime day) => day.isAfter(_today);

  List<OutfitCalendarEntry> _entriesForDay(
      List<OutfitCalendarEntry> monthEntries, DateTime day) {
    return monthEntries.where((e) => isSameDay(e.date, day)).toList();
  }

  Future<void> _openRecordSheet() async {
    await showCalendarRecordSheet(context, date: _selectedDay);
    // 저장은 Firestore 스트림으로 자동 반영되므로 별도 새로고침이 필요 없다.
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? AppColors.red : AppColors.navy,
    ));
  }

  // ── 레벨 2: 주간 코디 플랜 ──────────────────────────────
  Future<void> _runWeeklyPlan() async {
    final uid = _uid;
    if (uid == null || _planning) return;
    setState(() => _planning = true);
    try {
      final plan = await AgentPlanner.generateWeeklyPlan(uid);
      if (!mounted) return;
      await showWeeklyPlanSheet(context, plan: plan, onConfirm: _confirmPlanDay);
    } on StateError catch (e) {
      _showSnack(e.message, isError: true);
    } catch (e) {
      _showSnack('플랜 생성 실패: $e', isError: true);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  // 주간 플랜의 특정 날 조합을 그 날짜의 착장으로 확정 저장(source: agent).
  Future<void> _confirmPlanDay(WeeklyPlanDay day) async {
    final uid = _uid;
    if (uid == null) return;
    final entry = OutfitCalendarEntry(
      id: '',
      date: day.date,
      tpoTag: day.tpoTag,
      itemIds: day.items.map((i) => i.id).toList(),
      itemSummaries:
          day.items.map((i) => '${i.category}: ${i.attributes?.color ?? ''}'.trim()).toList(),
      source: OutfitCalendarEntry.sourceAgent,
      createdAt: DateTime.now(),
    );
    try {
      await FirestoreService.addCalendarEntry(uid, entry);
      unawaited(FirestoreService.addAgentLogSilently(
        uid,
        AgentLogEntry(
          id: '',
          eventType: AgentLogEntry.typeCalendarLogged,
          message: '${day.date.month}/${day.date.day} [${day.tpoTag}] 주간 플랜 코디를 캘린더에 확정했습니다',
        ),
      ));
      // 레벨 3: 확정도 "그날의 실제 선택"이므로 추천과 대조해 피드백을 감지한다.
      unawaited(AgentPlanner.detectFeedbackForCalendarEntry(uid, entry));
      _showSnack('${day.date.month}/${day.date.day} 코디를 캘린더에 저장했어요');
    } catch (e) {
      _showSnack('저장 실패: $e', isError: true);
    }
  }

  // ── 미래 날짜: 일정(TPO) 태그만 먼저 등록 ────────────────
  Future<void> _registerScheduleTag() async {
    final uid = _uid;
    if (uid == null) return;
    final tpo = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _TpoPickerSheet(date: _selectedDay),
    );
    if (tpo == null) return;
    final entry = OutfitCalendarEntry(
      id: '',
      date: _selectedDay,
      tpoTag: tpo,
      status: OutfitCalendarEntry.statusPlanned,
      createdAt: DateTime.now(),
    );
    try {
      await FirestoreService.addCalendarEntry(uid, entry);
      _showSnack('${_selectedDay.month}/${_selectedDay.day} [$tpo] 일정을 등록했어요 — 에이전트가 코디를 준비합니다');
    } catch (e) {
      _showSnack('일정 등록 실패: $e', isError: true);
    }
  }

  Future<void> _confirmDelete(OutfitCalendarEntry entry) async {
    final uid = _uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('기록 삭제',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text('이 착장 기록을 삭제하시겠습니까?',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirestoreService.deleteCalendarEntry(uid, entry.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('삭제 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Center(
          child: Text('로그인이 필요합니다', style: TextStyle(color: AppColors.textMuted)));
    }
    return StreamBuilder<List<OutfitCalendarEntry>>(
      stream: FirestoreService.calendarEntriesForMonth(
          uid, _focusedDay.year, _focusedDay.month),
      builder: (context, snapshot) {
        final monthEntries = snapshot.data ?? const <OutfitCalendarEntry>[];
        final dayEntries = _entriesForDay(monthEntries, _selectedDay);
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('착장 캘린더',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            _buildWeeklyPlanButton(),
            _buildCalendar(monthEntries),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: dayEntries.isEmpty
                  ? _buildEmptyDay()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        _dayHeader(),
                        const SizedBox(height: 12),
                        ...dayEntries.map(_entryCard),
                        const SizedBox(height: 12),
                        // 미래 날짜엔 일정 태그를 더 등록, 오늘/과거엔 착장 기록.
                        _isFuture(_selectedDay)
                            ? _scheduleButton(compact: true)
                            : _addButton(compact: true),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeeklyPlanButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton.icon(
          onPressed: _planning ? null : _runWeeklyPlan,
          icon: _planning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
          label: Text(_planning ? '플랜 짜는 중...' : '이번 주 코디 플랜 받기',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navy,
            disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.6),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar(List<OutfitCalendarEntry> monthEntries) {
    return TableCalendar<OutfitCalendarEntry>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: _focusedDay,
      currentDay: DateTime.now(),
      locale: 'ko_KR',
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableGestures: AvailableGestures.horizontalSwipe,
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(
            color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        todayTextStyle: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700),
        selectedDecoration: const BoxDecoration(
          color: AppColors.blue,
          shape: BoxShape.circle,
        ),
        markerDecoration: const BoxDecoration(
          color: AppColors.teal,
          shape: BoxShape.circle,
        ),
        markersMaxCount: 1,
        outsideDaysVisible: false,
      ),
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      eventLoader: (day) => _entriesForDay(monthEntries, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = OutfitCalendarEntry.normalizeDate(selectedDay);
          _focusedDay = focusedDay;
        });
      },
      onPageChanged: (focusedDay) {
        // 월 이동 → 해당 월 스트림으로 재구독.
        setState(() => _focusedDay = focusedDay);
      },
    );
  }

  Widget _dayHeader() {
    return Text(
      '${_selectedDay.month}월 ${_selectedDay.day}일 기록',
      style: const TextStyle(
          color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildEmptyDay() {
    final future = _isFuture(_selectedDay);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(future ? Icons.event_outlined : Icons.checkroom_outlined,
                      color: AppColors.textDisabled, size: 40),
                  const SizedBox(height: 12),
                  Text(
                      future
                          ? '${_selectedDay.month}월 ${_selectedDay.day}일 일정을 등록해보세요'
                          : '${_selectedDay.month}월 ${_selectedDay.day}일 기록이 없어요',
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                      future
                          ? 'TPO 태그를 남기면 에이전트가 코디를 미리 준비해요'
                          : '오늘 입은 착장을 기록해보세요',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 16),
                  // 미래 날짜엔 "일정 태그 등록"을, 오늘/과거엔 "착장 기록하기"를 제공.
                  future ? _scheduleButton(compact: false) : _addButton(compact: false),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _addButton({required bool compact}) {
    return SizedBox(
      width: compact ? double.infinity : 220,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _openRecordSheet,
        icon: const Icon(Icons.add, size: 18, color: AppColors.blue),
        label: const Text('착장 기록하기',
            style: TextStyle(color: AppColors.blue, fontSize: 14, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.blue),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _scheduleButton({required bool compact}) {
    return SizedBox(
      width: compact ? double.infinity : 220,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _registerScheduleTag,
        icon: const Icon(Icons.event_available, size: 18, color: AppColors.navy),
        label: const Text('일정 태그 등록',
            style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.navy),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _entryCard(OutfitCalendarEntry entry) {
    final tag = TpoTags.byLabel(entry.tpoTag);
    // 예정(태그만 등록된 미래 일정)은 착장 기록과 다르게 표시한다.
    final planned = entry.isPlanned;
    final summary = planned
        ? '에이전트가 코디를 준비할 예정이에요'
        : (entry.itemSummaries.isEmpty
            ? '코디 조합'
            : entry.itemSummaries.map((s) => s.split(':').first.trim()).join(', '));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60,
              height: 76,
              child: entry.fittingImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: entry.fittingImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.background),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.background,
                        child: const Icon(Icons.image_outlined, color: AppColors.textDisabled),
                      ),
                    )
                  : Container(
                      color: AppColors.background,
                      child: Icon(planned ? Icons.event_note : Icons.checkroom,
                          color: AppColors.textDisabled),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tag.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tag.icon, size: 13, color: tag.color),
                      const SizedBox(width: 4),
                      Text(tag.label,
                          style: TextStyle(
                              color: tag.color, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                if (planned) ...[
                  const SizedBox(height: 4),
                  const Text('예정 일정',
                      style: TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w600)),
                ] else if (entry.source == OutfitCalendarEntry.sourceAgent) ...[
                  const SizedBox(height: 4),
                  const Text('에이전트 추천에서 기록',
                      style: TextStyle(color: AppColors.blue, fontSize: 11)),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _confirmDelete(entry),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.delete_outline, color: AppColors.textDisabled, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// 미래 날짜에 TPO 태그만 먼저 등록할 때 뜨는 태그 선택 시트.
// 선택된 태그 라벨을 pop으로 반환한다(취소 시 null).
class _TpoPickerSheet extends StatelessWidget {
  final DateTime date;

  const _TpoPickerSheet({required this.date});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${date.month}월 ${date.day}일 일정 태그',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('이 날의 상황(TPO)을 골라주세요',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TpoTags.all.map((tag) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context, tag.label),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: tag.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: tag.color.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tag.icon, size: 16, color: tag.color),
                        const SizedBox(width: 6),
                        Text(tag.label,
                            style: TextStyle(
                                color: tag.color, fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
