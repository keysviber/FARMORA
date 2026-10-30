import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';
import 'widgets.dart';

class BusinessIdentity extends ConsumerWidget {
  const BusinessIdentity({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref
            .read(repositoryProvider)
            .db
            .collection('publicProfiles')
            .doc(uid)
            .snapshots(),
        builder: (context, s) {
          final p = s.data?.data();
          if (p == null) return const SizedBox.shrink();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storefront_outlined),
            title: Text(p['name']),
            subtitle: Text(p['location']),
            trailing: p['verified'] == true
                ? const Tooltip(
                    message: 'Verified business',
                    child: Icon(Icons.verified, color: Colors.green),
                  )
                : null,
          );
        },
      );
}

class BusinessReviews extends ConsumerWidget {
  const BusinessReviews({super.key, required this.uid});
  final String uid;
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: ref
        .read(repositoryProvider)
        .db
        .collection('reviews')
        .where('subjectId', isEqualTo: uid)
        .limit(100)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text(friendlyError(snapshot.error!));
      final reviews = snapshot.data?.docs ?? [];
      if (reviews.isEmpty) {
        return const Text('No completed-transaction reviews yet.');
      }
      final average =
          reviews.fold<double>(
            0,
            (total, doc) => total + (doc['rating'] as num).toDouble(),
          ) /
          reviews.length;
      return ExpansionTile(
        title: Text(
          '${average.toStringAsFixed(1)} / 5 · ${reviews.length}${reviews.length == 100 ? '+' : ''} reviews',
        ),
        subtitle: reviews.length == 100
            ? const Text('Average of the 100 displayed reviews')
            : null,
        children: [
          for (final doc in reviews)
            ListTile(
              title: Text('${doc['rating']} / 5'),
              subtitle: Text(doc['comment']),
            ),
        ],
      );
    },
  );
}
