import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'repository.dart';

final currenciesProvider = StreamProvider<List<String>>(
  (ref) => ref
      .read(repositoryProvider)
      .db
      .collection('platformSettings')
      .doc('marketplace')
      .snapshots()
      .map(
        (snapshot) =>
            List<String>.from(snapshot.data()?['currencies'] ?? ['USD']),
      ),
);

final categoryProvider = StreamProvider<List<String>>(
  (ref) => ref
      .read(repositoryProvider)
      .db
      .collection('categories')
      .limit(100)
      .snapshots()
      .map((snapshot) {
        final available = categories.toSet();
        for (final doc in snapshot.docs) {
          if (doc.data()['active'] == true) {
            available.add(doc.id);
          } else {
            available.remove(doc.id);
          }
        }
        return available.toList()..sort();
      }),
);
