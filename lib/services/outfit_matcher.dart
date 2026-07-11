import 'package:flutter/foundation.dart';
import '../models/clothing_attributes.dart';
import '../models/wardrobe_item.dart';

// 새로 등록된 옷과 기존 옷장만으로 어울리는 조합 1개를 고른다.
// FitPredictor와 동일하게 Gemini 호출 없이 순수 로컬 계산만 수행한다.
class OutfitMatch {
  final List<WardrobeItem> items; // 새 옷 포함

  const OutfitMatch(this.items);
}

class OutfitMatcher {
  // 코디 조합의 뼈대가 되는 카테고리만 매칭 대상으로 삼는다.
  // 액세서리/전신은 의류 조합 판단과 무관해 제외.
  static const _outfitCategories = {'상의', '하의', '아우터', '신발'};

  static const _formalityRank = {'캐주얼': 0, '세미포멀': 1, '포멀': 2};

  // 어떤 색과도 무난히 어울리는 무채색/뉴트럴 톤.
  static const _neutralColors = {
    '화이트', '블랙', '네이비', '그레이', '베이지', '아이보리', '카키', '그레이지',
  };

  // 새 옷(newItem)과 카테고리가 다르고 attributes가 이미 채워진 기존 아이템
  // 중 격식·색상 궁합이 좋은 후보를 카테고리별 1개씩 뽑아 상위 2~3개를
  // 최종 조합으로 채택한다. 매칭 가능한 후보가 없으면 null.
  static OutfitMatch? findBestMatch({
    required WardrobeItem newItem,
    required List<WardrobeItem> existingItems,
  }) {
    final newAttrs = newItem.attributes;
    if (newAttrs == null) {
      debugPrint('[RECOMMEND] 매칭 실패 — 이유: 새 옷에 attributes가 없음');
      return null;
    }
    if (!_outfitCategories.contains(newItem.category)) {
      debugPrint('[RECOMMEND] 매칭 실패 — 이유: 매칭 대상 카테고리가 아님(${newItem.category})');
      return null;
    }

    final pool = existingItems
        .where((i) =>
            i.id != newItem.id &&
            i.category != newItem.category &&
            _outfitCategories.contains(i.category) &&
            i.attributes != null)
        .toList();
    debugPrint('[RECOMMEND] 후보 풀 크기: ${pool.length}개');

    // 같은 카테고리 두 벌이 한 조합에 들어가지 않도록 카테고리별 최고점만 남긴다.
    final bestPerCategory = <String, ({WardrobeItem item, double score})>{};
    for (final candidate in pool) {
      final score = _compatibilityScore(newAttrs, candidate.attributes!);
      final current = bestPerCategory[candidate.category];
      if (current == null || score > current.score) {
        bestPerCategory[candidate.category] = (item: candidate, score: score);
      }
    }

    final ranked = bestPerCategory.values.where((c) => c.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty) {
      final reason = pool.isEmpty
          ? '후보 풀이 비어 있음(카테고리가 다르고 attributes가 채워진 기존 옷이 없음)'
          : '후보는 ${pool.length}개 있었지만 전부 궁합 점수 0점 이하';
      debugPrint('[RECOMMEND] 매칭 실패 — 이유: $reason');
      return null;
    }

    final picked = ranked.take(3).map((c) => c.item).toList();
    debugPrint('[RECOMMEND] 매칭 성공: 선택된 조합 '
        '${[newItem, ...picked].map((i) => '${i.category}(${i.id})').join(', ')}');
    return OutfitMatch([newItem, ...picked]);
  }

  static double _compatibilityScore(ClothingAttributes a, ClothingAttributes b) {
    double score = 0;

    final rankA = _formalityRank[a.formality];
    final rankB = _formalityRank[b.formality];
    if (rankA != null && rankB != null) {
      final diff = (rankA - rankB).abs();
      score += diff == 0 ? 2 : (diff == 1 ? 1 : -1);
    }

    if (_neutralColors.contains(a.color) || _neutralColors.contains(b.color)) {
      score += 2;
    } else if (a.color == b.color && a.color.isNotEmpty) {
      score += 1;
    }

    return score;
  }
}
