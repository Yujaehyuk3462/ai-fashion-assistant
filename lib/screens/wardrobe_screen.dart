import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';
import '../data/wardrobe_data.dart' show categories;
import '../models/clothing_attributes.dart';
import '../models/clothing_size.dart';
import '../models/wardrobe_item.dart';
import '../services/firestore_service.dart';
import '../services/gemini_api_exception.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';

const _uploadCategories = ['상의', '하의', '아우터', '전신'];

// 위젯과 무관하게 실행되는 백그라운드 작업 — 업로드 화면을 벗어나도
// 계속 진행되고, 실패해도 조용히 무시한다(분석 시점 폴백이 나중에 채운다).
Future<void> _extractAndCacheAttributes(
  String itemId,
  String imageUrl,
  String category,
) async {
  try {
    final attributes = await _extractAttributesWithRetry(imageUrl, category);
    await FirestoreService.updateWardrobeAttributes(itemId, attributes);
  } catch (_) {
    // 업로드 자체는 이미 끝난 뒤라 실패를 사용자에게 노출하지 않는다.
    // 분석 시점 폴백(FittingJobController._resolveAttributes)이 나중에 채운다.
  }
}

// 타임아웃 등 일시적 오류는 한 번 더 시도해본다.
Future<ClothingAttributes> _extractAttributesWithRetry(
  String imageUrl,
  String category,
) async {
  try {
    return await GeminiService.extractAttributes(imageUrl: imageUrl, category: category);
  } on TimeoutException {
    return await GeminiService.extractAttributes(imageUrl: imageUrl, category: category);
  }
}

// 사이즈표 OCR도 타임아웃/503·429 같은 일시적 오류는 한 번 더 시도해보고,
// 그래도 실패하면 그대로 던져서 호출부가 손 입력 폴백으로 안내하게 한다.
Future<ClothingSize> _scanSizeChartWithRetry({
  required Uint8List imageBytes,
  required String category,
  required String sizeLabel,
}) async {
  try {
    return await GeminiService.extractSizeFromChart(
      imageBytes: imageBytes,
      category: category,
      sizeLabel: sizeLabel,
    );
  } on TimeoutException {
    return await GeminiService.extractSizeFromChart(
      imageBytes: imageBytes,
      category: category,
      sizeLabel: sizeLabel,
    );
  } on GeminiApiException catch (e) {
    if (!e.isRetryable) rethrow;
    return await GeminiService.extractSizeFromChart(
      imageBytes: imageBytes,
      category: category,
      sizeLabel: sizeLabel,
    );
  }
}

class WardrobeScreen extends StatefulWidget {
  final ValueChanged<WardrobeItem>? onSelectItem;

  const WardrobeScreen({super.key, this.onSelectItem});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String _activeCategory = '전체';
  bool _isUploading = false;

  List<WardrobeItem> _filter(List<WardrobeItem> all) {
    if (_activeCategory == '전체') return all;
    return all.where((item) => item.category == _activeCategory).toList();
  }

  // ── 카드 탭: 피팅룸 전송 액션 시트 ──────────────────────
  void _showCardOptions(BuildContext context, WardrobeItem item) {
    if (widget.onSelectItem == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.category,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '아이템 선택됨',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.onSelectItem!(item);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.checkroom, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '피팅룸에서 입어보기',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 아이템 삭제 확인 ─────────────────────────────────────
  Future<void> _confirmDelete(WardrobeItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '아이템 삭제',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          '이 아이템을 삭제하시겠습니까?\n삭제 후 복구할 수 없습니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await StorageService.deleteWardrobeImage(item.imageUrl);
      await FirestoreService.deleteWardrobeItem(item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('아이템이 삭제되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 실패: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  // ── FAB: 소스 선택 → 사진 선택 → 카테고리 선택 → 업로드 ──
  void _showAddBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _AddBottomSheet(
        onPickSource: (source) async {
          Navigator.pop(sheetCtx); // 소스 선택 시트 닫기
          await _pickAndUpload(source);
        },
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    // 해상도를 미리 낮춰 두면 Storage 업로드는 물론, 이후 AI 분석/피팅 때마다
    // 반복되는 다운로드·base64 인코딩 페이로드도 함께 줄어든다.
    final xFile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1440,
      maxHeight: 1440,
    );
    if (xFile == null || !mounted) return;

    // 카테고리 선택
    final category = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CategoryPickerSheet(),
    );
    if (category == null || !mounted) return;

    // 치수 입력(선택) — 전신 사진은 핏 예측 대상이 아니므로 건너뛴다.
    ClothingSize? size;
    if (category != '전신') {
      size = await showModalBottomSheet<ClothingSize>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SizeInputSheet(category: category),
      );
      if (!mounted) return;
    }

    setState(() => _isUploading = true);
    try {
      final imageUrl = await StorageService.uploadWardrobeImage(xFile);
      final itemId = await FirestoreService.addWardrobeItem(
        imageUrl: imageUrl,
        category: category,
        size: size,
      );
      // 속성 추출은 업로드 완료를 기다리게 하지 않고 백그라운드로 흘려보낸다.
      unawaited(_extractAndCacheAttributes(itemId, imageUrl, category));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$category 아이템이 등록되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('업로드 실패: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<WardrobeItem>>(
          stream: FirestoreService.wardrobeStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingView();
            }
            if (snapshot.hasError) {
              return _ErrorView(message: snapshot.error.toString());
            }

            final allItems = snapshot.data ?? [];
            final items = _filter(allItems);

            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(allItems.length),
                    Expanded(
                      child: items.isEmpty
                          ? _buildEmptyState()
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 0.72,
                              ),
                              itemCount: items.length,
                              itemBuilder: (ctx, i) => GestureDetector(
                                onTap: widget.onSelectItem != null
                                    ? () => _showCardOptions(ctx, items[i])
                                    : null,
                                child: _WardrobeCard(
                                  item: items[i],
                                  onDelete: () => _confirmDelete(items[i]),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                _buildFab(),
              ],
            );
          },
        ),
        if (_isUploading) _buildUploadOverlay(),
      ],
    );
  }

  Widget _buildHeader(int totalCount) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '내 옷장',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$totalCount벌 보관 중',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune, color: AppColors.textSecondary, size: 20),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: categories.map((cat) {
                  final isActive = _activeCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _activeCategory = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.navy : AppColors.background,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: isActive ? Colors.white : AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.checkroom_outlined,
                color: AppColors.textDisabled, size: 26),
          ),
          const SizedBox(height: 20),
          const Text(
            '아직 등록된 옷이 없습니다',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '새 옷을 등록해 보세요!',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFab() {
    return Positioned(
      bottom: 24,
      right: 20,
      child: GestureDetector(
        onTap: _showAddBottomSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                '옷 추가',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.navy, strokeWidth: 2.5),
              SizedBox(height: 20),
              Text(
                '사진을 업로드 중입니다...',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '잠시만 기다려 주세요',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 소스 선택 바텀시트 ──────────────────────────────────
class _AddBottomSheet extends StatelessWidget {
  final ValueChanged<ImageSource> onPickSource;

  const _AddBottomSheet({required this.onPickSource});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '새 옷 등록',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '사진을 선택해 옷장에 추가하세요',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            _SourceButton(
              icon: Icons.camera_alt_outlined,
              label: '카메라로 촬영하기',
              sublabel: '지금 바로 사진을 찍어 등록',
              onTap: () => onPickSource(ImageSource.camera),
            ),
            const SizedBox(height: 12),
            _SourceButton(
              icon: Icons.photo_library_outlined,
              label: '갤러리에서 가져오기',
              sublabel: '저장된 사진을 선택해 등록',
              onTap: () => onPickSource(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 카테고리 선택 바텀시트 ──────────────────────────────
class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '카테고리 선택',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '이 옷의 카테고리를 선택해 주세요',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ..._uploadCategories.map((cat) {
              final icons = {
                '상의': Icons.checkroom_outlined,
                '하의': Icons.straighten,
                '아우터': Icons.layers_outlined,
                '전신': Icons.person_outline,
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, cat),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icons[cat]!, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          cat,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios,
                            color: AppColors.textDisabled, size: 14),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── 치수 입력 바텀시트 (선택) ─────────────────────────────
class _SizeInputSheet extends StatefulWidget {
  final String category;

  const _SizeInputSheet({required this.category});

  @override
  State<_SizeInputSheet> createState() => _SizeInputSheetState();
}

class _SizeInputSheetState extends State<_SizeInputSheet> {
  static const _bottomFields = [
    (key: 'waistWidth', label: '허리단면'),
    (key: 'hipWidth', label: '엉덩이단면'),
    (key: 'thighWidth', label: '허벅지단면'),
    (key: 'pantsLength', label: '총장'),
  ];
  static const _topFields = [
    (key: 'totalLength', label: '총장'),
    (key: 'shoulderWidth', label: '어깨너비'),
    (key: 'chestWidth', label: '가슴단면'),
    (key: 'sleeveLength', label: '소매길이'),
  ];

  late final _fields = widget.category == '하의' ? _bottomFields : _topFields;
  final _controllers = <String, TextEditingController>{};
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      _controllers[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(String key) {
    final text = _controllers[key]?.text.trim();
    if (text == null || text.isEmpty) return null;
    return double.tryParse(text);
  }

  void _submit() {
    final size = ClothingSize(
      totalLength: _parse('totalLength'),
      shoulderWidth: _parse('shoulderWidth'),
      chestWidth: _parse('chestWidth'),
      sleeveLength: _parse('sleeveLength'),
      waistWidth: _parse('waistWidth'),
      hipWidth: _parse('hipWidth'),
      thighWidth: _parse('thighWidth'),
      pantsLength: _parse('pantsLength'),
    );
    Navigator.pop(context, size.hasAnyData ? size : null);
  }

  // 사이즈표 캡처 → 사이즈 행 선택 → 촬영/선택 → OCR → 필드 자동 채움.
  // 실패해도 필드는 비어있는 채로 남아 손 입력으로 자연스럽게 폴백된다.
  Future<void> _scanSizeChart() async {
    final sizeLabel = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SizeLabelPickerSheet(),
    );
    if (sizeLabel == null || !mounted) return;

    final source = await _pickImageSourceChoice(context);
    if (source == null || !mounted) return;

    final xFile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (xFile == null || !mounted) return;

    setState(() => _isScanning = true);
    try {
      final bytes = await xFile.readAsBytes();
      final result = await _scanSizeChartWithRetry(
        imageBytes: bytes,
        category: widget.category,
        sizeLabel: sizeLabel,
      );
      if (!mounted) return;
      _applyScannedSize(result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.hasAnyData
            ? 'AI가 읽은 값이에요. 확인 후 저장해 주세요.'
            : '사이즈표에서 인식된 값이 없어요. 사진을 다시 확인하거나 직접 입력해 주세요.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('자동 인식 실패: 직접 입력해 주세요. ($e)'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.red,
      ));
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _applyScannedSize(ClothingSize size) {
    void set(String key, double? value) {
      _controllers[key]?.text = value?.toString() ?? '';
    }

    set('totalLength', size.totalLength);
    set('shoulderWidth', size.shoulderWidth);
    set('chestWidth', size.chestWidth);
    set('sleeveLength', size.sleeveLength);
    set('waistWidth', size.waistWidth);
    set('hipWidth', size.hipWidth);
    set('thighWidth', size.thighWidth);
    set('pantsLength', size.pantsLength);
  }

  Future<ImageSource?> _pickImageSourceChoice(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.navy),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.navy),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '치수 입력 (선택)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '무신사 사이즈표를 참고해 입력하면 체형과 비교한 예상 핏을 보여드려요',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _isScanning ? null : _scanSizeChart,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bluePale,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isScanning)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.document_scanner_outlined, color: AppColors.blue, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _isScanning ? 'AI가 사이즈표를 읽는 중...' : '사이즈표 캡처로 자동 입력',
                        style: const TextStyle(
                            color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ..._fields.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _controllers[f.key],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '${f.label} (cm)',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('건너뛰기',
                          style: TextStyle(
                              color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _submit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '완료',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 사이즈표 OCR용 사이즈 행 선택 바텀시트 ───────────────
class _SizeLabelPickerSheet extends StatefulWidget {
  const _SizeLabelPickerSheet();

  @override
  State<_SizeLabelPickerSheet> createState() => _SizeLabelPickerSheetState();
}

class _SizeLabelPickerSheetState extends State<_SizeLabelPickerSheet> {
  static const _quickLabels = ['S', 'M', 'L', 'XL', 'XXL'];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _controller.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(context, label);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '어떤 사이즈 행을 읽을까요?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '사이즈표에서 이 옷에 해당하는 사이즈를 알려주세요',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickLabels.map((label) {
                    final isSelected = _controller.text == label;
                    return ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _controller.text = label),
                      selectedColor: AppColors.bluePale,
                      labelStyle: TextStyle(
                          color: isSelected ? AppColors.blue : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                      backgroundColor: AppColors.background,
                      side: BorderSide(color: isSelected ? AppColors.blue : AppColors.border),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: '예: L, 100, Free',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _submit,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '다음: 사진 선택',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(sublabel,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    )),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios,
                color: AppColors.textDisabled, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── 공통 뷰 ──────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.navy, strokeWidth: 2),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppColors.textDisabled, size: 40),
            const SizedBox(height: 16),
            const Text(
              '데이터를 불러오지 못했습니다',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 옷장 카드 ─────────────────────────────────────────
class _WardrobeCard extends StatelessWidget {
  final WardrobeItem item;
  final VoidCallback onDelete;

  const _WardrobeCard({required this.item, required this.onDelete});

  String _formatDate(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(10)),
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.background),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.background,
                      child: const Icon(Icons.image_outlined,
                          color: AppColors.textDisabled),
                    ),
                  ),
                ),
                // 카테고리 뱃지
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.category,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                // 삭제 버튼
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: Colors.white, size: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.category,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(item.createdAt),
                  style: const TextStyle(
                    color: AppColors.textPlaceholder,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
