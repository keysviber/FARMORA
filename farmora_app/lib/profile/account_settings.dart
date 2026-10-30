import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';
import '../shared/widgets.dart';

class AccountSettings extends ConsumerStatefulWidget {
  const AccountSettings({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  ConsumerState<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends ConsumerState<AccountSettings> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.profile['name']),
      phone = TextEditingController(text: widget.profile['phone']),
      location = TextEditingController(text: widget.profile['location']);
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account details')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FormFieldInput(name, 'Name / business'),
          FormFieldInput(phone, 'Phone'),
          FormFieldInput(location, 'Province / city'),
          AsyncAction(
            label: 'Save details',
            action: () async {
              if (!form.currentState!.validate()) return;
              await ref.read(repositoryProvider).call('updateProfile', {
                'name': name.text.trim(),
                'phone': phone.text.trim(),
                'location': location.text.trim(),
              });
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Account deletion removes your login, profile, listings, saved products and device registrations. Transaction and conversation records are retained for other participants and dispute handling. Active obligations must be resolved first.',
          ),
          AsyncAction(
            label: 'Delete my account',
            icon: Icons.delete_forever,
            action: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Permanently delete your account?'),
                  content: const Text(
                    'This queues permanent deletion and signs you out. You may be asked to sign in again first.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Delete account'),
                    ),
                  ],
                ),
              );
              if (yes != true) return;
              final repo = ref.read(repositoryProvider);
              await repo.call('deleteAccount', {});
              await repo.signOut();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});
  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final message = TextEditingController();
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & support')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Describe the issue and include the relevant order ID. Support requests are private to the platform administrators. This is not a live or emergency service.',
        ),
        const SizedBox(height: 16),
        FormFieldInput(message, 'How can we help?', lines: 5),
        AsyncAction(
          label: 'Send support request',
          action: () async {
            if (message.text.trim().isEmpty) {
              throw Exception('Describe the issue first.');
            }
            await ref.read(repositoryProvider).call('contactSupport', {
              'message': message.text.trim(),
            });
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Support request submitted.')),
              );
              Navigator.pop(context);
            }
          },
        ),
      ],
    ),
  );
}

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({
    super.key,
    required this.orderId,
    required this.hasTransporter,
  });
  final String orderId;
  final bool hasTransporter;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final comment = TextEditingController();
  int rating = 5;
  String target = 'supplier';
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rate your transaction')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          initialValue: target,
          items: [
            const DropdownMenuItem(value: 'supplier', child: Text('Supplier')),
            if (widget.hasTransporter)
              const DropdownMenuItem(
                value: 'transporter',
                child: Text('Transporter'),
              ),
          ],
          onChanged: (v) => setState(() => target = v!),
        ),
        DropdownButtonFormField<int>(
          initialValue: rating,
          items: [1, 2, 3, 4, 5]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v stars')))
              .toList(),
          onChanged: (v) => rating = v!,
        ),
        const SizedBox(height: 16),
        FormFieldInput(comment, 'Your experience', lines: 4),
        AsyncAction(
          label: 'Publish review',
          action: () async {
            if (comment.text.trim().isEmpty) {
              throw Exception('Describe your experience.');
            }
            await ref.read(repositoryProvider).call('submitReview', {
              'orderId': widget.orderId,
              'target': target,
              'rating': rating,
              'comment': comment.text.trim(),
            });
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    ),
  );
}
