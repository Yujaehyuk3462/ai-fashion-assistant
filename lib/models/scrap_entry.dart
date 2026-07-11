import 'package:cloud_firestore/cloud_firestore.dart';

// users/{uid}/scraps 컬렉션 문서 — 사용자가 피팅룸에서 직접 북마크한 가상
// 피팅 결과 1건. 해제(delete) 시 대상 문서를 지정해야 해서 RecommendationEntry와
// 동일하게 doc.id를 들고 있는 WardrobeItem 패턴을 따른다.
class ScrapEntry {
  final String id;
  final String fittingImageUrl;
  final List<String> itemIds;
  final List<String> itemSummaries; // "카테고리: 속성" 한 줄 요약, RecommendationEntry와 동일 패턴
  final DateTime createdAt;

  const ScrapEntry({
    required this.id,
    required this.fittingImageUrl,
    required this.itemIds,
    required this.itemSummaries,
    required this.createdAt,
  });

  factory ScrapEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScrapEntry(
      id: doc.id,
      fittingImageUrl: data['fittingImageUrl'] as String? ?? '',
      itemIds: (data['itemIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      itemSummaries:
          (data['itemSummaries'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // id는 Firestore가 add() 시점에 자동 부여하므로 쓰기에는 포함하지 않는다.
  Map<String, dynamic> toFirestore() => {
        'fittingImageUrl': fittingImageUrl,
        'itemIds': itemIds,
        'itemSummaries': itemSummaries,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
