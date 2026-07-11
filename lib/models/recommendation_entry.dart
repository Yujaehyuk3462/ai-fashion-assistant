import 'package:cloud_firestore/cloud_firestore.dart';

// users/{uid}/recommendations 컬렉션 문서 — 새 옷 등록을 계기로 백그라운드에서
// 자동 생성된 "능동 추천" 코디 1건. dismiss 시 대상 문서를 지정해야 해서
// (OutfitHistoryEntry와 달리) doc.id를 들고 있는 WardrobeItem 패턴을 따른다.
class RecommendationEntry {
  final String id;
  final List<String> itemIds;
  final List<String> itemSummaries; // "카테고리: 속성" 한 줄 요약, HistoryEntry와 동일 패턴
  final int? colorScore;
  final String summaryText;
  final String triggerItemId; // 이 추천을 유발한 새 옷의 id
  final DateTime createdAt;
  final bool dismissed;

  const RecommendationEntry({
    required this.id,
    required this.itemIds,
    required this.itemSummaries,
    this.colorScore,
    required this.summaryText,
    required this.triggerItemId,
    required this.createdAt,
    this.dismissed = false,
  });

  factory RecommendationEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RecommendationEntry(
      id: doc.id,
      itemIds: (data['itemIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      itemSummaries:
          (data['itemSummaries'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      colorScore: data['colorScore'] as int?,
      summaryText: data['summaryText'] as String? ?? '',
      triggerItemId: data['triggerItemId'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dismissed: data['dismissed'] as bool? ?? false,
    );
  }

  // id는 Firestore가 add() 시점에 자동 부여하므로 쓰기에는 포함하지 않는다.
  Map<String, dynamic> toFirestore() => {
        'itemIds': itemIds,
        'itemSummaries': itemSummaries,
        if (colorScore != null) 'colorScore': colorScore,
        'summaryText': summaryText,
        'triggerItemId': triggerItemId,
        'createdAt': FieldValue.serverTimestamp(),
        'dismissed': dismissed,
      };
}
