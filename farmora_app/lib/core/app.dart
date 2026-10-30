import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'repository.dart';
import '../authentication/auth_screen.dart';
import '../marketplace/home.dart';
import '../shared/widgets.dart';

class FarmoraApp extends StatelessWidget {
  const FarmoraApp({super.key, this.startupError});
  final String? startupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Farmora',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    home: !FirebaseConfig.configured || startupError != null
        ? Scaffold(
            body: EmptyState(
              'Welcome to Farmora',
              startupError ?? 'Connecting Farmers, Buyers & Transporters.\n\nConnect Firebase to enable secure accounts and the live marketplace. See README.md for setup.',
            ),
          )
        : const SessionGate(),
  );
  ThemeData theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff237548),
      brightness: brightness,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(authProvider)
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) =>
            Scaffold(body: EmptyState('Unable to sign in', friendlyError(e))),
        data: (user) {
          if (user == null) return const AuthScreen();
          return ref
              .watch(profileProvider)
              .when(
                loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Scaffold(
                  body: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      EmptyState('Unable to load profile', friendlyError(e)),
                      TextButton(
                        onPressed: () => ref.invalidate(profileProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (snapshot) {
                  if (snapshot == null || !snapshot.exists) {
                    return const AuthScreen(completeProfile: true);
                  }
                  final profile = snapshot.data()!;
                  if (profile['suspended'] == true) {
                    return Scaffold(
                      body: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Your account is suspended. Contact support.',
                            ),
                            TextButton(
                              onPressed: () =>
                                  ref.read(repositoryProvider).signOut(),
                              child: const Text('Sign out'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return MarketplaceShell(profile: profile);
                },
              );
        },
      );
}
