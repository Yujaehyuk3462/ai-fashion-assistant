import '../models/clothing_size.dart';
import '../models/user_profile.dart';

enum FitLevel { tight, regular, oversized }

class FitResult {
  final FitLevel level;
  final String label;
  final double easeCm; // 옷 치수(둘레 환산) - 체형 치수

  const FitResult({
    required this.level,
    required this.label,
    required this.easeCm,
  });
}

// Gemini 호출 없이 저장된 치수와 체형 프로필의 숫자만 비교하는 규칙 기반
// 예측기. 임계값은 실측 데이터가 아니라 참고용 초기값이며, 실제 옷으로
// 검증한 뒤 조정이 필요하다.
class FitPredictor {
  static const _chestTightMax = 8.0;
  static const _chestRegularMax = 20.0;
  static const _waistTightMax = 3.0;
  static const _waistRegularMax = 12.0;

  // 카테고리별로 대조 가능한 치수·체형 값이 둘 다 있을 때만 결과를 낸다.
  // 하나라도 없으면 억지로 추정하지 않고 null(예측 불가)을 반환한다.
  static FitResult? predict({
    required String category,
    required ClothingSize? size,
    required UserProfile? profile,
  }) {
    if (size == null || profile == null) return null;

    switch (category) {
      case '상의':
      case '아우터':
        final chestWidth = size.chestWidth;
        final chestCm = profile.chestCm;
        if (chestWidth == null || chestCm == null) return null;
        final ease = chestWidth * 2 - chestCm;
        return _classify(ease, _chestTightMax, _chestRegularMax, oversizedLabel: '오버핏');
      case '하의':
        final waistWidth = size.waistWidth;
        final waistCm = profile.waistCm;
        if (waistWidth == null || waistCm == null) return null;
        final ease = waistWidth * 2 - waistCm;
        return _classify(ease, _waistTightMax, _waistRegularMax, oversizedLabel: '루즈');
      default:
        return null;
    }
  }

  static FitResult _classify(
    double ease,
    double tightMax,
    double regularMax, {
    required String oversizedLabel,
  }) {
    if (ease < tightMax) {
      return FitResult(level: FitLevel.tight, label: '타이트', easeCm: ease);
    }
    if (ease <= regularMax) {
      return FitResult(level: FitLevel.regular, label: '적당함', easeCm: ease);
    }
    return FitResult(level: FitLevel.oversized, label: oversizedLabel, easeCm: ease);
  }
}
