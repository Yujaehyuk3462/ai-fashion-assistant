import 'package:cloud_firestore/cloud_firestore.dart';
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

  static Future<void> addWardrobeItem({
    required String imageUrl,
    required String category,
  }) async {
    await _db.collection(_wardrobeCol).add({
      'imageUrl': imageUrl,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteWardrobeItem(String id) async {
    await _db.collection(_wardrobeCol).doc(id).delete();
  }
}
