import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';
import '../core/models.dart';
import '../marketplace/details.dart';
import '../shared/widgets.dart';
import '../shared/business_identity.dart';

class SavedSuppliers extends ConsumerWidget {
  const SavedSuppliers({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved suppliers')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection('users')
            .doc(repo.uid)
            .collection('savedSuppliers')
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              'Suppliers unavailable',
              friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const EmptyState(
              'No saved suppliers',
              'Save a supplier from a product details page.',
            );
          }
          return ListView(
            children: [
              for (final doc in snapshot.data!.docs)
                Card(
                  child: Column(
                    children: [
                      BusinessIdentity(uid: doc.id),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => openScreen(
                              context,
                              SupplierProducts(
                                supplierId: doc.id,
                                profile: profile,
                              ),
                            ),
                            child: const Text('View products'),
                          ),
                          AsyncAction(
                            label: 'Remove',
                            action: () => doc.reference.delete(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class SaveSupplier extends ConsumerWidget {
  const SaveSupplier({super.key, required this.supplierId});
  final String supplierId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    final saved = repo.db
        .collection('users')
        .doc(repo.uid)
        .collection('savedSuppliers')
        .doc(supplierId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: saved.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(friendlyError(snapshot.error!));
        final exists = snapshot.data?.exists == true;
        return AsyncAction(
          label: exists ? 'Unsave supplier' : 'Save supplier',
          icon: Icons.storefront_outlined,
          action: () async {
            if (exists) {
              await saved.delete();
            } else {
              await saved.set({
                'supplierId': supplierId,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          },
        );
      },
    );
  }
}

class SupplierProducts extends ConsumerStatefulWidget {
  const SupplierProducts({
    super.key,
    required this.supplierId,
    required this.profile,
  });
  final String supplierId;
  final Map<String, dynamic> profile;
  @override
  ConsumerState<SupplierProducts> createState() => _SupplierProductsState();
}

class _SupplierProductsState extends ConsumerState<SupplierProducts> {
  int limit = 30;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Supplier products')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref
          .read(repositoryProvider)
          .db
          .collection('products')
          .where('ownerId', isEqualTo: widget.supplierId)
          .limit(limit)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            'Products unavailable',
            friendlyError(snapshot.error!),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snapshot.data!.docs
            .where((doc) => doc.data()['status'] == 'active')
            .toList();
        return ListView(
          children: [
            BusinessIdentity(uid: widget.supplierId),
            if (products.isEmpty)
              const EmptyState(
                'No active products in this page',
                'Check back later or load more products.',
              ),
            for (final doc in products)
              ListTile(
                title: Text(doc['name']),
                subtitle: Text(
                  '${money(doc['price'], doc.data()['currency'] ?? 'USD')} / ${doc['unit']}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openScreen(
                  context,
                  RecordDetails(
                    collection: 'products',
                    id: doc.id,
                    profile: widget.profile,
                  ),
                ),
              ),
            if (snapshot.data!.docs.length == limit)
              TextButton(
                onPressed: () => setState(() => limit += 30),
                child: const Text('Load more'),
              ),
          ],
        );
      },
    ),
  );
}
