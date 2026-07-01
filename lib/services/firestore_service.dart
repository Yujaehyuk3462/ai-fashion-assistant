import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/clothing_attributes.dart';
import '../models/wardrobe_item.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;
  static const _wardrobeCol = 'wardrobe';

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
    required String category,
  }) async {
    final doc = await _db.collection(_wardrobeCol).add({
      'imageUrl': imageUrl,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
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

  static Future<void> deleteWardrobeItem(String id) async {
    await _db.collection(_wardrobeCol).doc(id).delete();
  }
}
