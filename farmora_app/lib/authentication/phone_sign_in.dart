import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../shared/widgets.dart';

class PhoneSignIn extends StatefulWidget {
  const PhoneSignIn({super.key});
  @override
  State<PhoneSignIn> createState() => _PhoneSignInState();
}

class _PhoneSignInState extends State<PhoneSignIn> {
  final phone = TextEditingController(), code = TextEditingController();
  String? verificationId;
  ConfirmationResult? confirmation;
  bool sent = false;
  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sign in with phone')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Enter your number with its country code, for example +263. SMS availability depends on your provider and Firebase configuration.',
        ),
        const SizedBox(height: 16),
        FormFieldInput(phone, 'Phone number'),
        AsyncAction(
          label: sent ? 'Resend SMS' : 'Send SMS code',
          action: () async {
            if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone.text.trim())) {
              throw Exception('Enter a valid international phone number.');
            }
            if (kIsWeb) {
              confirmation = await FirebaseAuth.instance.signInWithPhoneNumber(
                phone.text.trim(),
              );
              if (mounted) setState(() => sent = true);
            } else {
              await FirebaseAuth.instance.verifyPhoneNumber(
                phoneNumber: phone.text.trim(),
                verificationCompleted: (credential) async {
                  await FirebaseAuth.instance.signInWithCredential(credential);
                  if (context.mounted) Navigator.pop(context);
                },
                verificationFailed: (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(error))),
                    );
                  }
                },
                codeSent: (id, token) {
                  if (mounted) {
                    setState(() {
                      verificationId = id;
                      sent = true;
                    });
                  }
                },
                codeAutoRetrievalTimeout: (id) {
                  verificationId = id;
                },
              );
            }
          },
        ),
        if (sent) ...[
          const SizedBox(height: 16),
          FormFieldInput(code, 'SMS code'),
          AsyncAction(
            label: 'Verify and continue',
            action: () async {
              if (code.text.trim().length != 6) {
                throw Exception('Enter the six-digit SMS code.');
              }
              if (kIsWeb) {
                await confirmation!.confirm(code.text.trim());
              } else {
                await FirebaseAuth.instance.signInWithCredential(
                  PhoneAuthProvider.credential(
                    verificationId: verificationId!,
                    smsCode: code.text.trim(),
                  ),
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ],
    ),
  );
}
