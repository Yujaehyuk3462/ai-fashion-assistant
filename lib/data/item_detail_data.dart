
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class PriceEntry {
  final String store;
  final int price;
  final bool lowest;
  final String? badge;

  const PriceEntry({
    required this.store,
    required this.price,
    required this.lowest,
    this.badge,
  });
}

class CareInstruction {
  final IconData icon;
  final String title;
  final String detail;
  final String note;
  final Color color;
  final Color bg;

  const CareInstruction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.note,
    required this.color,
    required this.bg,
  });
}

class MaterialEntry {
  final String label;
  final String value;

  const MaterialEntry({required this.label, required this.value});
}

class StitchItem {
  final String label;
  final bool ok;

  const StitchItem({required this.label, required this.ok});
}

const priceData = [
  PriceEntry(store: '지그재그', price: 79000, lowest: true, badge: '최저가'),
  PriceEntry(store: '쿠팡', price: 82000, lowest: false, badge: '빠른배송'),
  PriceEntry(store: '무신사', price: 89000, lowest: false, badge: '인기'),
  PriceEntry(store: '29CM', price: 95000, lowest: false),
];

const careInstructions = [
  CareInstruction(
    icon: Icons.water_drop,
    title: '세탁 방법',
    detail: '손세탁 권장',
    note: '울 / 섬세 코스 30°C 이하',
    color: AppColors.blue,
    bg: AppColors.bluePale,
  ),
  CareInstruction(
    icon: Icons.thermostat,
    title: '다림질',
    detail: '중간 온도',
    note: '110°C 이하, 직접 다림질 금지',
    color: AppColors.amber,
    bg: AppColors.amberPale,
  ),
  CareInstruction(
    icon: Icons.warning_rounded,
    title: '드라이클리닝',
    detail: '불가',
    note: '드라이클리닝 하지 마세요',
    color: AppColors.red,
    bg: AppColors.redPale,
  ),
  CareInstruction(
    icon: Icons.check_circle,
    title: '탈수',
    detail: '약하게',
    note: '손으로 살짝 짜거나 수건에 감싸기',
    color: AppColors.teal,
    bg: AppColors.tealPale,
  ),
];

const materialInfo = [
  MaterialEntry(label: '소재', value: '면 100% (Cotton)'),
  MaterialEntry(label: '생산국', value: '베트남 (Vietnam)'),
  MaterialEntry(label: '무게', value: '180g'),
  MaterialEntry(label: '핏', value: '슬림 핏'),
];

const stitchChecklist = [
  StitchItem(label: '솔기 마감', ok: true),
  StitchItem(label: '단추 부착 상태', ok: true),
  StitchItem(label: '목선 처리', ok: true),
  StitchItem(label: '밑단 처리', ok: false),
];