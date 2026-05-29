import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../data/wardrobe_data.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String _activeCategory = '전체';
  bool _showFabMenu = false;
  final ImagePicker _picker = ImagePicker();

  // Firestore에서 옷 정보를 실시간으로 가져오는 스트림
  Stream<List<WardrobeItem>> get _wardrobeStream {
    var query = FirebaseFirestore.instance.collection('wardrobe').orderBy('createdAt', descending: true);
    if (_activeCategory != '전체') {
      query = query.where('category', isEqualTo: _activeCategory);
    }
    return query.snapshots().map((snapshot) => 
      snapshot.docs.map((doc) => WardrobeItem.fromFirestore(doc)).toList()
    );
  }

  // 이미지 선택 및 업로드 로직
  Future<void> _pickAndUploadImage(ImageSource source) async {
    setState(() => _showFabMenu = false);

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70, // 용량 최적화
      );

      if (pickedFile == null) return;

      // 로딩 표시
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('업로드 중...'), duration: Duration(seconds: 2)),
      );

      File file = File(pickedFile.path);
      String fileName = 'wardrobe/${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // 1. Firebase Storage에 업로드
      UploadTask uploadTask = FirebaseStorage.instance.ref().child(fileName).putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // 2. Firestore에 메타데이터 저장
      await FirebaseFirestore.instance.collection('wardrobe').add({
        'name': '새 아이템', // 실제로는 다이얼로그로 이름을 입력받을 수 있습니다
        'brand': '미지정',
        'category': _activeCategory == '전체' ? '상의' : _activeCategory,
        'color': '기본',
        'img': downloadUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('옷장에 성공적으로 등록되었습니다!')),
      );
    } catch (e) {
      debugPrint('Upload Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<WardrobeItem>>(
                stream: _wardrobeStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  final items = snapshot.data ?? [];
                  
                  if (items.isEmpty) {
                    return GridView.count(
                      padding: const EdgeInsets.all(16),
                      crossAxisCount: 1,
                      children: [_buildEmptyState()],
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _WardrobeCard(item: items[i]),
                  );
                },
              ),
            ),
          ],
        ),
        if (_showFabMenu) _buildFabOverlay(),
        _buildFab(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '내 옷장',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              StreamBuilder<List<WardrobeItem>>(
                stream: _wardrobeStream,
                builder: (context, snapshot) {
                  int count = snapshot.data?.length ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.bluePale, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '$count벌',
                      style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  );
                }
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isActive = _activeCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _activeCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.navy : AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: isActive ? Colors.white : AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.border, shape: BoxShape.circle),
            child: const Icon(Icons.image_outlined, color: AppColors.textPlaceholder, size: 28),
          ),
          const SizedBox(height: 12),
          const Text('아직 등록된 옷이 없어요', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFabOverlay() {
    return GestureDetector(
      onTap: () => setState(() => _showFabMenu = false),
      child: Container(
        color: AppColors.navy.withAlpha(128),
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 88),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _FabMenuItem(
                  icon: Icons.camera_alt, 
                  label: '현재 착장 업로드', // 카메라 촬영
                  color: AppColors.blue, 
                  onTap: () => _pickAndUploadImage(ImageSource.camera),
                ),
                const SizedBox(height: 12),
                _FabMenuItem(
                  icon: Icons.upload, 
                  label: '과거 착장 업로드', // 갤러리 선택
                  color: AppColors.purple, 
                  onTap: () => _pickAndUploadImage(ImageSource.gallery),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Positioned(
      bottom: 20,
      right: 20,
      child: GestureDetector(
        onTap: () => setState(() => _showFabMenu = !_showFabMenu),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: _showFabMenu ? null : const LinearGradient(colors: [Color(0xFF1D4ED8), AppColors.blue]),
            color: _showFabMenu ? AppColors.navy : null,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.blue.withAlpha(115), blurRadius: 20, offset: const Offset(0, 6))],
          ),
          child: Icon(_showFabMenu ? Icons.close : Icons.add, color: Colors.white, size: _showFabMenu ? 24 : 28),
        ),
      ),
    );
  }
}

class _FabMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FabMenuItem({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(38), blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }
}

class _WardrobeCard extends StatelessWidget {
  final WardrobeItem item;

  const _WardrobeCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.navy.withAlpha(20), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: CachedNetworkImage(
                    imageUrl: item.img,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.background),
                    errorWidget: (_, __, ___) => const Icon(Icons.error_outline),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withAlpha(191),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(item.category, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(item.brand, style: const TextStyle(color: AppColors.textPlaceholder, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20)),
                      child: Text(item.color, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
