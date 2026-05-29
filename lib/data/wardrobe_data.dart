import 'package:cloud_firestore/cloud_firestore.dart';

class WardrobeItem {
  final String id;
  final String name;
  final String brand;
  final String category;
  final String color;
  final String img;
  final DateTime? createdAt;

  const WardrobeItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.color,
    required this.img,
    this.createdAt,
  });

  factory WardrobeItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WardrobeItem(
      id: doc.id,
      name: data['name'] ?? '',
      brand: data['brand'] ?? '',
      category: data['category'] ?? '상의',
      color: data['color'] ?? '',
      img: data['img'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'brand': brand,
      'category': category,
      'color': color,
      'img': img,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }
}

const categories = ['전체', '상의', '하의', '아우터'];
