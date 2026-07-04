import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/clothing_attributes.dart';
import '../models/user_profile.dart';
import '../models/wardrobe_item.dart';
import 'firestore_service.dart';
import 'gemini_api_exception.dart';
import 'gemini_service.dart';
import 'storage_service.dart';

// 화면(State)이 아니라 AppShell 레벨에서 보관되는 컨트롤러.
// 탭을 이동하거나 위젯이 dispose되어도 진행 중인 Future와 그 결과는
// 이 인스턴스에 남아있기 때문에 작업이 끊기지 않는다.
class FittingJobController extends ChangeNotifier {
  bool isAnalyzing = false;
  bool isGeneratingFitting = false;

  String? analysisResult;
  String? analysisError;

  Uint8List? fittingImage;
  String? fittingImageUrl; // 캐시에서 가져온 결과 (Storage URL, bytes 아님)
  bool isFittingFromCache = false;
  String? fittingError;

  bool get isBusy => isAnalyzing || isGeneratingFitting;

  Future<void> analyze({
    required List<WardrobeItem> clothingItems,
    required WardrobeItem? userPhoto,
    UserProfile? userProfile,
  }) async {
    if (isBusy || clothingItems.isEmpty) return;

    isAnalyzing = true;
    analysisResult = null;
    analysisError = null;
    notifyListeners();

    final debugT0 = DateTime.now();
    try {
      final itemsWithAttributes = await _resolveAttributes(clothingItems);
      final debugT1 = DateTime.now();
      debugPrint('[TIMING] 1) 속성 준비: ${debugT1.difference(debugT0).inMilliseconds}ms');

      try {
        final buffer = StringBuffer();
        DateTime? debugFirstChunkAt;
        await for (final chunk in GeminiService.analyzeOutfitFromAttributesStream(
          items: itemsWithAttributes,
          userPhotoUrl: userPhoto?.imageUrl,
          userProfile: userProfile,
        )) {
          debugFirstChunkAt ??= DateTime.now();
          buffer.write(chunk);
          analysisResult = buffer.toString();
          notifyListeners();
        }
        final debugT2 = DateTime.now();
        debugPrint('[TIMING] 2) 첫 응답까지: '
            '${(debugFirstChunkAt ?? debugT2).difference(debugT1).inMilliseconds}ms');
        debugPrint('[TIMING] 3) 전체 생성 완료: '
            '${debugT2.difference(debugT1).inMilliseconds}ms '
            '(총합 ${debugT2.difference(debugT0).inMilliseconds}ms)');
        if (buffer.isEmpty) throw Exception('스트리밍 응답이 비어 있습니다.');
      } catch (_) {
        // 스트리밍이 중간에 끊기거나 실패하면 부분 텍스트는 버리고
        // 기존의 안정적인 전체 호출 + 재시도 경로로 폴백한다.
        analysisResult = null;
        notifyListeners();
        analysisResult = await _withRetry(
          () => GeminiService.analyzeOutfitFromAttributes(
            items: itemsWithAttributes,
            userPhotoUrl: userPhoto?.imageUrl,
            userProfile: userProfile,
          ),
        );
      }
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
    bool forceRegenerate = false,
  }) async {
    if (isBusy || clothingItems.isEmpty) return;

    isGeneratingFitting = true;
    fittingImage = null;
    fittingImageUrl = null;
    isFittingFromCache = false;
    fittingError = null;
    notifyListeners();

    try {
      final cacheKey = _buildFittingCacheKey(userPhoto, clothingItems);

      if (!forceRegenerate) {
        final cachedUrl = await _getCachedFittingImageUrlSilently(cacheKey);
        if (cachedUrl != null) {
          fittingImageUrl = cachedUrl;
          isFittingFromCache = true;
          return;
        }
      }

      final bytes = await _withRetry(
        () => GeminiService.generateFittingImage(
          userPhotoUrl: userPhoto.imageUrl,
          clothingImageUrls: clothingItems.map((i) => i.imageUrl).toList(),
          clothingNames: clothingItems.map((i) => i.category).toList(),
        ),
      );
      fittingImage = bytes;

      // 캐시 저장은 이미 화면에 이미지가 표시된 뒤의 부가 작업이라
      // 실패해도 조용히 무시한다 (_resolveAttributes의 백필과 동일 패턴).
      unawaited(_cacheFittingResultSilently(cacheKey, bytes));
    } catch (e) {
      fittingError = e.toString();
    } finally {
      isGeneratingFitting = false;
      notifyListeners();
    }
  }

  // 사용자 사진 ID + 정렬된 옷 ID들을 합쳐 SHA-256 해시로 만든다.
  // 옷 선택 순서가 달라도(하의→상의 vs 상의→하의) 같은 조합이면 같은 키가 나오도록
  // 정렬을 거친다.
  static String _buildFittingCacheKey(
    WardrobeItem userPhoto,
    List<WardrobeItem> clothingItems,
  ) {
    final sortedClothingIds = clothingItems.map((i) => i.id).toList()..sort();
    final raw = '${userPhoto.id}:${sortedClothingIds.join(',')}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static Future<void> _cacheFittingResultSilently(String cacheKey, Uint8List bytes) async {
    try {
      final imageUrl = await StorageService.uploadFittingResult(bytes, cacheKey);
      await FirestoreService.cacheFittingResult(cacheKey, imageUrl);
    } catch (_) {
      // 캐시 저장 실패는 무시 — 사용자에게는 이미 방금 생성된 이미지가 표시된 상태다.
    }
  }

  // 캐시 조회는 어디까지나 최적화이므로, 권한/네트워크 문제로 실패해도
  // 캐시 미스로 취급하고 정상 생성 경로로 넘어간다 — 여기서 예외가 새어나가면
  // 캐시 기능 하나 때문에 가상 피팅 자체가 실패해버린다.
  static Future<String?> _getCachedFittingImageUrlSilently(String cacheKey) async {
    try {
      return await FirestoreService.getCachedFittingImageUrl(cacheKey);
    } catch (_) {
      return null;
    }
  }
}
