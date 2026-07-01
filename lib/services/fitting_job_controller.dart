import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/clothing_attributes.dart';
import '../models/wardrobe_item.dart';
import 'firestore_service.dart';
import 'gemini_api_exception.dart';
import 'gemini_service.dart';

// 화면(State)이 아니라 AppShell 레벨에서 보관되는 컨트롤러.
// 탭을 이동하거나 위젯이 dispose되어도 진행 중인 Future와 그 결과는
// 이 인스턴스에 남아있기 때문에 작업이 끊기지 않는다.
class FittingJobController extends ChangeNotifier {
  bool isAnalyzing = false;
  bool isGeneratingFitting = false;

  String? analysisResult;
  String? analysisError;

  Uint8List? fittingImage;
  String? fittingError;

  bool get isBusy => isAnalyzing || isGeneratingFitting;

  Future<void> analyze({
    required List<WardrobeItem> clothingItems,
    required WardrobeItem? userPhoto,
  }) async {
    if (isBusy || clothingItems.isEmpty) return;

    isAnalyzing = true;
    analysisResult = null;
    analysisError = null;
    notifyListeners();

    try {
      final itemsWithAttributes = await _resolveAttributes(clothingItems);
      analysisResult = await _withRetry(
        () => GeminiService.analyzeOutfitFromAttributes(
          items: itemsWithAttributes,
          userPhotoUrl: userPhoto?.imageUrl,
        ),
      );
    } catch (e) {
      analysisError = e.toString();
    } finally {
      isAnalyzing = false;
      notifyListeners();
    }
  }

  // 등록 시점에 이미 속성이 캐싱된 아이템은 그대로 쓰고, 아직 없는
  // 레거시 아이템만 병렬로 추출한 뒤 다음 번을 위해 Firestore에 백필한다.
  // 추출 호출 자체도 타임아웃/일시적 오류에 재시도를 적용한다.
  static Future<List<({String category, ClothingAttributes attributes})>>
      _resolveAttributes(List<WardrobeItem> items) {
    return Future.wait(items.map((item) async {
      final cached = item.attributes;
      if (cached != null) return (category: item.category, attributes: cached);

      final extracted = await _withRetry(
        () => GeminiService.extractAttributes(
          imageUrl: item.imageUrl,
          category: item.category,
        ),
      );
      unawaited(FirestoreService.updateWardrobeAttributes(item.id, extracted));
      return (category: item.category, attributes: extracted);
    }));
  }

  // 응답 생성이 일시적으로 느려 타임아웃났거나, Gemini가 일시적으로
  // 과부하(503)·요청 급증(429) 상태인 경우 곧바로 실패시키지 않고
  // 한 번 더 시도해본다. 두 번째도 같은 상황이면 그대로 실패로 처리한다.
  static Future<T> _withRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on TimeoutException {
      return await action();
    } on GeminiApiException catch (e) {
      if (!e.isRetryable) rethrow;
      return await action();
    }
  }

  Future<void> generateFitting({
    required WardrobeItem userPhoto,
    required List<WardrobeItem> clothingItems,
  }) async {
    if (isBusy || clothingItems.isEmpty) return;

    isGeneratingFitting = true;
    fittingImage = null;
    fittingError = null;
    notifyListeners();

    try {
      fittingImage = await _withRetry(
        () => GeminiService.generateFittingImage(
          userPhotoUrl: userPhoto.imageUrl,
          clothingImageUrls: clothingItems.map((i) => i.imageUrl).toList(),
          clothingNames: clothingItems.map((i) => i.category).toList(),
        ),
      );
    } catch (e) {
      fittingError = e.toString();
    } finally {
      isGeneratingFitting = false;
      notifyListeners();
    }
  }
}
