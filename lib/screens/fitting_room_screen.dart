import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';
import '../data/fitting_data.dart';

class FittingRoomScreen extends StatefulWidget {
  final VoidCallback onNavigateToDetail;

  const FittingRoomScreen({super.key, required this.onNavigateToDetail});

  @override
  State<FittingRoomScreen> createState() => _FittingRoomScreenState();
}

class _FittingRoomScreenState extends State<FittingRoomScreen> {
  bool _hasPhoto = false;
  bool _isAnalyzing = false;
  bool _showResults = false;
  int _activeSlide = 0;

  void _handleUpload() => setState(() => _hasPhoto = true);

  void _handleMatch() async {
    if (!_hasPhoto) {
      _handleUpload();
      return;
    }
    setState(() => _isAnalyzing = true);
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) setState(() { _isAnalyzing = false; _showResults = true; });
  }

  void _prevSlide() => setState(() => _activeSlide = (_activeSlide == 0 ? simulationResults.length - 1 : _activeSlide - 1));
  void _nextSlide() => setState(() => _activeSlide = (_activeSlide == simulationResults.length - 1 ? 0 : _activeSlide + 1));

  @override
  Widget build(BuildContext context) {
    final result = simulationResults[_activeSlide];
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: _showResults ? 80 : 0),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _hasPhoto ? _buildPhotoPreview() : _buildUploadArea(),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildMatchButton(),
                    ),
                    if (_showResults) ...[
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildResults(result),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_showResults) _buildBuyButton(),
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
              const Text('AI 피팅룸', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.bluePale, borderRadius: BorderRadius.circular(20)),
                child: const Text('BETA', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '사진을 찍으면 AI가 어울리는 조합을 추천해줘요',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadArea() {
    return GestureDetector(
      onTap: _handleUpload,
      child: Container(
        height: 240,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.textDisabled, width: 2, style: BorderStyle.solid),
          boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.bluePale, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.camera_alt, color: AppColors.blue, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('피팅룸 사진 업로드', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('매장에서 옷 입은 전신 사진을 올려주세요', style: TextStyle(color: AppColors.textPlaceholder, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _UploadChip(icon: Icons.camera_alt, label: '촬영'),
                const SizedBox(width: 12),
                _UploadChip(icon: Icons.upload, label: '갤러리'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 240,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: 'https://images.unsplash.com/photo-1689044611227-3267fabaf76a?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=500&w=400&q=80',
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.background),
              errorWidget: (_, __, ___) => Container(color: AppColors.background),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x990D1B3E)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 8),
                      const Text('사진 업로드 완료', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => setState(() { _hasPhoto = false; _showResults = false; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('재업로드', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchButton() {
    return GestureDetector(
      onTap: _isAnalyzing ? null : _handleMatch,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: _isAnalyzing ? null : const LinearGradient(colors: [Color(0xFF1D4ED8), AppColors.blue]),
          color: _isAnalyzing ? const Color(0xFF93C5FD) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: _isAnalyzing ? [] : [BoxShadow(color: AppColors.blue.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _isAnalyzing
              ? [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  const Text('AI 분석 중...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ]
              : [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Text('내 옷장 옷과 매칭하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ],
        ),
      ),
    );
  }

  Widget _buildResults(SimulationResult result) {
    Color scoreBadgeColor = result.score >= 90 ? AppColors.green : result.score >= 80 ? AppColors.blue : AppColors.amber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('AI 코디 추천 결과', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            Text('${_activeSlide + 1} / ${simulationResults.length}', style: const TextStyle(color: AppColors.textPlaceholder, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: SizedBox(
                      height: 260,
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: result.fitImg,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.background),
                        errorWidget: (_, __, ___) => Container(color: AppColors.background),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: scoreBadgeColor, borderRadius: BorderRadius.circular(20)),
                      child: Text('매칭 ${result.score}%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 110,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SlideButton(icon: Icons.chevron_left, onTap: _prevSlide),
                        _SlideButton(icon: Icons.chevron_right, onTap: _nextSlide),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _ClothingChip(label: '상의', name: result.top, imgUrl: result.topImg)),
                        const SizedBox(width: 12),
                        Expanded(child: _ClothingChip(label: '하의', name: result.bottom, imgUrl: result.bottomImg)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(simulationResults.length, (i) {
            return GestureDetector(
              onTap: () => setState(() => _activeSlide = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _activeSlide ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _activeSlide ? AppColors.blue : AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBuyButton() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, AppColors.background],
            stops: [0, 0.4],
          ),
        ),
        child: GestureDetector(
          onTap: widget.onNavigateToDetail,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.navy, AppColors.navyLight]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('최저가 비교 및 구매하기', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _UploadChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SlideButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SlideButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 18),
      ),
    );
  }
}

class _ClothingChip extends StatelessWidget {
  final String label;
  final String name;
  final String imgUrl;

  const _ClothingChip({required this.label, required this.name, required this.imgUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.blueVeryPale, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 48,
              height: 56,
              child: CachedNetworkImage(
                imageUrl: imgUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.background),
                errorWidget: (_, __, ___) => Container(color: AppColors.background),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textPlaceholder, fontSize: 10)),
                Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}