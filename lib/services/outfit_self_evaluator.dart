import 'package:flutter/foundation.dart';
import 'gemini_service.dart';
import 'outfit_matcher.dart';

// 자기 평가 루프의 결과 한 건 — 채택된 조합과 그 근거(점수/평가 서사).
class SelfEvalOutcome {
  final OutfitMatch bestMatch;
  final String bestText; // [점수] 줄 포함 원문
  final String summaryText; // [점수] 줄 제거한 본문
  final int? bestScore;
  final int evaluatedCount; // 실제로 Gemini 평가에 성공한 후보 수
  final List<int> candidateScores; // 평가 순서대로(탈락 포함, 파싱 실패는 0)

  const SelfEvalOutcome({
    required this.bestMatch,
    required this.bestText,
    required this.summaryText,
    required this.bestScore,
    required this.evaluatedCount,
    required this.candidateScores,
  });
}

// 한 후보를 평가한 직후 호출부에 알려주는 콜백(agent_logs 기록용).
// score가 null이면 점수 파싱 실패, wasError면 Gemini 호출 자체가 실패해 건너뛴 것.
typedef SelfEvalStep = void Function({
  required int index,
  required int total,
  int? score,
  required bool passed,
  required bool wasError,
});

// 능동 추천(새 옷)과 선제 추천/주간 플랜(TPO)이 공유하는 "자기 평가 루프".
// 후보를 하나씩 Gemini로 평가하고, 기준점 이상이면 즉시 채택(조기 종료),
// 미달이면 다음 후보로, 전부 미달이면 최고점 조합을 채택한다. 호출 실패한
// 후보는 건너뛰고 다음 후보에게 기회를 준다.
class OutfitSelfEvaluator {
  // 채택 기준점. 이 점수 이상이면 남은 후보를 평가하지 않고 바로 채택한다.
  static const threshold = 70;

  static Future<SelfEvalOutcome?> run(
    List<OutfitMatch> candidates, {
    SelfEvalStep? onStep,
    String? recentHistoryText, // 취향/피드백 컨텍스트(RAG) — 있으면 평가 프롬프트에 주입
  }) async {
    OutfitMatch? bestMatch;
    String? bestText;
    int? bestScore;
    var evaluated = 0;
    final candidateScores = <int>[];

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final itemsForAnalysis = candidate.items
          .map((it) => (category: it.category, attributes: it.attributes!))
          .toList();

      debugPrint('[SELF-EVAL] 후보 ${i + 1}/${candidates.length} 평가 중...');
      String analysisText;
      try {
        analysisText = await GeminiService.withTextModelFallback(
          (model) => GeminiService.analyzeOutfitFromAttributes(
            items: itemsForAnalysis,
            recentHistoryText: recentHistoryText,
            model: model,
          ),
        );
      } catch (e) {
        // 일시적 오류일 수 있어 남은 후보에게 기회를 준다(모델 폴백은 이미 시도됨).
        debugPrint('[SELF-EVAL] 후보 ${i + 1}/${candidates.length} Gemini 호출 실패, 다음 후보로: $e');
        onStep?.call(index: i, total: candidates.length, score: null, passed: false, wasError: true);
        continue;
      }
      evaluated++;
      final score = parseScore(analysisText);
      candidateScores.add(score ?? 0);

      if (bestMatch == null || (score ?? -1) > (bestScore ?? -1)) {
        bestMatch = candidate;
        bestText = analysisText;
        bestScore = score;
      }
      final passed = score != null && score >= threshold;
      onStep?.call(
          index: i, total: candidates.length, score: score, passed: passed, wasError: false);
      if (passed) {
        debugPrint('[SELF-EVAL] 후보 ${i + 1}/${candidates.length} → 점수 $score (기준 통과, 채택)');
        break;
      }
      debugPrint('[SELF-EVAL] 후보 ${i + 1}/${candidates.length} → 점수 ${score ?? '(파싱 실패)'} '
          '(기준 미달${i < candidates.length - 1 ? ', 다음 후보로' : ''})');
    }

    if (bestMatch == null || bestText == null) return null;
    debugPrint('[SELF-EVAL] 완료: $evaluated개 평가(점수 ${candidateScores.join(', ')}), '
        '최고 ${bestScore ?? '(점수 없음)'} 채택');
    return SelfEvalOutcome(
      bestMatch: bestMatch,
      bestText: bestText,
      summaryText: stripScoreLine(bestText),
      bestScore: bestScore,
      evaluatedCount: evaluated,
      candidateScores: candidateScores,
    );
  }

  // 분석 텍스트의 "[점수] N" 줄에서 점수를 뽑는다. 없으면 null.
  static int? parseScore(String analysisText) {
    final match = RegExp(r'\[점수\]\s*(\d+)').firstMatch(analysisText);
    if (match == null) return null;
    final score = int.tryParse(match.group(1) ?? '');
    return score?.clamp(1, 100);
  }

  static String stripScoreLine(String analysisText) {
    return analysisText.replaceFirst(RegExp(r'\[점수\]\s*\d+\n?'), '').trim();
  }
}
