import 'package:cloud_firestore/cloud_firestore.dart';

class WardrobeItem {
  final String id;
  final String imageUrl;
  final String category;
  final DateTime createdAt;

  const WardrobeItem({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.createdAt,
  });

  factory WardrobeItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WardrobeItem(
      id: doc.id,
      imageUrl: data['imageUrl'] as String? ?? '',
      category: data['category'] as String? ?? '상의',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'imageUrl': imageUrl,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
