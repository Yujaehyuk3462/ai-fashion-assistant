import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/clothing_attributes.dart';
import '../models/clothing_size.dart';
import '../models/outfit_history_entry.dart';
import '../models/recommendation_entry.dart';
import '../models/scrap_entry.dart';
import '../models/user_profile.dart';
import '../models/wardrobe_item.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;
  static const _wardrobeCol = 'wardrobe';
  static const _fittingCacheCol = 'fitting_cache';
  static const _usersCol = 'users';

  static Stream<List<WardrobeItem>> wardrobeStream() {
    return _db
        .collection(_wardrobeCol)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => WardrobeItem.fromFirestore(doc))
              .toList(),
        );
  }

  static Future<String> addWardrobeItem({
    required String imageUrl,
    String? cutoutImageUrl,
    required String category,
    String? subCategory,
    ClothingSize? size,
  }) async {
    final doc = await _db.collection(_wardrobeCol).add({
      'imageUrl': imageUrl,
      if (cutoutImageUrl != null) 'cutoutImageUrl': cutoutImageUrl,
      'category': category,
      if (subCategory != null) 'subCategory': subCategory,
      'createdAt': FieldValue.serverTimestamp(),
      if (size != null) 'size': size.toFirestore(),
    });
    return doc.id;
  }

  // 등록 직후 백그라운드 추출, 또는 분석 시점 폴백 추출 결과를 문서에 patch.
  static Future<void> updateWardrobeAttributes(
    String id,
    ClothingAttributes attributes,
  ) async {
    await _db.collection(_wardrobeCol).doc(id).update({
      'attributes': attributes.toFirestore(),
    });
  }

  // 이미 등록된 옷에 치수를 나중에 입력하거나 기존 치수를 수정할 때 사용.
  static Future<void> updateWardrobeSize(String id, ClothingSize size) async {
    await _db.collection(_wardrobeCol).doc(id).update({
      'size': size.toFirestore(),
    });
  }

  // TODO: 옷/사용자 사진이 삭제될 때 해당 아이템이 포함된 fitting_cache
  // 문서와 Storage의 결과 이미지를 함께 정리하는 로직 필요 (현재 범위 밖 —
  // 지금은 삭제해도 캐시가 orphan으로 남아 낡은 조합을 계속 가리킬 수 있다).
  static Future<void> deleteWardrobeItem(String id) async {
    await _db.collection(_wardrobeCol).doc(id).delete();
  }

  // ── 가상 피팅 결과 캐시 (doc id = 사용자 사진+옷 조합의 SHA-256 해시) ──
  static Future<String?> getCachedFittingImageUrl(String cacheKey) async {
    final doc = await _db.collection(_fittingCacheCol).doc(cacheKey).get();
    return doc.data()?['imageUrl'] as String?;
  }

  static Future<void> cacheFittingResult(String cacheKey, String imageUrl) async {
    await _db.collection(_fittingCacheCol).doc(cacheKey).set({
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── 사용자 체형/취향 프로필 (doc id = uid, 본인만 접근 가능) ──
  static Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _db.collection(_usersCol).doc(uid).get();
    final data = doc.data();
    if (data == null) return null;
    return UserProfile.fromFirestore(data);
  }

  static Future<void> saveUserProfile(String uid, UserProfile profile) async {
    await _db.collection(_usersCol).doc(uid).set( profile.toFirestore());
  }

  // 분석 시점의 프로필 조회는 어디까지나 속도 최적화(사진 대체)를 위한
  // 것이므로, 실패해도 조용히 null을 반환해 기존 사진 기반 분석으로
  // 자연스럽게 폴백되게 한다 (fitting_cache 조회와 동일한 패턴).
  static Future<UserProfile?> getUserProfileSilently(String uid) async {
    try {
      return await getUserProfile(uid);
    } catch (e) {
      debugPrint('[프로필조회] 실패: $e');
      return null;
    }
  }

  // ── 코디 사용 이력 (개인화 추천용 축적 데이터, 본인만 접근 가능) ──
  static const _historyCol = 'history';

  static Future<void> addHistoryEntry(String uid, OutfitHistoryEntry entry) async {
    await _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_historyCol)
        .add(entry.toFirestore());
  }

  // 이력 기록은 분석/피팅/코디보드 같은 핵심 기능의 부가 작업일 뿐이므로,
  // 실패해도 조용히 무시한다 (getUserProfileSilently와 동일한 패턴).
  static Future<void> addHistoryEntrySilently(String uid, OutfitHistoryEntry entry) async {
    try {
      await addHistoryEntry(uid, entry);
    } catch (e) {
      // 무시 — 사용자가 방금 완료한 분석/피팅/보드 작업 자체는 이미 성공한 상태다.
      debugPrint('[히스토리저장] 실패: $e');
    }
  }

  static Future<List<OutfitHistoryEntry>> getRecentHistorySilently(
    String uid, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _db
          .collection(_usersCol)
          .doc(uid)
          .collection(_historyCol)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((doc) => OutfitHistoryEntry.fromFirestore(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('[히스토리조회] 실패: $e');
      return [];
    }
  }

  // ── 능동 추천 (새 옷 등록을 계기로 백그라운드 생성, 본인만 접근 가능) ──
  static const _recommendationsCol = 'recommendations';

  static Future<String> addRecommendation(String uid, RecommendationEntry entry) async {
    final doc = await _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_recommendationsCol)
        .add(entry.toFirestore());
    return doc.id;
  }

  // 추천 생성은 옷 등록의 부가 기능이므로, 실패해도 조용히 무시한다
  // (addHistoryEntrySilently와 동일한 패턴). 파이프라인이 어디서 끊기는지
  // 진단할 수 있도록 성공/실패를 로그로 남긴다.
  static Future<String?> addRecommendationSilently(String uid, RecommendationEntry entry) async {
    try {
      final docId = await addRecommendation(uid, entry);
      debugPrint('[RECOMMEND] 저장 완료: docId=$docId');
      return docId;
    } catch (e) {
      debugPrint('[RECOMMEND] 저장 실패: $e');
      return null;
    }
  }

  // dismissed == false인 것 중 최신 1건만 — 홈 화면 카드는 항상 최대 1개만 노출한다.
  static Stream<RecommendationEntry?> recommendationStream(String uid) {
    return _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_recommendationsCol)
        .where('dismissed', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.isEmpty ? null : RecommendationEntry.fromFirestore(snapshot.docs.first));
  }

  static Future<void> dismissRecommendation(String uid, String id) async {
    await _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_recommendationsCol)
        .doc(id)
        .update({'dismissed': true});
  }

  // ── 가상 피팅 스크랩 (사용자가 직접 북마크, 본인만 접근 가능) ──
  // 사용자의 명시적 액션이므로 다른 *Silently 메서드들과 달리 실패를
  // 삼키지 않고 그대로 던진다 — 호출부(fitting_room_screen.dart)가
  // 스낵바로 알린다.
  static const _scrapsCol = 'scraps';

  static Future<String> addScrap(String uid, ScrapEntry entry) async {
    final doc = await _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_scrapsCol)
        .add(entry.toFirestore());
    return doc.id;
  }

  static Future<void> deleteScrap(String uid, String scrapId) async {
    await _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_scrapsCol)
        .doc(scrapId)
        .delete();
  }

  // 이름은 "스크랩됐는지 여부"지만, 있으면 그 문서 id를 그대로 반환해
  // 호출부가 곧장 deleteScrap에 넘길 수 있게 한다(null이면 미스크랩).
  // where절 1개만 쓰므로 복합 인덱스가 필요 없다.
  static Future<String?> isScrapped(String uid, String fittingImageUrl) async {
    final snapshot = await _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_scrapsCol)
        .where('fittingImageUrl', isEqualTo: fittingImageUrl)
        .limit(1)
        .get();
    return snapshot.docs.isEmpty ? null : snapshot.docs.first.id;
  }

  static Stream<List<ScrapEntry>> scrapStream(String uid) {
    return _db
        .collection(_usersCol)
        .doc(uid)
        .collection(_scrapsCol)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => ScrapEntry.fromFirestore(doc)).toList());
  }
}
