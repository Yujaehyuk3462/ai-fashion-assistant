import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../constants/outfit_reason.dart';
import '../constants/style_tips.dart';
import '../models/scrap_entry.dart';
import '../models/user_profile.dart';
import '../models/wardrobe_item.dart';
import '../services/firestore_service.dart';
import '../services/fit_predictor.dart';
import '../services/fitting_job_controller.dart';
import '../services/fitting_progress.dart';
import '../services/outfit_matcher.dart';
import '../widgets/full_screen_image_viewer.dart';

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

  // ── 로딩 중 순환 문구: 상태 안내 대신 실용적인 패션 팁을 보여준다 ──
  // 팁 배열 자체는 lib/constants/style_tips.dart에 공용으로 뽑혀있다
  // (홈 화면 배너와 공유). 결과 카드 안 분석/피팅 영역이 각자
  // analysisStyleTips/fittingStyleTips를 직접 참조해 독립적으로 순환한다.
  Timer? _loadingTextTimer;
  int _loadingTextIndex = 0;

  // ── 가상 피팅 캐시 배지 접기/펼치기 ──────────────────────
  bool _showCacheBadge = false;

  // ── 가상 피팅 스크랩 ─────────────────────────────────────
  String? _scrapId; // null이면 미스크랩, 값이 있으면 그 스크랩 문서 id
  String? _checkedScrapUrl; // 마지막으로 isScrapped를 조회한 URL(중복 조회 방지)

  @override
  void initState() {
    super.initState();
    // 컨트롤러는 AppShell 레벨에서 살아있으므로, 다른 탭에 있는 동안
    // 완료된 작업 결과도 여기서 리스너를 통해 그대로 반영된다.
    widget.jobController.addListener(_onJobChanged);
    _loadUserProfile();
    _syncScrapStatus(); // 이미 결과가 있는 채로 화면에 재진입한 경우 대비
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
    _loadingTextTimer?.cancel();
    super.dispose();
  }

  void _onJobChanged() {
    _syncLoadingTextTimer();
    _syncScrapStatus();
    if (mounted) setState(() {});
  }

  // 피팅 이미지 URL이 바뀔 때마다(신규 생성 캐시 업로드 완료, 캐시 히트,
  // 다른 조합으로 재생성 등) 현재 그 URL이 이미 스크랩됐는지 다시 조회한다.
  // 같은 URL에 대해 중복 조회하지 않도록 마지막으로 확인한 URL을 기억한다.
  Future<void> _syncScrapStatus() async {
    final url = widget.jobController.fittingImageUrl;
    if (url == null || url == _checkedScrapUrl) return;
    _checkedScrapUrl = url;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // 화면 진입 시 조용히 확인하는 배경 조회일 뿐이라, 실패해도(권한/네트워크
    // 문제 등) 조용히 무시한다 — 아이콘이 "미스크랩" 상태로 남을 뿐, 사용자가
    // 직접 북마크를 누르는 _toggleScrap()은 실패 시 별도로 스낵바를 띄운다.
    try {
      final scrapId = await FirestoreService.isScrapped(uid, url);
      // 조회하는 동안 결과가 또 바뀌었으면(다시 생성 등) 낡은 응답은 버린다.
      if (mounted && widget.jobController.fittingImageUrl == url) {
        setState(() => _scrapId = scrapId);
      }
    } catch (e) {
      debugPrint('[스크랩조회] 실패: $e');
    }
  }

  // 스크랩은 사용자가 직접 누른 명시적 액션이므로, 실패를 조용히 무시하지
  // 않고 스낵바로 알린다(다른 백그라운드 저장들과는 다른 처리 방침).
  Future<void> _toggleScrap() async {
    final url = widget.jobController.fittingImageUrl;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('이미지 저장 준비 중이에요. 잠시 후 다시 시도해 주세요.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      if (_scrapId != null) {
        await FirestoreService.deleteScrap(uid, _scrapId!);
        if (!mounted) return;
        setState(() => _scrapId = null);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('스크랩을 해제했습니다.'),
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        final selectedList = widget.selectedItems.values.whereType<WardrobeItem>().toList();
        final entry = ScrapEntry(
          id: '',
          fittingImageUrl: url,
          itemIds: selectedList.map((i) => i.id).toList(),
          itemSummaries: selectedList
              .map((i) => '${i.category}: ${i.attributes?.toPromptLine() ?? ""}')
              .toList(),
          createdAt: DateTime.now(),
        );
        final newId = await FirestoreService.addScrap(uid, entry);
        if (!mounted) return;
        setState(() => _scrapId = newId);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('스크랩에 저장했습니다.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('스크랩 처리 실패: $e'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.red,
      ));
    }
  }

  // isAnalyzing/isGeneratingFitting 중 하나라도 false→true로 바뀌는 순간
  // 타이머를 시작하고, 둘 다 false가 되면 즉시 취소 + 인덱스 리셋한다.
  // dispose()에서도 별도로 취소하므로 화면을 벗어나도 타이머가 새지 않는다.
  // 인덱스는 특정 리스트 길이에 종속시키지 않는 순수 카운터로 두고, 분석/피팅
  // 영역이 각자 자기 리스트 길이로 나머지 연산을 해서 독립적으로 순환한다
  // (결과 카드 안에서 두 영역이 동시에 로딩 상태를 보일 수 있으므로).
  void _syncLoadingTextTimer() {
    final isBusy = widget.jobController.isAnalyzing || widget.jobController.isGeneratingFitting;
    if (isBusy && _loadingTextTimer == null) {
      // 매번 첫 문구부터 똑같이 시작하면 반복 사용 시 지루하므로 랜덤 시작점에서 순환한다.
      _loadingTextIndex = math.Random().nextInt(1000);
      _loadingTextTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
        if (!mounted) return;
        setState(() => _loadingTextIndex++);
      });
    } else if (!isBusy && _loadingTextTimer != null) {
      _loadingTextTimer!.cancel();
      _loadingTextTimer = null;
      _loadingTextIndex = 0;
    }
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

  // 분석 텍스트가 스트리밍으로 들어오기 시작했는지 — 결과 카드 안
  // 분석 영역에서 로딩 팁 대신 실제 텍스트를 보여줄 시점을 가른다.
  bool get _isStreamingAnalysis =>
      widget.jobController.isAnalyzing &&
      (widget.jobController.analysisResult?.isNotEmpty ?? false);

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

    // 새로 생성/조회할 때마다 캐시 배지는 접힌 기본 상태로 되돌린다 —
    // 시연 시 캐시 즉시 로딩이 매번 깔끔하게 보이도록.
    setState(() => _showCacheBadge = false);

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

  // ── 통합 실행: 코디 분석 + (내 사진이 있으면) 가상 피팅을 동시에 진행 ──
  // 서로 독립적인 API 호출이라 순차로 기다릴 필요가 없다. 한쪽이 실패해도
  // 다른 쪽 결과·에러 처리에 영향을 주지 않도록 각자의 기존 에러 처리
  // (_analyze/_generateFitting 내부의 스낵바)를 그대로 둔 채 병렬로만 묶는다.
  Future<void> _analyzeAndFit() async {
    if (!_canAnalyze) return;
    if (widget.userPhoto != null) {
      await Future.wait([_analyze(), _generateFitting()]);
    } else {
      await _analyze();
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
    // 결과 영역은 항상 인라인 그대로다(원래 동작, 손대지 않음) — 로딩 중엔
    // 결과 카드 자체가 영역별 순환 팁을 보여주고, 완료되면 자연스럽게
    // 실제 결과로 전환된다. 그 위에 "로딩 중에만" 뜨는 대기 팝업을 얹는다
    // (Stack) — 결과/점수/피팅 이미지는 팝업에 절대 들어가지 않는다.
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
                            widget.jobController.fittingImageUrl != null ||
                            widget.jobController.isAnalyzing ||
                            widget.jobController.isGeneratingFitting)
                        ? _buildResultCard()
                        : _buildResultPlaceholder(),
                  ],
                ),
              ),
            ),
          ],
        ),
        // 로딩 대기 팝업 — 진행 중(isAnalyzing/isGeneratingFitting)이고
        // 접히지 않았을 때만 뜬다. 완료되는 즉시(isBusy==false) 사라지고,
        // 그 밑에 원래부터 있던 인라인 결과 카드가 그대로 드러난다.
        ValueListenableBuilder<bool>(
          valueListenable: FittingProgress.collapsed,
          builder: (context, collapsed, _) {
            final isBusy =
                widget.jobController.isAnalyzing || widget.jobController.isGeneratingFitting;
            if (!isBusy || collapsed) return const SizedBox.shrink();
            return _buildLoadingPopupOverlay();
          },
        ),
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
                          // 드래그 조합 슬롯에서는 배경 제거본이 있으면 우선 사용 —
                          // 실제 합성/분석 호출(fitting_job_controller)은 항상 원본을 쓴다.
                          imageUrl: item.cutoutImageUrl ?? item.imageUrl,
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
      case FitLevel.slim:
        return AppColors.red;
      case FitLevel.regular:
        return AppColors.greenDark;
      case FitLevel.semiOversized:
        return AppColors.amber;
      case FitLevel.oversized:
      case FitLevel.loose:
        return AppColors.blue;
    }
  }

  // ── 액션 버튼 (분석 + 가상 피팅 통합 원클릭) ────────────
  Widget _buildActionButtons() {
    final buttonLabel = !_canAnalyze
        ? '코디 아이템을 먼저 선택해 주세요'
        : (widget.userPhoto != null ? 'AI 코디 분석 + 가상 피팅' : 'AI 코디 분석하기');
    return GestureDetector(
      onTap: _canAnalyze ? _analyzeAndFit : null,
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
              buttonLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
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
        pageBuilder: (_, __, ___) => FullScreenImageViewer(
          imageBytes: fittingImage,
          imageUrl: fittingImage == null ? (fittingImageUrl ?? _mockFittingImageUrl) : null,
          label: hasRealResult ? 'AI 합성 피팅' : '내 사진 기반 피팅',
        ),
      ),
    );
  }

  // ── 로딩 대기 팝업(순수 대기 화면 — 결과/점수/피팅 이미지는 절대 안 들어간다) ──
  // 배경을 탭해도 닫히지 않고 팝업 안의 접기 버튼으로만 닫힌다.
  Widget _buildLoadingPopupOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {},
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          alignment: Alignment.center,
          child: _FittingLoadingPopup(selectedItems: widget.selectedItems),
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
    final isAnalyzing = widget.jobController.isAnalyzing;
    final isGeneratingFitting = widget.jobController.isGeneratingFitting;
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
                          // 데모 녹화 시 캐시 즉시 로딩을 깔끔하게 보이기 위해 배지는
                          // 기본 접힘 상태 — "펼치기"를 탭해야만 "저장된 결과"가 보인다.
                          if (isFittingFromCache) ...[
                            const SizedBox(width: 6),
                            if (_showCacheBadge)
                              GestureDetector(
                                onTap: () => setState(() => _showCacheBadge = false),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                              )
                            else
                              GestureDetector(
                                onTap: () => setState(() => _showCacheBadge = true),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: const Text('펼치기',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline)),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Row(
                        children: [
                          // 실제 AI 합성 결과일 때만 스크랩 가능 — 내 사진
                          // 기반 폴백(_mockFittingImageUrl만 있는 경우)은 제외.
                          if (hasRealFittingResult) ...[
                            GestureDetector(
                              onTap: _toggleScrap,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _scrapId != null ? Icons.bookmark : Icons.bookmark_border,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.fullscreen,
                                color: Colors.white, size: 18),
                          ),
                        ],
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
            )
          else if (isGeneratingFitting)
            // 아직 이미지는 없지만 생성 중 — 같은 자리에 순환 팁을 보여주고,
            // 완료되면 위 분기(hasRealFittingResult)로 자연스럽게 전환된다.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Container(
                width: double.infinity,
                height: 320,
                color: AppColors.background,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Center(
                  child: Text(
                    fittingStyleTips[_loadingTextIndex % fittingStyleTips.length],
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.6),
                  ),
                ),
              ),
            ),
          // 피팅 결과(캐시든 신규든)가 있으면 강제로 다시 생성할 수 있는 버튼.
          // 통합 버튼(_analyzeAndFit)은 최초 1회 실행 전용이라, 재생성은
          // 여기 하나로만 남긴다.
          if (hasRealFittingResult)
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
          // 분석 텍스트 — 결과가 있거나, 아직 없어도 분석이 진행 중이면
          // (스트리밍 시작 전 짧은 순간) 이 영역 자체는 미리 보여준다.
          if (analysisResult != null || isAnalyzing)
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
                  if (analysisResult == null)
                    // 스트리밍이 아직 첫 글자도 안 왔을 때 — 순환 팁으로 대체.
                    // 텍스트가 들어오기 시작하면 이 분기 자체가 사라지고
                    // 아래 실제 결과 분기로 자연스럽게 전환된다.
                    Text(
                      analysisStyleTips[_loadingTextIndex % analysisStyleTips.length],
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.8),
                    )
                  else ...[
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
                ],
              ),
            ),
        ],
      ),
    );
  }

}

// 팝업 슬라이드 한 장 — 보여줄 아이템과 그 아래 캡션(추천 이유 또는 팁).
typedef _PopupSlide = ({WardrobeItem item, String caption});

// 로딩 대기 팝업의 콤팩트 카드 — 화면 폭의 80%, 내용에 맞는 세로 크기.
// 지금 피팅 중인 옷들과 어울리는 "다른 카테고리" 아이템을 OutfitMatcher로
// 로컬 매칭해(Gemini 호출 없음) 큰 이미지+짧은 이유로 3초마다 자동
// 슬라이드한다. 매칭 후보가 없으면 현재 피팅 중인 옷 + style_tips 팁으로
// 폴백한다. 순수 표시용 — FittingJobController 등 파이프라인 상태는
// 절대 건드리지 않는다.
class _FittingLoadingPopup extends StatefulWidget {
  final Map<String, WardrobeItem?> selectedItems;

  const _FittingLoadingPopup({required this.selectedItems});

  @override
  State<_FittingLoadingPopup> createState() => _FittingLoadingPopupState();
}

class _FittingLoadingPopupState extends State<_FittingLoadingPopup> {
  late final PageController _pageController;
  Timer? _timer;
  List<_PopupSlide>? _slides; // null = 아직 계산 중
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadSlides();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadSlides() async {
    final slides = await _buildSuggestionSlides();
    if (!mounted) return;
    setState(() => _slides = slides);
    _startAutoSlide();
  }

  void _startAutoSlide() {
    final slides = _slides;
    if (slides == null || slides.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = ((_pageController.page ?? 0).round() + 1) % slides.length;
      _pageController.animateToPage(next,
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  // 지금 피팅 중인 각 아이템(상의/하의 등)을 앵커 삼아, 그 아이템과 어울리는
  // 다른 카테고리 아이템은 물론 "같은 카테고리의 다른 선택지"도 후보에
  // 넣는다(예: 피팅 중인 상의를 기준으로 다른 하의를, 피팅 중인 하의를
  // 기준으로 다른 상의를). 제외하는 건 지금 피팅 중인 그 아이템 자체
  // (itemId)뿐 — 카테고리 전체를 제외하지 않는다. 카테고리당 상위 2개까지
  // 모아 전체를 궁합 점수순으로 정렬해 최대 5장. 로컬 계산만 하므로
  // Gemini 호출은 0회. 후보가 하나도 없으면(옷장이 빈약하거나 매칭 실패)
  // 현재 피팅 중인 옷 + style_tips 팁으로 폴백.
  Future<List<_PopupSlide>> _buildSuggestionSlides() async {
    final selected = widget.selectedItems.values.whereType<WardrobeItem>().toList();
    final selectedWithAttrs = selected.where((i) => i.attributes != null).toList();

    if (selectedWithAttrs.isNotEmpty) {
      try {
        final wardrobe = await FirestoreService.wardrobeStream().first;
        final fittingIds = selected.map((i) => i.id).toSet();
        const allCategories = ['상의', '하의', '아우터', '신발', '액세서리'];

        final scored = <({WardrobeItem item, WardrobeItem anchor, double score})>[];
        for (final category in allCategories) {
          // 같은 카테고리 자기 자신과 비교하는 건 의미가 없으니, 이 카테고리를
          // 추천할 근거는 "다른 카테고리"의 피팅 아이템만 앵커로 삼는다.
          final eligibleAnchors =
              selectedWithAttrs.where((a) => a.category != category).toList();
          if (eligibleAnchors.isEmpty) continue;

          final pool = wardrobe
              .where((i) =>
                  i.category == category && i.attributes != null && !fittingIds.contains(i.id))
              .toList();
          if (pool.isEmpty) continue;

          final perCategory = <({WardrobeItem item, WardrobeItem anchor, double score})>[];
          for (final candidate in pool) {
            WardrobeItem? bestAnchor;
            var bestScore = double.negativeInfinity;
            for (final anchor in eligibleAnchors) {
              final score =
                  OutfitMatcher.compatibilityScore(anchor.attributes!, candidate.attributes!);
              if (score > bestScore) {
                bestScore = score;
                bestAnchor = anchor;
              }
            }
            if (bestAnchor != null) {
              perCategory.add((item: candidate, anchor: bestAnchor, score: bestScore));
            }
          }
          perCategory.sort((a, b) => b.score.compareTo(a.score));
          scored.addAll(perCategory.take(2));
        }

        scored.sort((a, b) => b.score.compareTo(a.score));
        if (scored.isNotEmpty) {
          return scored
              .take(5)
              .map((s) =>
                  (item: s.item, caption: buildOutfitReason(anchor: s.anchor, candidate: s.item)))
              .toList();
        }
      } catch (e) {
        debugPrint('[FITTING-POPUP] 추천 매칭 실패, 폴백으로 전환: $e');
      }
    }

    // 폴백 — 현재 피팅 중인 옷 + 순환 팁.
    if (selected.isEmpty) return const [];
    return [
      for (var i = 0; i < selected.length; i++)
        (item: selected[i], caption: fittingStyleTips[i % fittingStyleTips.length]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: slides == null
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.navy, strokeWidth: 2))
                : slides.isEmpty
                    ? const Center(
                        child: Icon(Icons.checkroom_outlined,
                            color: AppColors.textDisabled, size: 48))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          color: AppColors.background,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: slides.length,
                            onPageChanged: (i) => setState(() => _currentPage = i),
                            itemBuilder: (context, i) {
                              final item = slides[i].item;
                              return Padding(
                                padding: const EdgeInsets.all(14),
                                child: CachedNetworkImage(
                                  imageUrl: item.cutoutImageUrl ?? item.imageUrl,
                                  fit: BoxFit.contain,
                                  placeholder: (_, __) => const SizedBox.shrink(),
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.image_not_supported_outlined,
                                      color: AppColors.textDisabled),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 36,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  slides == null
                      ? '분석 준비 중이에요...'
                      : slides.isEmpty
                          ? 'AI가 코디를 살펴보고 있어요...'
                          : slides[_currentPage].caption,
                  key: ValueKey(slides == null ? -1 : _currentPage),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => FittingProgress.collapsed.value = true,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('접기',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down, color: AppColors.textMuted, size: 16),
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
                                    imageUrl: item.cutoutImageUrl ?? item.imageUrl,
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