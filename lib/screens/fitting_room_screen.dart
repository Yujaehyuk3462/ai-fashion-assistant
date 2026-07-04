import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/user_profile.dart';
import '../models/wardrobe_item.dart';
import '../services/firestore_service.dart';
import '../services/fit_predictor.dart';
import '../services/fitting_job_controller.dart';

class FittingRoomScreen extends StatefulWidget {
  final FittingJobController jobController;
  final Map<String, WardrobeItem?> selectedItems;
  final WardrobeItem? userPhoto;
  final Function(String category, WardrobeItem item) onSetItem;
  final ValueChanged<String> onClearItem;
  final ValueChanged<WardrobeItem> onSetUserPhoto;
  final VoidCallback? onClearUserPhoto;       // 내 사진 초기화 (main.dart 연동 필요)
  final VoidCallback onNavigateToDetail;

  const FittingRoomScreen({
    super.key,
    required this.jobController,
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
  String? _mockFittingImageUrl;
  final ScrollController _scrollController = ScrollController();

  // 핏 예측용 체형 프로필 — Gemini 호출과 무관하게 로컬 계산만으로
  // 쓰이므로, 코디 분석 버튼과 상관없이 화면 진입 시 바로 불러온다.
  UserProfile? _userProfile;

  @override
  void initState() {
    super.initState();
    // 컨트롤러는 AppShell 레벨에서 살아있으므로, 다른 탭에 있는 동안
    // 완료된 작업 결과도 여기서 리스너를 통해 그대로 반영된다.
    widget.jobController.addListener(_onJobChanged);
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile = await FirestoreService.getUserProfileSilently(uid);
    if (mounted) setState(() => _userProfile = profile);
  }

  @override
  void dispose() {
    widget.jobController.removeListener(_onJobChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onJobChanged() {
    if (mounted) setState(() {});
  }

  // ── 점수 파싱 헬퍼 ──────────────────────────────────────
  int? _parseScore(String text) {
    final match = RegExp(r'\[점수\]\s*(\d+)').firstMatch(text);
    if (match == null) return null;
    final score = int.tryParse(match.group(1) ?? '');
    if (score == null) return null;
    return score.clamp(1, 100);
  }

  String _stripScoreLine(String text) {
    return text.replaceFirst(RegExp(r'\[점수\]\s*\d+\n?'), '').trim();
  }

  Color _scoreColor(int score) {
    if (score >= 85) return const Color(0xFF2563EB);
    if (score >= 70) return const Color(0xFF16A34A);
    if (score >= 50) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  String _scoreLabel(int score) {
    if (score >= 85) return '매우 잘 어울려요';
    if (score >= 70) return '잘 어울려요';
    if (score >= 50) return '무난한 조합이에요';
    return '조합 개선이 필요해요';
  }

  bool get _canAnalyze =>
      widget.selectedItems.values.any((v) => v != null) &&
      !widget.jobController.isBusy;

  bool get _canGenerateFitting =>
      widget.userPhoto != null &&
      widget.selectedItems.values.any((v) => v != null) &&
      !widget.jobController.isBusy;

  // 분석 텍스트가 스트리밍으로 들어오기 시작하면 전체 화면 오버레이를 걷어내고
  // 결과 카드가 실시간으로 채워지는 모습을 그대로 보여준다.
  bool get _isStreamingAnalysis =>
      widget.jobController.isAnalyzing &&
      (widget.jobController.analysisResult?.isNotEmpty ?? false);

  bool get _shouldBlockWithOverlay =>
      (widget.jobController.isAnalyzing && !_isStreamingAnalysis) ||
      widget.jobController.isGeneratingFitting;

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
    final userPhoto = widget.userPhoto;

    setState(() => _mockFittingImageUrl = null);

    // 체형 프로필이 입력되어 있으면 사진보다 우선해서 쓰므로(더 빠르고 정확),
    // 분석 직전에 조회한다. 조회 실패는 조용히 null로 처리되어 기존 사진
    // 기반 분석으로 자연스럽게 폴백된다.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userProfile =
        uid != null ? await FirestoreService.getUserProfileSilently(uid) : null;
    if (!mounted) return;

    // jobController.analyze()는 위젯과 무관하게 끝까지 실행되므로,
    // 이 화면을 벗어났다가 돌아와도 결과가 유지된다. 여기서의 await는
    // 스낵바 표시·자동 스크롤 같은 "이 화면이 떠 있을 때만" 필요한
    // UX 후처리를 위한 것일 뿐이다.
    await widget.jobController.analyze(
      clothingItems: selectedList,
      userPhoto: userPhoto,
      userProfile: userProfile,
    );
    if (!mounted) return;

    final error = widget.jobController.analysisError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('분석 실패: $error'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.red,
        action: SnackBarAction(
          label: '다시 시도',
          textColor: Colors.white,
          onPressed: _analyze,
        ),
      ));
      return;
    }
    setState(() => _mockFittingImageUrl = userPhoto?.imageUrl); // 내 사진 없으면 null
    _scrollToResult();
  }

  // ── Gemini 가상 피팅 이미지 생성 ─────────────────────────
  Future<void> _generateFitting({bool forceRegenerate = false}) async {
    if (!_canGenerateFitting) return;
    final selectedList = widget.selectedItems.values.whereType<WardrobeItem>().toList();
    final userPhoto = widget.userPhoto!;

    await widget.jobController.generateFitting(
      userPhoto: userPhoto,
      clothingItems: selectedList,
      forceRegenerate: forceRegenerate,
    );
    if (!mounted) return;

    final error = widget.jobController.fittingError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('가상 피팅 실패: $error'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.red,
        action: SnackBarAction(
          label: '다시 시도',
          textColor: Colors.white,
          onPressed: _generateFitting,
        ),
      ));
      return;
    }
    setState(() => _mockFittingImageUrl ??= userPhoto.imageUrl);
    _scrollToResult();
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
                    const SizedBox(height: 16),
                    _buildFitPreview(),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                    const SizedBox(height: 20),
                    (widget.jobController.analysisResult != null ||
                            widget.jobController.fittingImage != null ||
                            widget.jobController.fittingImageUrl != null)
                        ? _buildResultCard()
                        : _buildResultPlaceholder(),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_shouldBlockWithOverlay) _buildAnalyzingOverlay(isFitting: widget.jobController.isGeneratingFitting),
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

  // ── 예상 핏 (규칙 기반, 숫자 비교만 — Gemini 호출 없음) ──
  // 옷 치수와 체형 프로필을 대조한 결과일 뿐이므로 선택된 아이템이
  // 바뀌는 즉시(코디 분석 버튼을 누르기 전에도) 바로 반영된다.
  Widget _buildFitPreview() {
    final entries = widget.selectedItems.entries
        .where((e) => e.value != null)
        .map((e) => (category: e.key, item: e.value!))
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
            children: [
              const Icon(Icons.straighten, color: AppColors.navy, size: 16),
              const SizedBox(width: 6),
              const Text('예상 핏',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              const Text('실측 기준 아님 · 참고용',
                  style: TextStyle(color: AppColors.textPlaceholder, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 14),
          ...entries.map((e) {
            final result = FitPredictor.predict(
              category: e.category,
              size: e.item.size,
              profile: _userProfile,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(e.category,
                        style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(
                      result != null ? result.label : '정보 부족으로 예측 불가',
                      style: TextStyle(
                        color: result != null
                            ? _fitColor(result.level)
                            : AppColors.textDisabled,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (result != null)
                    Text(
                      '여유분 ${result.easeCm >= 0 ? '+' : ''}${result.easeCm.toStringAsFixed(1)}cm',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _fitColor(FitLevel level) {
    switch (level) {
      case FitLevel.tight:
        return AppColors.red;
      case FitLevel.regular:
        return AppColors.greenDark;
      case FitLevel.oversized:
        return AppColors.blue;
    }
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
    final fittingImage = widget.jobController.fittingImage;
    final fittingImageUrl = widget.jobController.fittingImageUrl;
    final hasRealResult = fittingImage != null || fittingImageUrl != null;
    if (!hasRealResult && _mockFittingImageUrl == null) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(
          imageBytes: fittingImage,
          imageUrl: fittingImage == null ? (fittingImageUrl ?? _mockFittingImageUrl) : null,
          label: hasRealResult ? 'AI 합성 피팅' : '내 사진 기반 피팅',
        ),
      ),
    );
  }

  // ── 분석 완료 결과 카드 ──────────────────────────────────
  Widget _buildResultCard() {
    final fittingImage = widget.jobController.fittingImage;
    final fittingImageUrl = widget.jobController.fittingImageUrl;
    final isFittingFromCache = widget.jobController.isFittingFromCache;
    final hasRealFittingResult = fittingImage != null || fittingImageUrl != null;
    final analysisResult = widget.jobController.analysisResult;
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
          if (hasRealFittingResult || _mockFittingImageUrl != null)
            GestureDetector(
              onTap: _openFullScreenImage,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  children: [
                    if (fittingImage != null)
                      Image.memory(
                        fittingImage,
                        width: double.infinity,
                        height: 320,
                        fit: BoxFit.cover,
                      )
                    else
                      CachedNetworkImage(
                        imageUrl: fittingImageUrl ?? _mockFittingImageUrl!,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                                Text(
                                  hasRealFittingResult ? 'AI 합성 피팅' : '내 사진 기반 피팅',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          if (isFittingFromCache) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.save_outlined, color: Colors.white, size: 12),
                                  SizedBox(width: 5),
                                  Text('저장된 결과',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ],
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
          // 캐시된 결과일 때 강제로 새로 생성할 수 있는 버튼
          if (isFittingFromCache)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: GestureDetector(
                onTap: () => _generateFitting(forceRegenerate: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border)),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, color: AppColors.textMuted, size: 15),
                      SizedBox(width: 6),
                      Text('새로 생성하기',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          // 분석 텍스트
          if (analysisResult != null)
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
                  const SizedBox(height: 16),
                  // ── 컬러 조합 점수 배지 ──────────────────────────
                  Builder(builder: (context) {
                    final score = _parseScore(analysisResult);
                    if (score == null) return const SizedBox.shrink();
                    final color = _scoreColor(score);
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CircularProgressIndicator(
                                  value: score / 100,
                                  strokeWidth: 5,
                                  backgroundColor: color.withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation<Color>(color),
                                ),
                                Center(
                                  child: Text(
                                    '$score',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('컬러 조합 점수',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(
                                  _scoreLabel(score),
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text('$score / 100점',
                                    style: TextStyle(
                                        color: color.withValues(alpha: 0.75),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Text(_stripScoreLine(analysisResult),
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.8)),
                  if (_isStreamingAnalysis) ...[
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              color: AppColors.textDisabled, strokeWidth: 1.5),
                        ),
                        SizedBox(width: 6),
                        Text('작성 중...',
                            style: TextStyle(
                                color: AppColors.textDisabled, fontSize: 11)),
                      ],
                    ),
                  ],
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