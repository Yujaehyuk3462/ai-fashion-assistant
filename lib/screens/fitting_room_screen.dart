import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_colors.dart';
import '../data/wardrobe_data.dart';
import '../services/gemini_service.dart';

class FittingRoomScreen extends StatefulWidget {
  final VoidCallback onNavigateToDetail;

  const FittingRoomScreen({super.key, required this.onNavigateToDetail});

  @override
  State<FittingRoomScreen> createState() => _FittingRoomScreenState();
}

class _FittingRoomScreenState extends State<FittingRoomScreen> {
  // Step 1 : 내 사진
  XFile? _userPhoto;
  Uint8List? _userPhotoBytes;

  // Step 2 : 옷 선택
  String _activeCategory = '상의';
  final Map<String, WardrobeItem?> _selected = {
    '상의': null,
    '하의': null,
    '아우터': null,
  };

  // 생성 상태
  bool _isGenerating = false;
  Uint8List? _resultBytes;
  String? _error;

  bool get _canGenerate =>
      _userPhoto != null && _selected.values.any((v) => v != null);

  Stream<List<WardrobeItem>> get _wardrobeStream =>
      FirebaseFirestore.instance
          .collection('wardrobe')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(WardrobeItem.fromFirestore).toList());

  // ── 사진 선택 ──────────────────────────────────────────
  Future<void> _pickUserPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.blue),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.blue),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _userPhoto = picked;
        _userPhotoBytes = bytes;
        _resultBytes = null;
        _error = null;
      });
    }
  }

  // ── 옷 선택/해제 ────────────────────────────────────────
  void _toggleItem(WardrobeItem item) {
    setState(() {
      _selected[item.category] =
          _selected[item.category]?.id == item.id ? null : item;
      _resultBytes = null;
      _error = null;
    });
  }

  // ── Gemini 피팅 생성 ────────────────────────────────────
  Future<void> _generate() async {
    if (!_canGenerate) return;
    setState(() {
      _isGenerating = true;
      _error = null;
      _resultBytes = null;
    });

    try {
      final selectedItems =
          _selected.values.whereType<WardrobeItem>().toList();
      final resultBytes = await GeminiService.generateFittingImage(
        userPhoto: _userPhoto!,
        clothingImageUrls: selectedItems.map((i) => i.img).toList(),
        clothingNames:
            selectedItems.map((i) => '${i.category} - ${i.name}').toList(),
      );
      if (mounted) setState(() => _resultBytes = resultBytes);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── Build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: StreamBuilder<List<WardrobeItem>>(
            stream: _wardrobeStream,
            builder: (context, snapshot) {
              final allItems = snapshot.data ?? [];
              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildStep1Card(),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildStep2Card(allItems),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildGenerateButton(),
                    ),
                    if (_isGenerating ||
                        _resultBytes != null ||
                        _error != null) ...[
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildResultSection(),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.blue, size: 20),
              const SizedBox(width: 8),
              const Text('AI 피팅룸',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.bluePale,
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('BETA',
                    style: TextStyle(
                        color: AppColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '내 사진과 옷을 선택하면 AI가 입어보는 모습을 보여줘요',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Step 1: 내 사진 ─────────────────────────────────────
  Widget _buildStep1Card() {
    return _StepCard(
      step: '1',
      title: '내 착장 사진 선택',
      subtitle: '현재 착장이나 전신 사진을 선택해주세요',
      child: _userPhotoBytes == null
          ? _buildPhotoUploadArea()
          : _buildPhotoPreview(),
    );
  }

  Widget _buildPhotoUploadArea() {
    return GestureDetector(
      onTap: _pickUserPhoto,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.textDisabled, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: AppColors.bluePale,
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.add_a_photo,
                  color: AppColors.blue, size: 26),
            ),
            const SizedBox(height: 12),
            const Text('사진 선택하기',
                style: TextStyle(
                    color: AppColors.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('촬영 또는 갤러리에서 선택',
                style: TextStyle(
                    color: AppColors.textPlaceholder, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: Image.memory(_userPhotoBytes!, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: _pickUserPhoto,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('재선택',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 2: 옷 선택 ─────────────────────────────────────
  Widget _buildStep2Card(List<WardrobeItem> allItems) {
    final selectedCount = _selected.values.where((v) => v != null).length;
    return _StepCard(
      step: '2',
      title: '입어볼 옷 선택',
      subtitle: '옷장에서 입어보고 싶은 옷을 선택해주세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카테고리 탭
          Row(
            children: ['상의', '하의', '아우터'].map((cat) {
              final isActive = _activeCategory == cat;
              final hasSelected = _selected[cat] != null;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _activeCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.navy : AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          cat,
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (hasSelected) ...[
                          const SizedBox(width: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.white
                                  : AppColors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 옷 목록
          _buildClothingList(
            allItems
                .where((i) => i.category == _activeCategory)
                .toList(),
          ),

          // 선택된 아이템 요약
          if (selectedCount > 0) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildSelectedSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildClothingList(List<WardrobeItem> items) {
    if (items.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.checkroom_outlined,
                color: AppColors.textDisabled, size: 28),
            const SizedBox(height: 8),
            Text(
              '$_activeCategory 아이템이 없어요\n옷장 탭에서 먼저 추가해주세요',
              style: const TextStyle(
                  color: AppColors.textPlaceholder, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final isSelected = _selected[item.category]?.id == item.id;
          return GestureDetector(
            onTap: () => _toggleItem(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 90,
              margin: EdgeInsets.only(right: 10, left: i == 0 ? 0 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? AppColors.blue : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.expand(
                      child: CachedNetworkImage(
                        imageUrl: item.img,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.background),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.background,
                          child: const Icon(Icons.image_not_supported,
                              color: AppColors.textDisabled),
                        ),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                            color: AppColors.blue, shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            color: Colors.white, size: 13),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                      ),
                      child: Text(
                        item.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedSummary() {
    final entries = _selected.entries
        .where((e) => e.value != null)
        .map((e) => e.value!)
        .toList();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: entries.map((item) {
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.bluePale,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${item.category} · ${item.name}',
                style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() {
                  _selected[item.category] = null;
                  _resultBytes = null;
                }),
                child: const Icon(Icons.close,
                    color: AppColors.blue, size: 14),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── 생성 버튼 ───────────────────────────────────────────
  Widget _buildGenerateButton() {
    final enabled = _canGenerate && !_isGenerating;
    return GestureDetector(
      onTap: enabled ? _generate : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF1D4ED8), AppColors.blue])
              : null,
          color: enabled ? null : AppColors.textDisabled,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: AppColors.blue.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6))
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              _isGenerating
                  ? 'AI 피팅 이미지 생성 중...'
                  : !_canGenerate
                      ? '사진과 옷을 먼저 선택해주세요'
                      : 'AI 피팅 해보기',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // ── 결과 섹션 ───────────────────────────────────────────
  Widget _buildResultSection() {
    if (_isGenerating) return _buildLoadingCard();
    if (_error != null) return _buildErrorCard();
    if (_resultBytes != null) return _buildResultCard();
    return const SizedBox.shrink();
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: AppColors.bluePale,
                borderRadius: BorderRadius.circular(20)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                  color: AppColors.blue, strokeWidth: 3),
            ),
          ),
          const SizedBox(height: 16),
          const Text('AI가 피팅 이미지를 생성하고 있어요',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('보통 10~30초 정도 소요됩니다',
              style:
                  TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
          const SizedBox(height: 12),
          const Text('피팅 이미지 생성 실패',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            _error ?? '알 수 없는 오류가 발생했습니다.',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _generate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bluePale,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('다시 시도',
                  style: TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI 피팅 결과',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: Image.memory(
                  _resultBytes!,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            color: AppColors.blue, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _selected.entries
                                .where((e) => e.value != null)
                                .map((e) =>
                                    '${e.key} · ${e.value!.name}')
                                .join('  /  '),
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _resultBytes = null;
                                _error = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.refresh,
                                      color: AppColors.textMuted,
                                      size: 16),
                                  SizedBox(width: 6),
                                  Text('다시 피팅',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: widget.onNavigateToDetail,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [
                                      AppColors.navy,
                                      AppColors.navyLight
                                    ]),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shopping_cart_outlined,
                                      color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text('구매하기',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 공통 카드 ────────────────────────────────────────────
class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                    color: AppColors.blue, shape: BoxShape.circle),
                child: Center(
                  child: Text(step,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textPlaceholder, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}