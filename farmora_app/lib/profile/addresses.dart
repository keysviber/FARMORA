import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';
import '../shared/widgets.dart';

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key, this.select = false});
  final bool select;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final addresses = repo.db
        .collection('users')
        .doc(repo.uid)
        .collection('addresses');
    return Scaffold(
      appBar: AppBar(
        title: Text(select ? 'Choose delivery address' : 'Saved locations'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            openScreen(context, AddressEditor(reference: addresses.doc())),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add location'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: addresses.orderBy('label').limit(100).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Locations unavailable',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const EmptyState(
              'No saved locations',
              'Add a delivery or pickup location to reuse it.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final doc in snapshot.data!.docs)
                ListTile(
                  title: Text(doc['label']),
                  subtitle: Text(
                    '${doc['address']}\n${doc['contact']} · ${doc['phone']}',
                  ),
                  onTap: () => select
                      ? Navigator.pop(context, doc['address'])
                      : openScreen(
                          context,
                          AddressEditor(
                            reference: doc.reference,
                            initial: doc.data(),
                          ),
                        ),
                  trailing: select
                      ? const Icon(Icons.chevron_right)
                      : AsyncAction(
                          label: 'Delete',
                          action: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete saved location?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) await doc.reference.delete();
                          },
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AddressEditor extends StatefulWidget {
  const AddressEditor({
    super.key,
    required this.reference,
    this.initial = const {},
  });
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> initial;
  @override
  State<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<AddressEditor> {
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final key in ['label', 'address', 'contact', 'phone'])
      key: TextEditingController(text: widget.initial[key] as String?),
  };
  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Save location')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FormFieldInput(fields['label']!, 'Label, e.g. Warehouse'),
          FormFieldInput(
            fields['address']!,
            'Street, city and province',
            lines: 3,
          ),
          FormFieldInput(fields['contact']!, 'Contact name'),
          FormFieldInput(fields['phone']!, 'Contact phone'),
          AsyncAction(
            label: 'Save location',
            action: () async {
              if (!form.currentState!.validate()) return;
              final limits = {
                'label': 80,
                'address': 500,
                'contact': 120,
                'phone': 40,
              };
              for (final key in fields.keys) {
                if (fields[key]!.text.trim().length > limits[key]!) {
                  throw Exception('$key is too long.');
                }
              }
              await widget.reference.set({
                for (final entry in fields.entries)
                  entry.key: entry.value.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}
