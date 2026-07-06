import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';
import '../models/wardrobe_item.dart';
import '../services/firestore_service.dart';

// 보드에 배치되는 슬롯 정의. key는 화면 내부 상태 식별자, category는
// wardrobeStream을 필터링할 때 쓰는 실제 등록 카테고리 — 모자/가방/시계는
// 전부 "액세서리" 카테고리 안에서 subCategory로 구분해서 고른다(등록
// 카테고리 자체를 3개로 쪼갤 필요는 없다). subCategory가 null인 슬롯은
// 해당 카테고리 전체에서 고르면 된다는 뜻.
const _boardSlots = [
  (key: '아우터', label: '아우터', category: '아우터', subCategory: null),
  (key: '상의', label: '상의', category: '상의', subCategory: null),
  (key: '하의', label: '하의', category: '하의', subCategory: null),
  (key: '신발', label: '신발', category: '신발', subCategory: null),
  (key: '모자', label: '모자', category: '액세서리', subCategory: '모자'),
  (key: '가방', label: '가방', category: '액세서리', subCategory: '가방'),
  (key: '시계', label: '시계', category: '액세서리', subCategory: '시계'),
  (key: '팔찌', label: '팔찌', category: '액세서리', subCategory: '팔찌'),
];

// 무신사 룩북 스타일 플랫레이 배치 좌표 — 전부 보드 크기(가로/세로) 대비
// 비율(0~1)이며 실측 옷을 넣어보며 조정하기 쉽도록 한곳에 모아둔다.
class _BoardLayout {
  const _BoardLayout._();

  static const double aspectRatio = 3 / 4;
  static const Color backgroundColor = Color(0xFF2A2A2A);

  // 상의 (아우터 없을 때 — 보드 상단 중앙). 박스 높이를 넉넉히 줘야
  // BoxFit.contain으로 렌더링될 때 실제 이미지가 목표 폭(55~60%)까지
  // 커질 여유가 생긴다 — 높이가 좁으면 세로로 긴 사진일수록 폭이
  // 의도보다 훨씬 작게 그려진다. (레퍼런스 대비 이미 적정 수준 — 유지)
  static const double topLeft = 0.19;
  static const double topTop = 0.19;
  static const double topWidth = 0.55;
  static const double topHeight = 0.42;
  static const double topRotationDeg = 0.0;

  // 상의 (아우터 있을 때 — 아우터 오른쪽 뒤로 살짝 걸치게)
  static const double topWithOuterLeft = 0.36;
  static const double topWithOuterTop = 0.19;
  static const double topWithOuterWidth = 0.46;

  // 아우터 (상의 왼쪽, 상의보다 앞에 그려짐)
  static const double outerLeft = 0.04;
  static const double outerTop = 0.03;
  static const double outerWidth = 0.50;
  static const double outerHeight = 0.38;

  // 하의 — 상의 밑단과 15~20%가량 겹치도록 top을 당겨서 배치.
  // 겹침이 실제로 보이려면 상의는 박스 하단에, 하의는 박스 상단에
  // 붙여 그려야 한다(각 슬롯의 alignment 참고). (유지)
  static const double bottomLeft = 0.205;
  static const double bottomTop = 0.48;
  static const double bottomWidth = 0.52;
  static const double bottomHeight = 0.42;
  static const double bottomRotationDeg = 0.0;

  // 신발 — 하의 밑단과 살짝 겹치도록 오른쪽 아래에 배치, 시계방향으로 기울여
  // 캐주얼하게 벗어둔 느낌을 낸다.
  static const double shoesLeft = 0.51;
  static const double shoesTop = 0.76;
  static const double shoesWidth = 0.44;
  static const double shoesHeight = 0.24;
  static const double shoesRotationDeg = 0.0;

  // 액세서리 — 모자(상의 바로 위, 중앙) / 가방(오른쪽에 세로로 길게,
  // 상의 중간~하의 중간 높이) / 시계(왼쪽 상의 팔 높이) / 팔찌(시계 위쪽)
  static const double hatLeft = 0.335;
  static const double hatTop = 0.01;
  static const double hatWidth = 0.26;
  static const double hatHeight = 0.17;
  static const double hatRotationDeg = -5.0;

  static const double bagLeft = 0.58;
  static const double bagTop = 0.30;
  static const double bagWidth = 0.38;
  static const double bagHeight = 0.40;
  static const double bagRotationDeg = 3.0;

  static const double watchLeft = 0.10;
  static const double watchTop = 0.33;
  static const double watchWidth = 0.12;
  static const double watchHeight = 0.09;
  static const double watchRotationDeg = 15.0;

  static const double braceletLeft = 0.09;
  static const double braceletTop = 0.22;
  static const double braceletWidth = 0.11;
  static const double braceletHeight = 0.07;
  static const double braceletRotationDeg = -10.0;
}

class CoordBoardScreen extends StatefulWidget {
  const CoordBoardScreen({super.key});

  @override
  State<CoordBoardScreen> createState() => _CoordBoardScreenState();
}

class _CoordBoardScreenState extends State<CoordBoardScreen> {
  final Map<String, WardrobeItem?> _slots = {
    for (final s in _boardSlots) s.key: null,
  };

  void _pickForSlot(String slotKey) {
    final slot = _boardSlots.firstWhere((s) => s.key == slotKey);
    showModalBottomSheet<WardrobeItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BoardItemPickerSheet(
        category: slot.category,
        subCategory: slot.subCategory,
        slotLabel: slot.label,
      ),
    ).then((selected) {
      if (selected != null && mounted) {
        setState(() => _slots[slotKey] = selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildBoard(),
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
      child: Row(
        children: [
          const Icon(Icons.dashboard_customize_outlined, color: AppColors.navy, size: 22),
          const SizedBox(width: 8),
          const Text('코디 보드',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ── 보드 본체: Stack + Positioned로 플랫레이 배치 ─────────
  Widget _buildBoard() {
    final hasOuter = _slots['아우터'] != null;

    return AspectRatio(
      aspectRatio: _BoardLayout.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: _BoardLayout.backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return Stack(
              children: [
                // z-order (뒤→앞): 하의 → 상의 → 아우터 → 모자 → 가방 → 시계 → 팔찌 → 신발
                // 하의 — 박스 상단에 붙여 그려서 상의 밑단과 실제로 겹쳐 보이게 한다.
                _buildSlot(
                  slotKey: '하의',
                  left: w * _BoardLayout.bottomLeft,
                  top: h * _BoardLayout.bottomTop,
                  width: w * _BoardLayout.bottomWidth,
                  height: h * _BoardLayout.bottomHeight,
                  alignment: Alignment.topCenter,
                  rotationDeg: _BoardLayout.bottomRotationDeg,
                ),
                // 상의 — 아우터가 있으면 오른쪽으로 밀려 아우터 뒤에 걸친다.
                // 박스 하단에 붙여 그려서 하의와 겹치는 부분이 실제로 보이게 한다.
                _buildSlot(
                  slotKey: '상의',
                  left: w * (hasOuter ? _BoardLayout.topWithOuterLeft : _BoardLayout.topLeft),
                  top: h * (hasOuter ? _BoardLayout.topWithOuterTop : _BoardLayout.topTop),
                  width: w * (hasOuter ? _BoardLayout.topWithOuterWidth : _BoardLayout.topWidth),
                  height: h * _BoardLayout.topHeight,
                  alignment: Alignment.bottomCenter,
                  rotationDeg: _BoardLayout.topRotationDeg,
                ),
                // 아우터 — 상의보다 나중에 그려서 앞으로 나오게 한다.
                if (hasOuter)
                  _buildSlot(
                    slotKey: '아우터',
                    left: w * _BoardLayout.outerLeft,
                    top: h * _BoardLayout.outerTop,
                    width: w * _BoardLayout.outerWidth,
                    height: h * _BoardLayout.outerHeight,
                  ),
                // 모자
                _buildSlot(
                  slotKey: '모자',
                  left: w * _BoardLayout.hatLeft,
                  top: h * _BoardLayout.hatTop,
                  width: w * _BoardLayout.hatWidth,
                  height: h * _BoardLayout.hatHeight,
                  rotationDeg: _BoardLayout.hatRotationDeg,
                ),
                // 가방 — 오른쪽 중단을 크게 채움
                _buildSlot(
                  slotKey: '가방',
                  left: w * _BoardLayout.bagLeft,
                  top: h * _BoardLayout.bagTop,
                  width: w * _BoardLayout.bagWidth,
                  height: h * _BoardLayout.bagHeight,
                  rotationDeg: _BoardLayout.bagRotationDeg,
                ),
                // 시계
                _buildSlot(
                  slotKey: '시계',
                  left: w * _BoardLayout.watchLeft,
                  top: h * _BoardLayout.watchTop,
                  width: w * _BoardLayout.watchWidth,
                  height: h * _BoardLayout.watchHeight,
                  rotationDeg: _BoardLayout.watchRotationDeg,
                ),
                // 팔찌 — 시계 바로 위
                _buildSlot(
                  slotKey: '팔찌',
                  left: w * _BoardLayout.braceletLeft,
                  top: h * _BoardLayout.braceletTop,
                  width: w * _BoardLayout.braceletWidth,
                  height: h * _BoardLayout.braceletHeight,
                  rotationDeg: _BoardLayout.braceletRotationDeg,
                ),
                // 신발 — 하의 밑단과 겹치게, 맨 앞
                _buildSlot(
                  slotKey: '신발',
                  left: w * _BoardLayout.shoesLeft,
                  top: h * _BoardLayout.shoesTop,
                  width: w * _BoardLayout.shoesWidth,
                  height: h * _BoardLayout.shoesHeight,
                  rotationDeg: _BoardLayout.shoesRotationDeg,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSlot({
    required String slotKey,
    required double left,
    required double top,
    required double width,
    required double height,
    double rotationDeg = 0,
    Alignment alignment = Alignment.center,
  }) {
    final item = _slots[slotKey];
    Widget content = SizedBox(
      width: width,
      height: height,
      child: item != null
          ? CachedNetworkImage(
              imageUrl: item.cutoutImageUrl ?? item.imageUrl,
              fit: BoxFit.contain,
              alignment: alignment,
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.image_outlined, color: Colors.white24, size: 28),
            )
          : _EmptySlotPlaceholder(label: slotKey),
    );

    if (rotationDeg != 0) {
      content = Transform.rotate(angle: rotationDeg * math.pi / 180, child: content);
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: () => _pickForSlot(slotKey),
        child: content,
      ),
    );
  }
}

// ── 빈 슬롯 표시: 점선 테두리 + 안내 텍스트 ──────────────
class _EmptySlotPlaceholder extends StatelessWidget {
  final String label;

  const _EmptySlotPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Center(
        // 시계처럼 매우 작은 슬롯에서도 두 줄 안내 문구가 넘치지 않도록
        // 박스 크기에 맞춰 통째로 축소한다.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              const Text('탭해서\n선택',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  static const _dashWidth = 6.0;
  static const _dashSpace = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

// ── 슬롯 탭 시 뜨는 가로 스크롤 아이템 선택 바텀시트 ─────
class _BoardItemPickerSheet extends StatelessWidget {
  final String category;
  final String? subCategory;
  final String slotLabel;

  const _BoardItemPickerSheet({
    required this.category,
    required this.subCategory,
    required this.slotLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 0, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Column(
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
                  const SizedBox(height: 16),
                  Text('$slotLabel 선택',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4)),
                  const SizedBox(height: 4),
                  Text('등록된 $category 아이템 중에서 골라보세요',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: StreamBuilder<List<WardrobeItem>>(
                stream: FirestoreService.wardrobeStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: AppColors.navy, strokeWidth: 2));
                  }
                  // subCategory가 지정된 슬롯(모자/가방/시계)이면 해당 타입과
                  // 정확히 일치하거나, 아직 세부 분류가 없는(null) 레거시
                  // 아이템까지 폴백으로 포함한다 — 등록 당시 미분류였다고
                  // 특정 슬롯에서 영영 안 보이면 안 되니까.
                  final items = (snapshot.data ?? [])
                      .where((i) =>
                          i.category == category &&
                          (subCategory == null ||
                              i.subCategory == subCategory ||
                              i.subCategory == null))
                      .toList();
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Text('등록된 $category 아이템이 없습니다',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, item),
                        child: Container(
                          width: 110,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: CachedNetworkImage(
                              imageUrl: item.cutoutImageUrl ?? item.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: AppColors.background),
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.background,
                                child: const Icon(Icons.image_outlined,
                                    color: AppColors.textDisabled),
                              ),
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
      ),
    );
  }
}
