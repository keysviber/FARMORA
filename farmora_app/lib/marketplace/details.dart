import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/repository.dart';
import '../shared/widgets.dart';
import '../messaging/messages.dart';
import 'editor.dart';
import '../shared/business_identity.dart';
import 'transport_estimate.dart';
import '../profile/addresses.dart';
import '../profile/saved_suppliers.dart';

class RecordDetails extends ConsumerStatefulWidget {
  const RecordDetails({
    super.key,
    required this.collection,
    required this.id,
    required this.profile,
  });
  final String collection, id;
  final Map<String, dynamic> profile;
  @override
  ConsumerState<RecordDetails> createState() => _RecordDetailsState();
}

class _RecordDetailsState extends ConsumerState<RecordDetails> {
  final quantity = TextEditingController(),
      destination = TextEditingController(),
      offer = TextEditingController();
  String? requestKey;
  @override
  void dispose() {
    quantity.dispose();
    destination.dispose();
    offer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection(widget.collection)
            .doc(widget.id)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Could not load details',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const EmptyState(
              'No longer available',
              'This record has been removed.',
            );
          }
          final d = snapshot.data!.data()!,
              own = d['ownerId'] == repo.uid,
              product = widget.collection == 'products',
              request = widget.collection == 'buyerRequests';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if ((d['images'] as List?)?.isNotEmpty == true)
                SizedBox(
                  height: 260,
                  child: PageView(
                    children: (d['images'] as List)
                        .map(
                          (url) => InteractiveViewer(
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                d['name'] ?? 'Transport request',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(d['description'] ?? ''),
              if ((d['quality'] as String? ?? '').isNotEmpty)
                Text('Quality: ${d['quality']}'),
              if ((d['packaging'] as String? ?? '').isNotEmpty)
                Text('Packaging: ${d['packaging']}'),
              if ((d['harvestDate'] as String? ?? '').isNotEmpty)
                Text('Harvested: ${d['harvestDate']}'),
              Text('${d['location'] ?? d['pickup']}'),
              if (d['destination'] != null)
                Text('Deliver to: ${d['destination']}'),
              if (d['quantity'] != null) Text('${d['quantity']} ${d['unit']}'),
              if (d['price'] != null)
                Text(
                  '${money(d['price'], d['currency'] ?? 'USD')} per ${d['unit']}',
                ),
              if (d['minimum'] != null)
                Text('Minimum: ${d['minimum']} ${d['unit']}'),
              if (d['requiredDate'] != null)
                Text('Required by: ${d['requiredDate']}'),
              Text('Status: ${d['status']}'),
              BusinessIdentity(uid: d['ownerId']),
              BusinessReviews(uid: d['ownerId']),
              if (product && !own && widget.profile['role'] == 'buyer') ...[
                SaveSupplier(supplierId: d['ownerId']),
                TextButton(
                  onPressed: () => openScreen(
                    context,
                    SupplierProducts(
                      supplierId: d['ownerId'],
                      profile: widget.profile,
                    ),
                  ),
                  child: const Text('More from this supplier'),
                ),
              ],
              const SizedBox(height: 20),
              if (own &&
                  [
                    'products',
                    'buyerRequests',
                    'vehicles',
                  ].contains(widget.collection)) ...[
                FilledButton.icon(
                  onPressed: () => openScreen(
                    context,
                    RecordEditor(
                      collection: widget.collection,
                      id: widget.id,
                      initial: d,
                      profile: widget.profile,
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                if (d['status'] == 'soldOut')
                  const Text('Sold out. Edit the quantity to restock.')
                else
                  AsyncAction(
                    label: d['status'] == 'active' ? 'Pause' : 'Reactivate',
                    action: () => repo.db
                        .collection(widget.collection)
                        .doc(widget.id)
                        .update({
                          'status': d['status'] == 'active'
                              ? 'paused'
                              : 'active',
                          'updatedAt': FieldValue.serverTimestamp(),
                        }),
                  ),
                if (product && d['status'] != 'soldOut')
                  AsyncAction(
                    label: 'Mark sold out',
                    action: () => repo.db
                        .collection(widget.collection)
                        .doc(widget.id)
                        .update({
                          'status': 'soldOut',
                          'updatedAt': FieldValue.serverTimestamp(),
                        }),
                  ),
                AsyncAction(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  action: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Delete this record?'),
                        content: const Text(
                          'Existing order records will be retained.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await repo.db
                          .collection(widget.collection)
                          .doc(widget.id)
                          .delete();
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
              ],
              if (!own)
                AsyncAction(
                  label: product
                      ? 'Message supplier'
                      : request
                      ? 'Message buyer'
                      : 'Discuss transport',
                  icon: Icons.chat_bubble_outline,
                  action: () async {
                    final result = await repo.call('startConversation', {
                      'collection': widget.collection,
                      'recordId': widget.id,
                    });
                    if (context.mounted) {
                      openScreen(
                        context,
                        ChatScreen(
                          id: result['id'],
                          title: d['name'] ?? 'Transport',
                        ),
                      );
                    }
                  },
                ),
              if (!own &&
                  product &&
                  widget.profile['role'] == 'buyer' &&
                  d['status'] == 'active') ...[
                const SizedBox(height: 16),
                FormFieldInput(quantity, 'Required quantity', numeric: true),
                FormFieldInput(destination, 'Delivery destination'),
                TextButton.icon(
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('Choose saved address'),
                  onPressed: () async {
                    final selected = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) => const AddressesScreen(select: true),
                      ),
                    );
                    if (selected != null && mounted) {
                      setState(() => destination.text = selected);
                    }
                  },
                ),
                ValueListenableBuilder(
                  valueListenable: quantity,
                  builder: (_, value, _) {
                    final q = double.tryParse(value.text);
                    return Text(
                      q != null && q.isFinite && q > 0
                          ? 'Product subtotal: ${money(q * (d['price'] as num), d['currency'] ?? 'USD')}'
                          : 'Enter quantity to calculate subtotal',
                    );
                  },
                ),
                TransportEstimatePanel(
                  productId: widget.id,
                  quantity: quantity,
                  destination: destination,
                  price: d['price'],
                ),
                AsyncAction(
                  label: 'Request supplier quotation',
                  action: () async {
                    final q = positiveNumber(quantity.text);
                    if (q < d['minimum'] || q > d['quantity']) {
                      throw Exception(
                        'Choose a quantity between ${d['minimum']} and ${d['quantity']}.',
                      );
                    }
                    if (destination.text.trim().isEmpty) {
                      throw Exception('Enter your delivery destination.');
                    }
                    requestKey ??= repo.db.collection('orders').doc().id;
                    await repo.call('requestOrder', {
                      'productId': widget.id,
                      'quantity': q,
                      'destination': destination.text.trim(),
                      'requestKey': requestKey,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Quotation requested. Follow progress in Profile → Orders.',
                          ),
                        ),
                      );
                      Navigator.pop(context);
                    }
                  },
                ),
                AsyncAction(
                  label: 'Save product',
                  icon: Icons.bookmark_outline,
                  action: () async {
                    await repo.db
                        .collection('users')
                        .doc(repo.uid)
                        .collection('savedProducts')
                        .doc(widget.id)
                        .set({
                          'productId': widget.id,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Saved. Find it in Profile → Saved products.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
              if (!own &&
                  request &&
                  widget.profile['role'] == 'supplier' &&
                  d['status'] == 'active') ...[
                const SizedBox(height: 16),
                FormFieldInput(
                  offer,
                  'Your unit price (${d['currency'] ?? 'USD'})',
                  numeric: true,
                ),
                AsyncAction(
                  label: 'Send offer',
                  action: () async {
                    await repo.call('submitOffer', {
                      'requestId': widget.id,
                      'price': positiveNumber(offer.text),
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Offer sent. View it in Profile → Quotations.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
              if (!own &&
                  widget.collection == 'transportRequests' &&
                  widget.profile['role'] == 'logistics' &&
                  d['status'] == 'open') ...[
                FormFieldInput(
                  offer,
                  'Total delivery quote (${d['currency'] ?? 'USD'})',
                  numeric: true,
                ),
                AsyncAction(
                  label: 'Submit transport quote',
                  action: () async {
                    await repo.call('submitTransportQuote', {
                      'requestId': widget.id,
                      'amount': positiveNumber(offer.text),
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Transport quote submitted.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
