import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

final repositoryProvider = Provider((ref) => FarmoraRepository());
final authProvider = StreamProvider(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);
final profileProvider = StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>(
  (ref) {
    final user = ref.watch(authProvider).value;
    if (user == null) return Stream.value(null);
    return ref
        .read(repositoryProvider)
        .db
        .collection('users')
        .doc(user.uid)
        .snapshots();
  },
);

class FarmoraRepository {
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  String get uid => auth.currentUser!.uid;
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await FirebaseFunctions.instanceFor(region: 'africa-south1')
        .httpsCallable(name)
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> saveProfile(Map<String, dynamic> data) =>
      db.collection('users').doc(uid).set({
        ...data,
        'verified': false,
        'suspended': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
  Future<String> upload(XFile image, String folder) async {
    final bytes = await image.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw Exception('Choose an image smaller than 5 MB.');
    }
    final target = FirebaseStorage.instance.ref(
      '$folder/$uid/${db.collection('uploads').doc().id}.jpg',
    );
    await target.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return target.getDownloadURL();
  }

  Future<void> publish(
    String collection,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final target = id == null
        ? db.collection(collection).doc()
        : db.collection(collection).doc(id);
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(target);
      transaction.set(target, {
        ...data,
        if (!existing.exists) 'ownerId': uid,
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> signOut() async {
    // Remove this device from the current account before ending its session.
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 5),
      );
      if (token != null && auth.currentUser != null) {
        await db
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(token)
            .delete();
      }
    } catch (_) {
      await FirebaseMessaging.instance.deleteToken().catchError((_) {});
    }
    await auth.signOut();
  }

  Future<void> sendMessage(String id, String text) async {
    await call('sendMessage', {'conversationId': id, 'text': text.trim()});
  }
}
