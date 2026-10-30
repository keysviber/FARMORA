import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';
import '../profile/saved_suppliers.dart';
import '../shared/widgets.dart';

class FeaturedSuppliers extends ConsumerWidget {
  const FeaturedSuppliers({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: ref
        .read(repositoryProvider)
        .db
        .collection('publicProfiles')
        .where('featured', isEqualTo: true)
        .limit(10)
        .snapshots(),
    builder: (context, snapshot) {
      final suppliers = snapshot.data?.docs ?? [];
      if (suppliers.isEmpty) return const SizedBox.shrink();
      return SizedBox(
        height: 100,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final doc in suppliers)
              SizedBox(
                width: 240,
                child: Card(
                  child: ListTile(
                    title: Text(
                      doc['name'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Featured supplier · ${doc['location']}',
                      maxLines: 2,
                    ),
                    leading: const Icon(Icons.verified, color: Colors.green),
                    onTap: () => openScreen(
                      context,
                      SupplierProducts(supplierId: doc.id, profile: profile),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
