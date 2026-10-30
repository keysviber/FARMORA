import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'core/app.dart';
import 'core/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  if (FirebaseConfig.configured) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      await initializeServices();
    } catch (_) {
      error =
          'Firebase could not start. Check your configuration and connection.';
    }
  }
  runApp(ProviderScope(child: FarmoraApp(startupError: error)));
}
