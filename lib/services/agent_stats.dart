import '../models/recommendation_entry.dart';
import 'firestore_service.dart';

// 특정 태그(또는 '일반')의 채택률 — accepted / (accepted + rejected).
class TagAcceptance {
  final String tag;
  final int accepted;
  final int total; // accepted + rejected_with_alternative

  const TagAcceptance({required this.tag, required this.accepted, required this.total});

  double get rate => total == 0 ? 0 : accepted / total;
}

// 최근 30일 추천 피드백을 집계해 "에이전트가 실제로 학습하고 있는지"를
// 숫자로 보여준다. accepted/rejected_with_alternative로 반응이 기록된
// 것만 셈에 넣는다(아직 반응 없는 추천은 판단 대상이 아니므로 제외).
class AgentStats {
  final int overallAccepted;
  final int overallTotal;
  final List<TagAcceptance> byTag; // 표본 많은 순

  const AgentStats({
    required this.overallAccepted,
    required this.overallTotal,
    required this.byTag,
  });

  double? get overallRate => overallTotal == 0 ? null : overallAccepted / overallTotal;

  // targetTpoTag(선제 추천 카드 문구용) 기준 조회. 없으면 null.
  TagAcceptance? forTag(String? tag) {
    final key = tag ?? '일반';
    for (final t in byTag) {
      if (t.tag == key) return t;
    }
    return null;
  }

  static const _window = Duration(days: 30);

  static Future<AgentStats> compute(String uid) async {
    final since = DateTime.now().subtract(_window);
    final entries = await FirestoreService.recommendationsSinceSilently(uid, since);

    var accepted = 0;
    var total = 0;
    final tagAccepted = <String, int>{};
    final tagTotal = <String, int>{};

    for (final e in entries) {
      final isAccepted = e.userChoice == RecommendationEntry.choiceAccepted;
      final isRejected = e.userChoice == RecommendationEntry.choiceRejectedWithAlternative;
      if (!isAccepted && !isRejected) continue; // 아직 반응 없음 — 집계 제외

      final tag = e.targetTpoTag ?? '일반';
      total++;
      tagTotal[tag] = (tagTotal[tag] ?? 0) + 1;
      if (isAccepted) {
        accepted++;
        tagAccepted[tag] = (tagAccepted[tag] ?? 0) + 1;
      }
    }

    final byTag = tagTotal.keys
        .map((tag) =>
            TagAcceptance(tag: tag, accepted: tagAccepted[tag] ?? 0, total: tagTotal[tag]!))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return AgentStats(overallAccepted: accepted, overallTotal: total, byTag: byTag);
  }
}
