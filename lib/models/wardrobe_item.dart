import 'package:cloud_firestore/cloud_firestore.dart';
import 'clothing_attributes.dart';
import 'clothing_size.dart';

class WardrobeItem {
  final String id;
  final String imageUrl;
  final String category;
  final DateTime createdAt;
  final ClothingAttributes? attributes; // null = 아직 속성 추출 전(레거시 포함)
  final ClothingSize? size; // null = 치수 미입력

  const WardrobeItem({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.createdAt,
    this.attributes,
    this.size,
  });

  factory WardrobeItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final attributesMap = data['attributes'] as Map<String, dynamic>?;
    final sizeMap = data['size'] as Map<String, dynamic>?;
    return WardrobeItem(
      id: doc.id,
      imageUrl: data['imageUrl'] as String? ?? '',
      category: data['category'] as String? ?? '상의',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      attributes:
          attributesMap != null ? ClothingAttributes.fromJson(attributesMap) : null,
      size: sizeMap != null ? ClothingSize.fromJson(sizeMap) : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'imageUrl': imageUrl,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
        if (attributes != null) 'attributes': attributes!.toFirestore(),
        if (size != null) 'size': size!.toFirestore(),
      };
}
