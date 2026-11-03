import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.message, {
    super.key,
    this.icon = Icons.eco_outlined,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class AsyncAction extends StatefulWidget {
  const AsyncAction({
    super.key,
    required this.label,
    required this.action,
    this.icon,
  });
  final String label;
  final Future<void> Function() action;
  final IconData? icon;
  @override
  State<AsyncAction> createState() => _AsyncActionState();
}

class _AsyncActionState extends State<AsyncAction> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await widget.action();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(friendlyError(e))));
              }
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.arrow_forward),
    label: Text(busy ? 'Please wait…' : widget.label),
  );
}

String friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('invalid-credential')) {
    return 'Those sign-in details are incorrect.';
  }
  if (text.contains('email-already-in-use')) {
    return 'This phone number already has an account. Please sign in.';
  }
  if (text.contains('operation-not-allowed')) {
    return 'Sign-up is not available right now. Please try again later.';
  }
  if (text.contains('weak-password')) {
    return 'Choose a stronger password with at least 8 characters.';
  }
  if (text.contains('invalid-email')) {
    return 'Enter a valid email address.';
  }
  if (text.contains('too-many-requests')) {
    return 'Too many attempts. Please wait a few minutes and try again.';
  }
  if (text.contains('permission-denied')) {
    return 'This action is not permitted. Check your account access.';
  }
  if (text.contains('unavailable') || text.contains('network-request-failed')) {
    return 'Connection unavailable. Please reconnect and retry.';
  }
  return text
      .replaceFirst('Exception: ', '')
      .replaceFirst('FormatException: ', '');
}

void openScreen(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class FormFieldInput extends StatelessWidget {
  const FormFieldInput(
    this.controller,
    this.label, {
    super.key,
    this.numeric = false,
    this.optional = false,
    this.lines = 1,
  });
  final TextEditingController controller;
  final String label;
  final bool numeric, optional;
  final int lines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      maxLines: lines,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (optional && text.isEmpty) return null;
        if (text.isEmpty) return '$label is required';
        if (numeric) {
          final n = double.tryParse(text);
          if (n == null || !n.isFinite || n <= 0) {
            return 'Enter a number greater than zero';
          }
        }
        return null;
      },
    ),
  );
}
