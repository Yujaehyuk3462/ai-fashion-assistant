import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';
import '../models/wardrobe_item.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';

const _mockImages = {
  '아우터': 'https://images.unsplash.com/photo-1617137968427-85924c800a22?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=900&w=600&q=80',
  '캐주얼': 'https://images.unsplash.com/photo-1480455624313-e29b44bbfde1?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=900&w=600&q=80',
  '기본':   'https://images.unsplash.com/photo-1490578474895-699cd4e2cf59?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=900&w=600&q=80',
};

class FittingRoomScreen extends StatefulWidget {
  final Map<String, WardrobeItem?> selectedItems;
  final WardrobeItem? userPhoto;
  final Function(String category, WardrobeItem item) onSetItem;
  final ValueChanged<String> onClearItem;
  final ValueChanged<WardrobeItem> onSetUserPhoto;
  final VoidCallback? onClearUserPhoto;       // 내 사진 초기화 (main.dart 연동 필요)
  final VoidCallback onNavigateToDetail;

  const FittingRoomScreen({
    super.key,
    required this.selectedItems,
    required this.userPhoto,
    required this.onSetItem,
    required this.onClearItem,
    required this.onSetUserPhoto,
    this.onClearUserPhoto,
    required this.onNavigateToDetail,
  });

  @override
  State<FittingRoomScreen> createState() => _FittingRoomScreenState();
}

class _FittingRoomScreenState extends State<FittingRoomScreen> {
  bool _isAnalyzing = false;
  bool _isGeneratingFitting = false;
  String? _analysisResult;
  String? _mockFittingImageUrl;
  Uint8List? _fittingImage;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canAnalyze =>
      widget.selectedItems.values.any((v) => v != null) &&
      !_isAnalyzing &&
      !_isGeneratingFitting;

  bool get _canGenerateFitting =>
      widget.userPhoto != null &&
      widget.selectedItems.values.any((v) => v != null) &&
      !_isAnalyzing &&
      !_isGeneratingFitting;

  String _pickMockImage() {
    final cats = widget.selectedItems.entries
        .where((e) => e.value != null)
        .map((e) => e.key)
        .toList();
    if (cats.contains('아우터')) return _mockImages['아우터']!;
    if (cats.contains('하의') && cats.contains('상의')) return _mockImages['캐주얼']!;
    return _mockImages['기본']!;
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Gemini 텍스트 분석 ───────────────────────────────────
  Future<void> _analyze() async {
    if (!_canAnalyze) return;
    final selectedList = widget.selectedItems.values.whereType<WardrobeItem>().toList();

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _mockFittingImageUrl = null;
      _fittingImage = null;
    });

    try {
      final result = await GeminiService.analyzeOutfit(
        clothingImageUrls: selectedList.map((i) => i.imageUrl).toList(),
        clothingCategories: selectedList.map((i) => i.category).toList(),
        userPhotoUrl: widget.userPhoto?.imageUrl,
      );
      if (mounted) {
        setState(() {
          _analysisResult = result;
          _mockFittingImageUrl = widget.userPhoto?.imageUrl; // 내 사진 없으면 null
        });
        _scrollToResult();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('분석 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // ── Gemini 가상 피팅 이미지 생성 ─────────────────────────
  Future<void> _generateFitting() async {
    if (!_canGenerateFitting) return;
    final selectedList = widget.selectedItems.values.whereType<WardrobeItem>().toList();

    setState(() {
      _isGeneratingFitting = true;
      _fittingImage = null;
    });

    try {
      final result = await GeminiService.generateFittingImage(
        userPhotoUrl: widget.userPhoto!.imageUrl,
        clothingImageUrls: selectedList.map((i) => i.imageUrl).toList(),
        clothingNames: selectedList.map((i) => i.category).toList(),
      );
      if (mounted) {
        setState(() {
          _fittingImage = result;
          _mockFittingImageUrl ??= widget.userPhoto?.imageUrl ?? _pickMockImage();
        });
        _scrollToResult();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('가상 피팅 실패: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingFitting = false);
    }
  }

  void _showPhotoPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WardrobePickerSheet(
        category: '전신',
        title: '전신 사진 선택',
        emptyMessage: '전신 코디 사진이 없습니다.\n옷장 탭에서 "전신" 카테고리로 등록해 주세요.',
        onSelect: (item) {
          Navigator.pop(context);
          widget.onSetUserPhoto(item);
        },
      ),
    );
  }

  void _showClothingPicker(String category) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WardrobePickerSheet(
        category: category,
        title: '$category 선택',
        emptyMessage: '등록된 $category 아이템이 없습니다.\n옷장 탭에서 먼저 추가해 주세요.',
        onSelect: (item) {
          Navigator.pop(context);
          widget.onSetItem(category, item);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepCard(
                      number: '1',
                      title: '내 사진 선택',
                      subtitle: '옷장의 전신 코디 사진을 선택해 주세요',
                      child: _buildPhotoSlot(),
                    ),
                    const SizedBox(height: 16),
                    _buildStepCard(
                      number: '2',
                      title: '코디 선택',
                      subtitle: '슬롯을 탭하면 옷장에서 바로 선택할 수 있습니다',
                      child: _buildClothingSection(),
                    ),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                    const SizedBox(height: 20),
                    (_analysisResult != null || _fittingImage != null)
                        ? _buildResultCard()
                        : _buildResultPlaceholder(),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_isAnalyzing || _isGeneratingFitting)
          _buildAnalyzingOverlay(isFitting: _isGeneratingFitting),
      ],
    );
  }

  // ── 헤더 ────────────────────────────────────────────────
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
              const Icon(Icons.checkroom, color: AppColors.navy, size: 22),
              const SizedBox(width: 8),
              const Text('AI 피팅룸',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.bluePale,
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('BETA',
                    style: TextStyle(
                        color: AppColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('슬롯을 탭해 옷장에서 바로 선택하세요',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  // ── 스텝 카드 래퍼 ──────────────────────────────────────
  Widget _buildStepCard({
    required String number,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                    color: AppColors.navy, shape: BoxShape.circle),
                child: Center(
                  child: Text(number,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textPlaceholder, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ── Step 1: 전신 사진 슬롯 ──────────────────────────────
  Widget _buildPhotoSlot() {
    final photo = widget.userPhoto;
    return GestureDetector(
      onTap: _showPhotoPicker,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: photo != null
                ? AppColors.navy.withValues(alpha: 0.35)
                : AppColors.border,
            width: photo != null ? 2.0 : 1.5,
          ),
        ),
        child: photo != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: CachedNetworkImage(
                      imageUrl: photo.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.background),
                      errorWidget: (_, __, ___) => Container(color: AppColors.background),
                    ),
                  ),
                  // 변경 버튼
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _showPhotoPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 13),
                            SizedBox(width: 4),
                            Text('변경',
                                style: TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 삭제(초기화) 버튼
                  if (widget.onClearUserPhoto != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: GestureDetector(
                        onTap: widget.onClearUserPhoto,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 15),
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: AppColors.bluePale,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.person_outline,
                        color: AppColors.blue, size: 26),
                  ),
                  const SizedBox(height: 12),
                  const Text('전신 사진 선택',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  const Text('탭해서 옷장의 전신 코디 사진을 선택하세요',
                      style: TextStyle(
                          color: AppColors.textPlaceholder, fontSize: 11)),
                ],
              ),
      ),
    );
  }

  // ── Step 2: 의류 슬롯 3개 ───────────────────────────────
  Widget _buildClothingSection() {
    const slotCategories = ['상의', '하의', '아우터'];
    const categoryIcons = {
      '상의': Icons.checkroom_outlined,
      '하의': Icons.straighten,
      '아우터': Icons.layers_outlined,
    };
    final selectedCount = widget.selectedItems.values.where((v) => v != null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: slotCategories.asMap().entries.map((entry) {
            final i = entry.key;
            final category = entry.value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 10 : 0),
                child: _buildClothingSlot(
                  category: category,
                  icon: categoryIcons[category]!,
                  item: widget.selectedItems[category],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.touch_app_outlined,
                color: AppColors.textDisabled, size: 13),
            const SizedBox(width: 5),
            Text(
              selectedCount > 0
                  ? '$selectedCount개 선택됨 — 빈 슬롯을 탭해 추가할 수 있습니다'
                  : '슬롯을 탭하면 옷장에서 바로 선택할 수 있습니다',
              style: const TextStyle(color: AppColors.textDisabled, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClothingSlot({
    required String category,
    required IconData icon,
    required WardrobeItem? item,
  }) {
    final isFilled = item != null;
    return GestureDetector(
      onTap: isFilled ? null : () => _showClothingPicker(category),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category,
            style: TextStyle(
              color: isFilled ? AppColors.navy : AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 0.85,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: isFilled
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppColors.background),
                          errorWidget: (_, __, ___) => Container(
                              color: AppColors.background,
                              child: Icon(icon, color: AppColors.textDisabled)),
                        )
                      : Container(
                          color: AppColors.background,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, color: AppColors.textDisabled, size: 24),
                              const SizedBox(height: 6),
                              const Text('탭해서\n선택',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.textPlaceholder,
                                      fontSize: 10,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isFilled
                          ? AppColors.navy.withValues(alpha: 0.35)
                          : AppColors.border,
                      width: isFilled ? 2.0 : 1.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                if (isFilled)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => widget.onClearItem(category),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 액션 버튼 영역 (분석 + 가상 피팅) ───────────────────
  Widget _buildActionButtons() {
    return Column(
      children: [
        // AI 코디 분석 버튼
        GestureDetector(
          onTap: _canAnalyze ? _analyze : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: _canAnalyze ? AppColors.navy : AppColors.textDisabled,
              borderRadius: BorderRadius.circular(12),
              boxShadow: _canAnalyze
                  ? [BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6))]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  _canAnalyze ? 'AI 코디 분석하기' : '코디 아이템을 먼저 선택해 주세요',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // AI 가상 피팅 이미지 생성 버튼
        GestureDetector(
          onTap: _canGenerateFitting ? _generateFitting : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: _canGenerateFitting
                  ? const Color(0xFF4A5568)
                  : AppColors.textDisabled,
              borderRadius: BorderRadius.circular(12),
              boxShadow: _canGenerateFitting
                  ? [BoxShadow(
                      color: const Color(0xFF4A5568).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4))]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.image_search, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  _canGenerateFitting
                      ? 'AI 가상 피팅 이미지 생성'
                      : '내 사진을 선택하면 가상 피팅이 가능합니다',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 결과 대기 플레이스홀더 ──────────────────────────────
  Widget _buildResultPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.tips_and_updates_outlined,
                color: AppColors.textDisabled, size: 26),
          ),
          const SizedBox(height: 14),
          const Text('AI 코디 분석',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('코디 아이템을 선택한 뒤\n버튼을 눌러 주세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textPlaceholder,
                  fontSize: 13,
                  height: 1.6)),
        ],
      ),
    );
  }

  // ── 전체 화면 이미지 뷰어 ────────────────────────────────
  void _openFullScreenImage() {
    if (_fittingImage == null && _mockFittingImageUrl == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(
          imageBytes: _fittingImage,
          imageUrl: _fittingImage == null ? _mockFittingImageUrl : null,
          label: _fittingImage != null ? 'AI 합성 피팅' : '내 사진 기반 피팅',
        ),
      ),
    );
  }

  // ── 분석 완료 결과 카드 ──────────────────────────────────
  Widget _buildResultCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 피팅 이미지 영역 — 이미지가 있을 때만 표시
          if (_fittingImage != null || _mockFittingImageUrl != null)
            GestureDetector(
              onTap: _openFullScreenImage,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  children: [
                    if (_fittingImage != null)
                      Image.memory(
                        _fittingImage!,
                        width: double.infinity,
                        height: 320,
                        fit: BoxFit.cover,
                      )
                    else
                      CachedNetworkImage(
                        imageUrl: _mockFittingImageUrl!,
                        width: double.infinity,
                        height: 320,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            height: 320,
                            color: AppColors.background,
                            child: const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.navy, strokeWidth: 2))),
                        errorWidget: (_, __, ___) => Container(
                            height: 220,
                            color: AppColors.background,
                            child: const Icon(Icons.image_outlined,
                                color: AppColors.textDisabled, size: 40)),
                      ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                            const SizedBox(width: 5),
                            Text(
                              _fittingImage != null ? 'AI 합성 피팅' : '내 사진 기반 피팅',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.fullscreen,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 80,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.white],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 분석 텍스트
          if (_analysisResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI 코디 분석 결과',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                          Text('Gemini Fashion Advisor',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: AppColors.border),
                  const SizedBox(height: 14),
                  Text(_analysisResult!,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.8)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _analyze,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border)),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.refresh,
                                    color: AppColors.textMuted, size: 15),
                                SizedBox(width: 6),
                                Text('다시 분석',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13,
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                                color: AppColors.navy,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.open_in_new,
                                    color: Colors.white, size: 15),
                                SizedBox(width: 6),
                                Text('아이템 상세',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
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
    );
  }

  // ── 분석/생성 중 오버레이 ────────────────────────────────
  Widget _buildAnalyzingOverlay({bool isFitting = false}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20)),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      color: AppColors.navy, strokeWidth: 2.5),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isFitting
                    ? 'AI 가상 피팅 이미지를\n생성 중입니다...'
                    : 'AI 코디 분석을\n진행 중입니다...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.5),
              ),
              const SizedBox(height: 6),
              const Text('Gemini Fashion Advisor가 분석 중입니다',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 전체 화면 이미지 뷰어 위젯 ───────────────────────────
class _FullScreenImageViewer extends StatelessWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String label;

  const _FullScreenImageViewer({
    this.imageBytes,
    this.imageUrl,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5.0,
              child: imageBytes != null
                  ? Image.memory(imageBytes!, fit: BoxFit.contain)
                  : CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2)),
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.image_outlined,
                          color: Colors.white54,
                          size: 48),
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                        const SizedBox(width: 5),
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 옷장 아이템 선택 바텀시트 ─────────────────────────────
class _WardrobePickerSheet extends StatelessWidget {
  final String category;
  final String title;
  final String emptyMessage;
  final ValueChanged<WardrobeItem> onSelect;

  const _WardrobePickerSheet({
    required this.category,
    required this.title,
    required this.emptyMessage,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.close,
                                color: AppColors.textMuted, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('등록된 $category 아이템을 선택하세요',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    Container(height: 1, color: AppColors.border),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<WardrobeItem>>(
                  stream: FirestoreService.wardrobeStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.navy, strokeWidth: 2));
                    }

                    final items = (snapshot.data ?? [])
                        .where((i) => i.category == category)
                        .toList();

                    if (items.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.checkroom_outlined,
                                    color: AppColors.textDisabled, size: 26),
                              ),
                              const SizedBox(height: 16),
                              Text(emptyMessage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                      height: 1.6)),
                            ],
                          ),
                        ),
                      );
                    }

                    return GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return GestureDetector(
                          onTap: () => onSelect(item),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: item.imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) =>
                                        Container(color: AppColors.background),
                                    errorWidget: (_, __, ___) => Container(
                                        color: AppColors.background,
                                        child: const Icon(Icons.image_outlined,
                                            color: AppColors.textDisabled)),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55)),
                                      child: Text(
                                        '${item.createdAt.month}/${item.createdAt.day}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}