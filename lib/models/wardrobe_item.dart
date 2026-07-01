import 'package:cloud_firestore/cloud_firestore.dart';
import 'clothing_attributes.dart';

class WardrobeItem {
  final String id;
  final String imageUrl;
  final String category;
  final DateTime createdAt;
  final ClothingAttributes? attributes; // null = 아직 속성 추출 전(레거시 포함)

  const WardrobeItem({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.createdAt,
    this.attributes,
  });

  factory WardrobeItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final attributesMap = data['attributes'] as Map<String, dynamic>?;
    return WardrobeItem(
      id: doc.id,
      imageUrl: data['imageUrl'] as String? ?? '',
      category: data['category'] as String? ?? '상의',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      attributes:
          attributesMap != null ? ClothingAttributes.fromJson(attributesMap) : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'imageUrl': imageUrl,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
        if (attributes != null) 'attributes': attributes!.toFirestore(),
      };
}
