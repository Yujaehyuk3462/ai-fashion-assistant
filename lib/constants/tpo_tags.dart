import 'package:flutter/material.dart';
import 'app_colors.dart';

// 착장 캘린더의 TPO(Time·Place·Occasion) 태그 정의. 라벨/아이콘/색상에 더해
// formalityHint를 함께 둔다 — 이후 에이전트가 "이 날 일정은 어느 격식인가"를
// 옷장 매칭(OutfitMatcher의 격식 궁합)에 연결할 때 그대로 쓰는 매핑이다.
class TpoTag {
  final String label;
  final IconData icon;
  final Color color;
  final String formalityHint; // '캐주얼' | '세미포멀' | '포멀' — OutfitMatcher와 동일 어휘

  const TpoTag({
    required this.label,
    required this.icon,
    required this.color,
    required this.formalityHint,
  });
}

class TpoTags {
  static const all = <TpoTag>[
    TpoTag(label: '출근', icon: Icons.work_outline, color: AppColors.navy, formalityHint: '세미포멀'),
    TpoTag(label: '데이트', icon: Icons.favorite_border, color: AppColors.red, formalityHint: '세미포멀'),
    TpoTag(label: '여행', icon: Icons.flight_takeoff, color: AppColors.teal, formalityHint: '캐주얼'),
    TpoTag(label: '운동', icon: Icons.fitness_center, color: AppColors.green, formalityHint: '캐주얼'),
    TpoTag(label: '모임', icon: Icons.groups_outlined, color: AppColors.purple, formalityHint: '세미포멀'),
    TpoTag(label: '일상', icon: Icons.wb_sunny_outlined, color: AppColors.amber, formalityHint: '캐주얼'),
  ];

  // 라벨로 태그를 찾는다. 없으면(레거시/삭제된 태그) '일상'으로 폴백해
  // 화면이 아이콘/색상 null로 깨지지 않게 한다.
  static TpoTag byLabel(String label) =>
      all.firstWhere((t) => t.label == label, orElse: () => all.last);

  static const labels = ['출근', '데이트', '여행', '운동', '모임', '일상'];
}
