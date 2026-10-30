import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';
import '../core/models.dart';
import '../orders/orders.dart';
import '../shared/widgets.dart';

class FinancialHistory extends ConsumerStatefulWidget {
  const FinancialHistory({super.key, required this.role});
  final String role;
  @override
  ConsumerState<FinancialHistory> createState() => _FinancialHistoryState();
}

class _FinancialHistoryState extends ConsumerState<FinancialHistory> {
  int limit = 50;
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    final driver = widget.role == 'logistics';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          driver
              ? 'Delivery earnings'
              : widget.role == 'supplier'
              ? 'Sales history'
              : 'Payment history',
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection('orders')
            .where('participants', arrayContains: repo.uid)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'History unavailable',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data!.docs;
          final completed = <String, double>{}, expected = <String, double>{};
          for (final doc in orders) {
            final data = doc.data();
            final amount =
                (driver ? data['transportFee'] ?? 0 : data['subtotal'] ?? 0)
                    as num;
            final currency = data['currency'] as String? ?? 'USD';
            if (data['status'] == 'completed') {
              completed[currency] =
                  (completed[currency] ?? 0) + amount.toDouble();
            }
            if (![
              'completed',
              'cancelled',
              'declined',
            ].contains(data['status'])) {
              expected[currency] =
                  (expected[currency] ?? 0) + amount.toDouble();
            }
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (driver || widget.role == 'supplier') ...[
                for (final entry in completed.entries)
                  Text(
                    'Completed ${driver ? 'delivery fees' : 'sales'}: ${money(entry.value, entry.key)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                for (final entry in expected.entries)
                  Text('Active order value: ${money(entry.value, entry.key)}'),
                const Text(
                  'Totals cover the loaded orders. Agreed fees and completed sales do not establish a provider payout or bank settlement.',
                ),
                const SizedBox(height: 16),
              ],
              if (orders.isEmpty)
                const EmptyState(
                  'No transaction history',
                  'Your real orders and payment statuses will appear here.',
                ),
              for (final doc in orders)
                ListTile(
                  title: Text(doc['name']),
                  subtitle: Text(
                    '${doc['status']} · Payment: ${doc['paymentStatus']}',
                  ),
                  trailing: Text(
                    money(
                      driver
                          ? doc.data()['transportFee'] ?? 0
                          : (doc.data()['subtotal'] as num) +
                                (widget.role == 'buyer'
                                    ? doc.data()['transportFee'] as num? ?? 0
                                    : 0),
                      doc.data()['currency'] ?? 'USD',
                    ),
                  ),
                  onTap: () => openScreen(
                    context,
                    OrderScreen(id: doc.id, role: widget.role),
                  ),
                ),
              if (orders.length == limit)
                TextButton(
                  onPressed: () => setState(() => limit += 50),
                  child: const Text('Load earlier transactions'),
                ),
            ],
          );
        },
      ),
    );
  }
}
