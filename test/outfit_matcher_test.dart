// OutfitMatcher.findCandidateMatches의 순수 로직 단위 테스트.
// Firebase/네트워크 없이 결정적으로 검증되는 부분(자기 평가 루프의 재료인
// 후보 조합 생성)만 다룬다.
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_fashion_assistant/models/clothing_attributes.dart';
import 'package:ai_fashion_assistant/models/wardrobe_item.dart';
import 'package:ai_fashion_assistant/services/outfit_matcher.dart';

ClothingAttributes _attrs(String color, String formality) => ClothingAttributes(
      color: color,
      style: '기본',
      pattern: '무지',
      formality: formality,
      fit: '레귤러',
      tags: const [],
    );

WardrobeItem _item(String id, String category, String color, String formality) =>
    WardrobeItem(
      id: id,
      imageUrl: 'https://example.com/$id.png',
      category: category,
      createdAt: DateTime(2026, 1, 1),
      attributes: _attrs(color, formality),
    );

// 조합 안에 같은 카테고리가 두 벌 들어가지 않는다는 불변식.
Set<String> _categories(OutfitMatch m) => m.items.map((i) => i.category).toSet();

void main() {
  // 새 옷: 화이트(뉴트럴) 상의, 캐주얼.
  final newItem = _item('new-top', '상의', '화이트', '캐주얼');

  // 하의는 최고점(A)/차순위(B)가 갈리도록, 아우터·신발은 각 1벌씩.
  final bottomA = _item('bottom-a', '하의', '네이비', '캐주얼'); // 격식차0(+2)+뉴트럴(+2)=4
  final bottomB = _item('bottom-b', '하의', '블랙', '세미포멀'); // 격식차1(+1)+뉴트럴(+2)=3
  final outerA = _item('outer-a', '아우터', '베이지', '캐주얼'); // 4
  final shoesA = _item('shoes-a', '신발', '그레이', '캐주얼'); // 4
  final existing = [bottomA, bottomB, outerA, shoesA];

  group('findCandidateMatches', () {
    test('서로 다른 후보를 최대 3개까지 생성한다', () {
      final candidates = OutfitMatcher.findCandidateMatches(
        newItem: newItem,
        existingItems: existing,
      );
      expect(candidates.length, 3);

      // 후보들은 아이템 구성이 서로 달라야 한다(중복 제거).
      final signatures = candidates
          .map((c) => (c.items.map((i) => i.id).toList()..sort()).join(','))
          .toSet();
      expect(signatures.length, candidates.length);

      // 모든 후보는 새 옷을 포함하고, 카테고리가 겹치지 않는다.
      for (final c in candidates) {
        expect(c.items.any((i) => i.id == newItem.id), isTrue);
        expect(_categories(c).length, c.items.length);
      }
    });

    test('1번 후보는 카테고리별 최고점 풀 조합(localScore 최대)이다', () {
      final candidates = OutfitMatcher.findCandidateMatches(
        newItem: newItem,
        existingItems: existing,
      );
      final first = candidates.first;
      // 새 옷 + 하의A + 아우터A + 신발A = 4벌, localScore 4+4+4=12.
      expect(first.items.length, 4);
      expect(first.localScore, 12);
      expect(first.items.map((i) => i.id), containsAll(['bottom-a', 'outer-a', 'shoes-a']));
      // 차순위 하의B는 1번 조합에 들어가지 않는다.
      expect(first.items.map((i) => i.id), isNot(contains('bottom-b')));
    });

    test('변형 후보에는 차순위 교체 조합이 포함된다', () {
      final candidates = OutfitMatcher.findCandidateMatches(
        newItem: newItem,
        existingItems: existing,
      );
      // 하의를 차순위(B)로 바꾼 조합이 후보 어딘가에 있어야 한다.
      final hasSwap = candidates.any((c) => c.items.any((i) => i.id == 'bottom-b'));
      expect(hasSwap, isTrue);
    });

    test('findBestMatch는 1번 후보와 동일하다', () {
      final best = OutfitMatcher.findBestMatch(newItem: newItem, existingItems: existing);
      final candidates = OutfitMatcher.findCandidateMatches(
        newItem: newItem,
        existingItems: existing,
      );
      expect(best, isNotNull);
      expect(best!.localScore, candidates.first.localScore);
      expect(
        (best.items.map((i) => i.id).toList()..sort()),
        (candidates.first.items.map((i) => i.id).toList()..sort()),
      );
    });

    test('maxCandidates 상한을 지킨다', () {
      final candidates = OutfitMatcher.findCandidateMatches(
        newItem: newItem,
        existingItems: existing,
        maxCandidates: 1,
      );
      expect(candidates.length, 1);
    });

    test('새 옷에 attributes가 없으면 빈 리스트', () {
      final noAttrs = WardrobeItem(
        id: 'x',
        imageUrl: '',
        category: '상의',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(
        OutfitMatcher.findCandidateMatches(newItem: noAttrs, existingItems: existing),
        isEmpty,
      );
    });

    test('매칭 대상이 아닌 카테고리(액세서리)면 빈 리스트', () {
      final accessory = _item('acc', '액세서리', '블랙', '캐주얼');
      expect(
        OutfitMatcher.findCandidateMatches(newItem: accessory, existingItems: existing),
        isEmpty,
      );
    });

    test('궁합 후보가 없으면 빈 리스트', () {
      expect(
        OutfitMatcher.findCandidateMatches(newItem: newItem, existingItems: const []),
        isEmpty,
      );
    });
  });
}
