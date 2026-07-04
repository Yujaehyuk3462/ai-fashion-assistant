import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  static final _storage = FirebaseStorage.instance;
  static const _folder = 'wardrobe_images';
  static const _fittingResultsFolder = 'fitting_results';

  static Future<String> uploadWardrobeImage(XFile xFile) async {
    final file = File(xFile.path);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('$_folder/$fileName');

    await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return ref.getDownloadURL();
  }

  static Future<void> deleteWardrobeImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (_) {
      // Storage 파일이 없어도 Firestore 삭제는 계속 진행
    }
  }

  // 캐시 키(사용자 사진 + 옷 조합의 SHA-256 해시)를 파일명으로 써서
  // 같은 조합이면 항상 같은 경로에 덮어쓰기(overwrite)되게 한다.
  static Future<String> uploadFittingResult(Uint8List bytes, String cacheKey) async {
    final ref = _storage.ref().child('$_fittingResultsFolder/$cacheKey.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}