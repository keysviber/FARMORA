import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'core/app.dart';
import 'core/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  var ready = false;
  if (FirebaseConfig.available) {
    try {
      // Dart-defined options win; otherwise Android reads google-services.json.
      await Firebase.initializeApp(
        options: FirebaseConfig.configured ? FirebaseConfig.options : null,
      );
      await initializeServices();
      ready = true;
    } catch (e) {
      debugPrint('Firebase startup failed: $e');
      error =
          'Firebase could not start. Check your configuration and connection.';
    }
  }
  runApp(
    ProviderScope(
      child: FarmoraApp(firebaseReady: ready, startupError: error),
    ),
  );
}
