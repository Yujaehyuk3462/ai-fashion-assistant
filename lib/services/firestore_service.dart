import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/clothing_attributes.dart';
import '../models/clothing_size.dart';
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
    await _db.collection(_usersCol).doc(uid).set(profile.toFirestore());
  }

  // 분석 시점의 프로필 조회는 어디까지나 속도 최적화(사진 대체)를 위한
  // 것이므로, 실패해도 조용히 null을 반환해 기존 사진 기반 분석으로
  // 자연스럽게 폴백되게 한다 (fitting_cache 조회와 동일한 패턴).
  static Future<UserProfile?> getUserProfileSilently(String uid) async {
    try {
      return await getUserProfile(uid);
    } catch (_) {
      return null;
    }
  }
}
