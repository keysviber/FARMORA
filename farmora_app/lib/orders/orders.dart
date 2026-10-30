import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import 'delivery_proof.dart';
import '../profile/account_settings.dart';
import '../core/repository.dart';
import '../shared/widgets.dart';
import '../messaging/messages.dart';
import '../marketplace/details.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key, required this.role});
  final String role;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Orders & deliveries')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection('orders')
            .where('participants', arrayContains: repo.uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Could not load orders',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const EmptyState(
              'No orders yet',
              'Request a product quotation or accept a supplier offer to begin.',
            );
          }
          return ListView(
            children: snapshot.data!.docs.map((doc) {
              final d = doc.data();
              return ListTile(
                title: Text(d['name']),
                subtitle: Text(
                  '${d['status']} · ${money(d['subtotal'], d['currency'] ?? 'USD')}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    openScreen(context, OrderScreen(id: doc.id, role: role)),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.id, required this.role});
  final String id, role;
  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  final price = TextEditingController(), reference = TextEditingController();
  @override
  void dispose() {
    price.dispose();
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Order details')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: repo.db.collection('orders').doc(widget.id).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Could not load order',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const EmptyState(
              'Order unavailable',
              'This order could not be found.',
            );
          }
          final d = snapshot.data!.data()!, status = d['status'];
          final buyer = d['buyerId'] == repo.uid,
              supplier = d['supplierId'] == repo.uid,
              driver = d['transporterId'] == repo.uid;
          Widget action(String label, String next) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AsyncAction(
              label: label,
              action: () async {
                await repo.call('transitionOrder', {
                  'orderId': widget.id,
                  'next': next,
                });
              },
            ),
          );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(d['name'], style: Theme.of(context).textTheme.headlineSmall),
              Text('${d['quantity']} ${d['unit']}'),
              Text(
                'Product total: ${money(d['subtotal'], d['currency'] ?? 'USD')}',
              ),
              Text('Delivery: ${d['destination']}'),
              Text('Order status: $status'),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in {
                    'Buyer': d['buyerId'],
                    'Supplier': d['supplierId'],
                    'Transporter': d['transporterId'],
                  }.entries)
                    if (entry.value != null && entry.value != repo.uid)
                      AsyncAction(
                        label: 'Message ${entry.key.toLowerCase()}',
                        action: () async {
                          final chat = await repo.call('startConversation', {
                            'collection': 'orders',
                            'recordId': widget.id,
                            'recipientId': entry.value,
                          });
                          if (context.mounted) {
                            openScreen(
                              context,
                              ChatScreen(id: chat['id'], title: d['name']),
                            );
                          }
                        },
                      ),
                ],
              ),
              if (buyer && status == 'completed')
                FilledButton(
                  onPressed: () => openScreen(
                    context,
                    ReviewScreen(
                      orderId: widget.id,
                      hasTransporter: d['transporterId'] != null,
                    ),
                  ),
                  child: const Text('Rate supplier / transporter'),
                ),
              Text('Payment: ${d['paymentStatus']}'),
              if (driver &&
                  d['driverAccepted'] != true &&
                  ['confirmed', 'ready'].contains(status))
                AsyncAction(
                  label: 'Accept assigned delivery job',
                  action: () async {
                    await repo.call('acceptJob', {'orderId': widget.id});
                  },
                ),
              if ([
                'inTransit',
                'delivered',
                'completed',
                'deliveryFailed',
              ].contains(status))
                DeliveryProofPanel(
                  orderId: widget.id,
                  path: d['proofPath'],
                  canUpload:
                      status == 'inTransit' &&
                      (driver || supplier && d['transporterId'] == null),
                ),
              if (driver && status == 'inTransit')
                action('Report failed delivery', 'deliveryFailed'),
              if (d['transportFee'] != null)
                Text(
                  'Accepted transport fee: ${money(d['transportFee'], d['currency'] ?? 'USD')}',
                ),
              const SizedBox(height: 24),
              if (supplier && status == 'requested') ...[
                FormFieldInput(
                  price,
                  'Quoted unit price (${d['currency'] ?? 'USD'})',
                  numeric: true,
                ),
                AsyncAction(
                  label: 'Send quotation',
                  action: () async {
                    await repo.call('quoteOrder', {
                      'orderId': widget.id,
                      'price': positiveNumber(price.text),
                    });
                  },
                ),
                action('Decline request', 'declined'),
              ],
              if (buyer && status == 'quoted')
                action('Accept quote and reserve stock', 'confirmed'),
              if (supplier && status == 'confirmed')
                action('Ready for collection', 'ready'),
              if ((driver && d['driverAccepted'] == true ||
                      supplier && d['transporterId'] == null) &&
                  status == 'ready')
                action('Confirm collection', 'inTransit'),
              if ((driver || supplier && d['transporterId'] == null) &&
                  status == 'inTransit')
                d['proofPath'] == null
                    ? const Text('Upload proof of delivery to report arrival.')
                    : action('Report arrival', 'delivered'),
              if (buyer && status == 'delivered')
                action('Confirm receipt', 'completed'),
              // Suppliers decline (not cancel) requests they have not quoted.
              if (buyer &&
                      [
                        'requested',
                        'quoted',
                        'confirmed',
                        'ready',
                      ].contains(status) ||
                  supplier && ['quoted', 'confirmed', 'ready'].contains(status))
                action('Cancel order', 'cancelled'),
              if ((buyer || supplier) &&
                  ['inTransit', 'delivered'].contains(status))
                action('Open dispute', 'disputed'),
              if (buyer &&
                  ['confirmed', 'ready'].contains(status) &&
                  d['transporterId'] == null &&
                  d['paymentStatus'] == 'pending') ...[
                const SizedBox(height: 16),
                AsyncAction(
                  label: 'Request transport quotes',
                  action: () async {
                    await repo.call('requestTransport', {'orderId': widget.id});
                  },
                ),
                TransportQuotes(orderId: widget.id),
              ],
              if (buyer &&
                  [
                    'confirmed',
                    'ready',
                    'inTransit',
                    'delivered',
                    'completed',
                  ].contains(status) &&
                  ['pending', 'failed'].contains(d['paymentStatus'])) ...[
                const SizedBox(height: 16),
                const Text(
                  'Record an agreed external payment. This does not mark the order paid; an authorized operator must reconcile it.',
                ),
                FormFieldInput(reference, 'Payment method and reference'),
                AsyncAction(
                  label: 'Submit payment for verification',
                  action: () async {
                    if (reference.text.trim().isEmpty) {
                      throw Exception('Enter a payment reference.');
                    }
                    await repo.call('recordPayment', {
                      'orderId': widget.id,
                      'reference': reference.text.trim(),
                    });
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

class TransportQuotes extends ConsumerWidget {
  const TransportQuotes({super.key, required this.orderId});
  final String orderId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: repo.db
          .collection('transportQuotes')
          .where('buyerId', isEqualTo: repo.uid)
          .where('orderId', isEqualTo: orderId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(friendlyError(snapshot.error!));
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return Column(
          children: snapshot.data!.docs
              .map(
                (doc) => ListTile(
                  title: Text(
                    money(
                      doc.data()['amount'],
                      doc.data()['currency'] ?? 'USD',
                    ),
                  ),
                  subtitle: Text(doc.data()['status']),
                  trailing: doc.data()['status'] == 'pending'
                      ? AsyncAction(
                          label: 'Select',
                          action: () async {
                            await repo.call('acceptTransportQuote', {
                              'quoteId': doc.id,
                            });
                          },
                        )
                      : null,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class SentTransportQuotes extends ConsumerWidget {
  const SentTransportQuotes({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My transport quotes')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection('transportQuotes')
            .where('transporterId', isEqualTo: repo.uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Could not load quotes',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const EmptyState(
              'No quotes sent yet',
              'Open a transport job from Home and submit a delivery quote.',
            );
          }
          return ListView(
            children: snapshot.data!.docs.map((doc) {
              final q = doc.data();
              // Unselected quotes stay pending on the server, so show the
              // job's state to tell the transporter whether it is still open.
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: repo.db
                    .collection('transportRequests')
                    .doc(q['requestId'])
                    .snapshots(),
                builder: (context, request) {
                  final r = request.data?.data();
                  final status = q['status'] == 'accepted'
                      ? 'accepted'
                      : r == null || r['status'] == 'open'
                      ? q['status']
                      : 'not selected';
                  return ListTile(
                    title: Text(r?['name'] ?? 'Transport job'),
                    subtitle: Text(
                      '${money(q['amount'], q['currency'] ?? 'USD')} · $status'
                      '${r == null ? '' : '\n${r['pickup']} → ${r['destination']}'}',
                    ),
                    isThreeLine: r != null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openScreen(
                      context,
                      q['status'] == 'accepted'
                          ? OrderScreen(id: q['orderId'], role: 'logistics')
                          : RecordDetails(
                              collection: 'transportRequests',
                              id: q['requestId'],
                              profile: profile,
                            ),
                    ),
                  );
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key, required this.role});
  final String role;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Quotations')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection('quotations')
            .where(
              role == 'buyer' ? 'buyerId' : 'supplierId',
              isEqualTo: repo.uid,
            )
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Could not load offers',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const EmptyState(
              'No offers yet',
              'Offers for buying requests will appear here.',
            );
          }
          return ListView(
            children: snapshot.data!.docs.map((doc) {
              final d = doc.data();
              return ListTile(
                title: Text(d['name']),
                subtitle: Text(
                  '${money(d['price'], d['currency'] ?? 'USD')} / ${d['unit']} · ${d['status']}',
                ),
                trailing: role == 'buyer' && d['status'] == 'pending'
                    ? AsyncAction(
                        label: 'Accept',
                        action: () async {
                          await repo.call('acceptOffer', {'offerId': doc.id});
                        },
                      )
                    : null,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
