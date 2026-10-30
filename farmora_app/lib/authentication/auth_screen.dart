import 'package:google_sign_in/google_sign_in.dart';

import 'phone_sign_in.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/repository.dart';
import '../shared/widgets.dart';

Future<void>? _googleInit;

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.completeProfile = false});
  final bool completeProfile;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      phone = TextEditingController();
  bool register = false, consent = false;
  AccountRole role = AccountRole.buyer;
  String province = provinces.first;
  @override
  void dispose() {
    for (final c in [email, password, name, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signup = register || widget.completeProfile;
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 32),
                Icon(
                  Icons.eco,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                Text(
                  'Farmora',
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connecting Farmers, Buyers & Transporters.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Text(
                  widget.completeProfile
                      ? 'Complete your account'
                      : signup
                      ? 'Get started'
                      : 'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Form(
                  key: form,
                  child: Column(
                    children: [
                      if (signup) ...[
                        for (final r in AccountRole.values)
                          Card(
                            child: ListTile(
                              leading: Icon(
                                r == AccountRole.buyer
                                    ? Icons.shopping_basket_outlined
                                    : r == AccountRole.supplier
                                    ? Icons.agriculture
                                    : Icons.local_shipping_outlined,
                              ),
                              title: Text(r.label),
                              subtitle: Text(r.description),
                              trailing: Icon(
                                role == r
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                              ),
                              onTap: () => setState(() => role = r),
                            ),
                          ),
                        const SizedBox(height: 16),
                        FormFieldInput(name, 'Full name or business name'),
                        FormFieldInput(phone, 'Phone number'),
                        DropdownButtonFormField<String>(
                          initialValue: province,
                          decoration: const InputDecoration(
                            labelText: 'Province / city',
                          ),
                          items: provinces
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (v) => province = v!,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!widget.completeProfile) ...[
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (v) =>
                              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v?.trim() ?? '')
                              ? null
                              : 'Enter a valid email address',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (v) => (v?.length ?? 0) < (signup ? 8 : 1)
                              ? 'Use at least ${signup ? 8 : 1} characters'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (signup)
                        CheckboxListTile(
                          value: consent,
                          onChanged: (v) => setState(() => consent = v!),
                          title: const Text(
                            'I accept the Terms and Privacy Policy',
                          ),
                          subtitle: TextButton(
                            onPressed: () =>
                                openScreen(context, const PolicyScreen()),
                            child: const Text('Read terms and privacy'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      AsyncAction(
                        label: signup ? 'Create account' : 'Sign in',
                        action: () async {
                          if (!form.currentState!.validate()) return;
                          if (signup && !consent) {
                            throw Exception(
                              'Please review and accept the terms and privacy policy.',
                            );
                          }
                          if (signup) {
                            if (!widget.completeProfile) {
                              await repo.auth.createUserWithEmailAndPassword(
                                email: email.text.trim(),
                                password: password.text,
                              );
                            }
                            await repo.saveProfile({
                              'name': name.text.trim(),
                              'phone': phone.text.trim(),
                              'email': repo.auth.currentUser!.email ?? '',
                              'role': role.name,
                              'location': province,
                              'termsVersion': 'draft-1',
                              'tutorialSeen': false,
                            });
                          } else {
                            await repo.auth.signInWithEmailAndPassword(
                              email: email.text.trim(),
                              password: password.text,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if (!widget.completeProfile) ...[
                  if (const bool.fromEnvironment('ENABLE_PHONE_SIGN_IN'))
                    TextButton(
                      onPressed: () => openScreen(context, const PhoneSignIn()),
                      child: const Text('Continue with phone'),
                    ),
                  if (const bool.fromEnvironment('ENABLE_GOOGLE_SIGN_IN'))
                    AsyncAction(
                      label: 'Continue with Google',
                      action: () async {
                        final provider = GoogleAuthProvider();
                        if (kIsWeb) {
                          await repo.auth.signInWithPopup(provider);
                        } else {
                          // google_sign_in must be initialized exactly once.
                          await (_googleInit ??= GoogleSignIn.instance
                              .initialize(
                                serverClientId:
                                    const String.fromEnvironment(
                                      'GOOGLE_SERVER_CLIENT_ID',
                                    ).isEmpty
                                    ? null
                                    : const String.fromEnvironment(
                                        'GOOGLE_SERVER_CLIENT_ID',
                                      ),
                              )
                              .catchError((Object e) {
                                _googleInit = null;
                                throw e;
                              }));
                          final google = await GoogleSignIn.instance
                              .authenticate();
                          await repo.auth.signInWithCredential(
                            GoogleAuthProvider.credential(
                              idToken: google.authentication.idToken,
                            ),
                          );
                        }
                      },
                    ),
                  TextButton(
                    onPressed: () => setState(() => register = !register),
                    child: Text(
                      signup
                          ? 'Already have an account? Sign in'
                          : 'New to Farmora? Get started',
                    ),
                  ),
                  if (!signup)
                    AsyncAction(
                      label: 'Reset password',
                      icon: Icons.lock_reset,
                      action: () async {
                        if (!email.text.contains('@')) {
                          throw Exception('Enter your email address first.');
                        }
                        await repo.auth.sendPasswordResetEmail(
                          email: email.text.trim(),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'If an account exists, a reset email will arrive shortly. Check your spam folder.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ] else
                  TextButton(
                    onPressed: repo.signOut,
                    child: const Text('Sign out'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Terms & privacy — development draft')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Text(
        'Farmora connects buyers, suppliers and transport providers. Listings, prices and transport estimates must be confirmed by the parties. Never submit misleading listings or misuse another person’s information.\n\nWe process account details, listings, messages and transaction records to operate the service. Conversation access is restricted to participants. Public marketplace records are visible to signed-in users.\n\nDo not upload sensitive identity documents until a private verification process is configured.\n\nThis is a development draft, not an approved launch policy. The operator must supply its legal identity, support contact, retention policy, dispute terms and applicable privacy disclosures before accepting real users.',
      ),
    ),
  );
}
