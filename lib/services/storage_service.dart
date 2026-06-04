import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  static final _storage = FirebaseStorage.instance;
  static const _folder = 'wardrobe_images';

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
}