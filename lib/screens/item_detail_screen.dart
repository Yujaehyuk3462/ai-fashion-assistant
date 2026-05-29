import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';
import '../data/item_detail_data.dart';

final _maxPrice = priceData.map((d) => d.price).reduce((a, b) => a > b ? a : b);

class ItemDetailScreen extends StatelessWidget {
  final VoidCallback onBack;

  const ItemDetailScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildHeroPrice(),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: '가격 비교',
                    child: _buildPriceComparison(),
                  ),
                  const SizedBox(height: 16),
                  _buildBuyButton(),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: '소재 정보',
                    child: _buildMaterialInfo(),
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: '세탁 & 관리 방법',
                    child: _buildCareInstructions(),
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: '박음질 상태 체크',
                    child: _buildStitchChecklist(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('슬림 청바지', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              Text('리바이스 511 · 블루', style: TextStyle(color: AppColors.textPlaceholder, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPrice() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
              child: SizedBox(
                width: 130,
                height: 170,
                child: CachedNetworkImage(
                  imageUrl: 'https://images.unsplash.com/photo-1714143136372-ddaf8b606da7?crop=entropy&cs=tinysrgb&fit=crop&fm=jpg&h=340&w=260&q=80',
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.background),
                  errorWidget: (_, __, ___) => Container(color: AppColors.background),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('현재 최저가', style: TextStyle(color: AppColors.textPlaceholder, fontSize: 11)),
                    const Text('₩79,000', style: TextStyle(color: AppColors.red, fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
                    const Text('지그재그 기준', style: TextStyle(color: AppColors.textPlaceholder, fontSize: 11)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                          child: const Icon(Icons.check, color: AppColors.greenDark, size: 10),
                        ),
                        const SizedBox(width: 4),
                        const Text('16,000원 절약 가능', style: TextStyle(color: AppColors.greenDark, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPriceComparison() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: priceData.map((item) {
          final barWidth = item.price / _maxPrice;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(item.store, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    if (item.badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.lowest ? const Color(0xFFDCFCE7) : AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          item.badge!,
                          style: TextStyle(color: item.lowest ? AppColors.greenDark : AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '₩${item.price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                      style: TextStyle(
                        color: item.lowest ? AppColors.red : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: item.lowest ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: barWidth,
                    minHeight: 8,
                    backgroundColor: AppColors.background,
                    valueColor: AlwaysStoppedAnimation(item.lowest ? AppColors.green : AppColors.blue),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBuyButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.red, Color(0xFFDC2626)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.red.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.open_in_new, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('지그재그에서 구매하기 · ₩79,000', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2,
        children: materialInfo.map((info) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.blueVeryPale, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(info.label, style: const TextStyle(color: AppColors.textPlaceholder, fontSize: 11)),
                const SizedBox(height: 2),
                Text(info.value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCareInstructions() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: careInstructions.map((instr) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: instr.bg, borderRadius: BorderRadius.circular(12)),
                child: Icon(instr.icon, color: instr.color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(instr.title, style: const TextStyle(color: AppColors.textPlaceholder, fontSize: 10)),
              Text(instr.detail, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(instr.note, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, height: 1.4)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStitchChecklist() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          ...stitchChecklist.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: s.ok ? AppColors.greenPale : AppColors.redPale,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    s.ok ? Icons.check : Icons.close,
                    color: s.ok ? AppColors.greenDark : AppColors.red,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500))),
                Text(
                  s.ok ? '양호' : '확인 필요',
                  style: TextStyle(color: s.ok ? AppColors.greenDark : AppColors.red, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          )),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.amberPale, borderRadius: BorderRadius.circular(12)),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.amber, size: 14),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '밑단 처리 상태를 구매 전 직접 확인해 보세요. 착용 시 실밥이 나올 수 있어요.',
                    style: TextStyle(color: Color(0xFF92400E), fontSize: 11, height: 1.5),
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