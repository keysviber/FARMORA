import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models.dart';
import '../core/repository.dart';
import '../shared/widgets.dart';
import '../core/catalog.dart';

class RecordEditor extends ConsumerStatefulWidget {
  const RecordEditor({
    super.key,
    required this.collection,
    required this.profile,
    this.id,
    this.initial,
  });
  final String collection;
  final Map<String, dynamic> profile;
  final String? id;
  final Map<String, dynamic>? initial;
  @override
  ConsumerState<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends ConsumerState<RecordEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final photos = <XFile>[];
  String? draftId;
  final uploaded = <XFile, String>{};
  late final existingPhotos = List<String>.from(
    widget.initial?['images'] ?? [],
  );
  String category = categories.first, unit = units.first;
  String currency = 'USD';
  String? date;
  TextEditingController field(String name) => fields.putIfAbsent(
    name,
    () => TextEditingController(
      text:
          widget.initial?[name]?.toString() ??
          (name == 'location' ? widget.profile['location'] : ''),
    ),
  );
  @override
  void initState() {
    super.initState();
    category = widget.initial?['category'] ?? categories.first;
    unit = widget.initial?['unit'] ?? units.first;
    date = widget.initial?['requiredDate'];
    currency = widget.initial?['currency'] ?? 'USD';
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.collection == 'products',
        vehicle = widget.collection == 'vehicles';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.id == null ? 'Add' : 'Edit'} ${product
              ? 'product'
              : vehicle
              ? 'vehicle'
              : 'buying request'}',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                FormFieldInput(
                  field('name'),
                  vehicle ? 'Vehicle type' : 'Product name',
                ),
                if (!vehicle) ...[
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items:
                        {
                              ...(ref.watch(categoryProvider).value ??
                                  categories),
                              category,
                            }
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) => category = v!,
                  ),
                  const SizedBox(height: 16),
                ],
                FormFieldInput(
                  field('quantity'),
                  vehicle ? 'Load capacity' : 'Quantity',
                  numeric: true,
                ),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: units
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: widget.id != null && product
                      ? null
                      : (v) => unit = v!,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items:
                      {
                            ...(ref.watch(currenciesProvider).value ?? ['USD']),
                            currency,
                          }
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: widget.id != null
                      ? null
                      : (value) => setState(() => currency = value!),
                ),
                const SizedBox(height: 16),
                if (!vehicle)
                  FormFieldInput(
                    field('price'),
                    product
                        ? 'Price per unit ($currency)'
                        : 'Target price per unit ($currency, optional)',
                    numeric: true,
                    optional: !product,
                  ),
                if (product)
                  FormFieldInput(
                    field('minimum'),
                    'Minimum order quantity',
                    numeric: true,
                  ),
                FormFieldInput(
                  field('location'),
                  product
                      ? 'Pickup location'
                      : vehicle
                      ? 'Operating locations'
                      : 'Delivery location',
                ),
                if (vehicle) ...[
                  FormFieldInput(field('registration'), 'Vehicle registration'),
                  FormFieldInput(
                    field('baseFee'),
                    'Base fee ($currency)',
                    numeric: true,
                  ),
                  FormFieldInput(
                    field('rate'),
                    'Price per road kilometre ($currency)',
                    numeric: true,
                  ),
                  FormFieldInput(field('cargo'), 'Supported cargo types'),
                ],
                if (!product && !vehicle) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (d != null) {
                        setState(
                          () => date = d.toIso8601String().split('T').first,
                        );
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(date ?? 'Required delivery date'),
                  ),
                  const SizedBox(height: 16),
                ],
                FormFieldInput(
                  field('description'),
                  vehicle
                      ? 'Vehicle and service information'
                      : 'Description / additional requirements',
                  lines: 3,
                  optional: true,
                ),
                if (product)
                  ExpansionTile(
                    title: const Text('Quality and packaging (optional)'),
                    children: [
                      FormFieldInput(
                        field('quality'),
                        'Quality grade',
                        optional: true,
                      ),
                      FormFieldInput(
                        field('packaging'),
                        'Packaging details',
                        optional: true,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          field('harvestDate').text.isEmpty
                              ? 'Select harvest date'
                              : field('harvestDate').text,
                        ),
                        onPressed: () async {
                          final selected = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (selected != null && mounted) {
                            setState(
                              () => field('harvestDate').text = selected
                                  .toIso8601String()
                                  .split('T')
                                  .first,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                if (product || vehicle) ...[
                  for (final url in existingPhotos)
                    ListTile(
                      leading: Image.network(
                        url,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                      title: const Text('Listing photo'),
                      trailing: IconButton(
                        tooltip: 'Remove photo',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() => existingPhotos.remove(url)),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 75,
                        maxWidth: 1600,
                      );
                      if (selected != null && mounted) {
                        setState(() => photos.add(selected));
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('Add photo (${photos.length} selected)'),
                  ),
                  for (final p in photos)
                    ListTile(
                      title: Text(p.name),
                      trailing: IconButton(
                        tooltip: 'Remove photo',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => photos.remove(p)),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                AsyncAction(
                  label: widget.id == null ? 'Publish' : 'Save changes',
                  icon: Icons.check,
                  action: () async {
                    if (!form.currentState!.validate()) return;
                    if (!product && !vehicle && date == null) {
                      throw Exception('Choose a delivery date.');
                    }
                    final quantity = positiveNumber(field('quantity').text);
                    if (product &&
                        positiveNumber(field('minimum').text) > quantity) {
                      throw Exception(
                        'Minimum order cannot exceed available quantity.',
                      );
                    }
                    final repo = ref.read(repositoryProvider);
                    final urls = List<String>.from(existingPhotos);
                    if ((product || vehicle) &&
                        urls.isEmpty &&
                        photos.isEmpty) {
                      throw Exception('Add at least one photo.');
                    }
                    if (urls.length + photos.length > 6) {
                      throw Exception('Use up to six photos.');
                    }
                    for (final p in photos) {
                      uploaded[p] ??= await repo.upload(p, widget.collection);
                      urls.add(uploaded[p]!);
                    }
                    draftId ??= repo.db.collection(widget.collection).doc().id;
                    await repo.publish(widget.collection, {
                      'name': field('name').text.trim(),
                      'location': field('location').text.trim(),
                      'description': field('description').text.trim(),
                      'quantity': quantity,
                      'unit': unit,
                      'currency': currency,
                      // Saving a sold-out product with new stock restocks it.
                      'status': switch (widget.initial?['status']) {
                        null || 'soldOut' => 'active',
                        final status => status,
                      },
                      'images': urls,
                      if (!vehicle) 'category': category,
                      if (!vehicle && field('price').text.isNotEmpty)
                        'price': positiveNumber(field('price').text),
                      if (product)
                        'minimum': positiveNumber(field('minimum').text),
                      if (product) ...{
                        'quality': field('quality').text.trim(),
                        'packaging': field('packaging').text.trim(),
                        'harvestDate': field('harvestDate').text.trim(),
                      },
                      if (!product && !vehicle) 'requiredDate': date,
                      if (vehicle) ...{
                        'registration': field('registration').text.trim(),
                        'baseFee': positiveNumber(field('baseFee').text),
                        'rate': positiveNumber(field('rate').text),
                        'cargo': field('cargo').text.trim(),
                      },
                    }, id: widget.id ?? draftId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Published successfully')),
                      );
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
