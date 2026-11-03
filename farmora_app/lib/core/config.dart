import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class FirebaseConfig {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static bool get configured =>
      [projectId, apiKey, appId, senderId].every((s) => s.isNotEmpty);

  /// Android builds can also start from the native google-services.json.
  static bool get available =>
      configured || !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
  );
}
