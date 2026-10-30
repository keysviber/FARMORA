import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/repository.dart';
import '../shared/widgets.dart';
import '../messaging/messages.dart';
import '../profile/profile.dart';
import 'editor.dart';
import 'details.dart';
import '../notifications/navigation.dart';
import '../core/catalog.dart';
import 'featured_suppliers.dart';
import '../profile/account_settings.dart';
import '../shared/business_identity.dart';

class MarketplaceShell extends StatefulWidget {
  const MarketplaceShell({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  State<MarketplaceShell> createState() => _MarketplaceShellState();
}

class _MarketplaceShellState extends State<MarketplaceShell> {
  int index = 0;
  StreamSubscription<RemoteMessage>? opened, foreground;
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && !const bool.fromEnvironment('USE_FIREBASE_EMULATORS')) {
      opened = FirebaseMessaging.onMessageOpenedApp.listen(handlePush);
      foreground = FirebaseMessaging.onMessage.listen((message) {
        if (!mounted ||
            message.data['userId'] != FirebaseAuth.instance.currentUser?.uid) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.notification?.title ?? 'New Farmora activity',
            ),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => handlePush(message),
            ),
          ),
        );
      });
      FirebaseMessaging.instance
          .getInitialMessage()
          .then((message) {
            if (message != null) handlePush(message);
          })
          .catchError((Object error) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(friendlyError(error))));
            }
          });
    }
  }

  Future<void> handlePush(RemoteMessage message) async {
    if (!mounted) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await openPushNotification(context, message.data, widget.profile, uid);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  @override
  void dispose() {
    opened?.cancel();
    foreground?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: index,
      children: [
        HomeScreen(profile: widget.profile),
        const MessagesScreen(),
        ProfileScreen(profile: widget.profile),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (v) => setState(() => index = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Messages',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    ),
  );
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = AccountRole.parse(profile['role']);
    final collection = role == AccountRole.buyer
        ? 'products'
        : role == AccountRole.supplier
        ? 'buyerRequests'
        : 'transportRequests';
    final ownCollection = role == AccountRole.buyer
        ? 'buyerRequests'
        : role == AccountRole.supplier
        ? 'products'
        : 'vehicles';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Farmora'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => openScreen(context, const NotificationsScreen()),
            icon: const Icon(Icons.notifications_outlined),
          ),
          TextButton.icon(
            onPressed: () => openScreen(
              context,
              RecordEditor(collection: ownCollection, profile: profile),
            ),
            icon: const Icon(Icons.add),
            label: Text(
              role == AccountRole.buyer
                  ? 'Buying request'
                  : role == AccountRole.supplier
                  ? 'Add product'
                  : 'Add vehicle',
            ),
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${profile['name']}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('${profile['location']} · ${role.label}'),
                      TextButton.icon(
                        onPressed: () => openScreen(
                          context,
                          AccountSettings(profile: profile),
                        ),
                        icon: const Icon(Icons.location_on_outlined),
                        label: const Text('Change location'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        role == AccountRole.buyer
                            ? 'Fresh opportunities. Direct from the source.'
                            : role == AccountRole.supplier
                            ? 'Find your next buyer.'
                            : 'Keep the harvest moving.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                if (profile['tutorialSeen'] != true)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      child: ListTile(
                        title: Text(
                          role == AccountRole.buyer
                              ? 'Browse, request a quote, then confirm your order.'
                              : role == AccountRole.supplier
                              ? 'Publish your produce or send an offer to a buyer.'
                              : 'Register a vehicle, then quote for transport jobs.',
                        ),
                        trailing: TextButton(
                          onPressed: () => ref
                              .read(repositoryProvider)
                              .db
                              .collection('users')
                              .doc(ref.read(repositoryProvider).uid)
                              .update({'tutorialSeen': true})
                              .catchError((Object e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(friendlyError(e))),
                                  );
                                }
                              }),
                          child: const Text('Skip'),
                        ),
                      ),
                    ),
                  ),
                if (role == AccountRole.buyer)
                  FeaturedSuppliers(profile: profile),
              ],
            ),
          ),
        ],
        body: RecordsList(collection: collection, profile: profile),
      ),
    );
  }
}

class RecordsList extends ConsumerStatefulWidget {
  const RecordsList({
    super.key,
    required this.collection,
    required this.profile,
    this.own = false,
  });
  final String collection;
  final Map<String, dynamic> profile;
  final bool own;
  @override
  ConsumerState<RecordsList> createState() => _RecordsListState();
}

class _RecordsListState extends ConsumerState<RecordsList> {
  String search = '', category = 'All', sorting = 'Newest';
  bool localOnly = false;
  int limit = 30;
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    Query<Map<String, dynamic>> query = repo.db.collection(widget.collection);
    query = widget.own
        ? query.where('ownerId', isEqualTo: repo.uid)
        : query.where(
            'status',
            isEqualTo: widget.collection == 'transportRequests'
                ? 'open'
                : 'active',
          );
    if (category != 'All') query = query.where('category', isEqualTo: category);
    query = query.orderBy('createdAt', descending: true).limit(limit);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search loaded results',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase().trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('My location'),
                selected: localOnly,
                onSelected: (value) => setState(() => localOnly = value),
              ),
              DropdownButton<String>(
                value: sorting,
                items: ['Newest', 'Price: low to high', 'Quantity: high to low']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => sorting = value!),
              ),
            ],
          ),
        ),
        if (['products', 'buyerRequests'].contains(widget.collection))
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children:
                  ['All', ...(ref.watch(categoryProvider).value ?? categories)]
                      .map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: category == c,
                            onSelected: (_) => setState(() {
                              category = c;
                              limit = 30;
                            }),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  'Could not load marketplace',
                  friendlyError(snapshot.error!),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs
                  .where(
                    (d) =>
                        (!localOnly ||
                            (d.data()['location'] as String? ?? '')
                                .toLowerCase()
                                .contains(
                                  (widget.profile['location'] as String)
                                      .toLowerCase(),
                                )) &&
                        '${d.data()['name']} ${d.data()['location']}'
                            .toLowerCase()
                            .contains(search),
                  )
                  .toList();
              if (sorting == 'Price: low to high') {
                docs.sort((a, b) {
                  final currency = (a.data()['currency'] as String? ?? 'USD')
                      .compareTo(b.data()['currency'] as String? ?? 'USD');
                  return currency != 0
                      ? currency
                      : ((a.data()['price'] as num?) ?? double.infinity)
                            .compareTo(
                              (b.data()['price'] as num?) ?? double.infinity,
                            );
                });
              }
              if (sorting == 'Quantity: high to low') {
                docs.sort((a, b) {
                  final unit = (a.data()['unit'] as String? ?? '').compareTo(
                    b.data()['unit'] as String? ?? '',
                  );
                  return unit != 0
                      ? unit
                      : ((b.data()['quantity'] as num?) ?? 0).compareTo(
                          (a.data()['quantity'] as num?) ?? 0,
                        );
                });
              }
              if (docs.isEmpty) {
                return ListView(
                  children: [
                    const EmptyState(
                      'No results yet',
                      'New listings and opportunities will appear here. Try another category or publish your first record.',
                    ),
                    if (snapshot.data!.docs.length == limit)
                      TextButton(
                        onPressed: () => setState(() => limit += 30),
                        child: const Text('Search more results'),
                      ),
                  ],
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await query.get(const GetOptions(source: Source.server));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length + 1,
                  itemBuilder: (context, i) {
                    if (i == docs.length) {
                      return snapshot.data!.docs.length == limit
                          ? TextButton(
                              onPressed: () => setState(() => limit += 30),
                              child: const Text('Load more'),
                            )
                          : const SizedBox(height: 24);
                    }
                    final doc = docs[i], data = doc.data();
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: () => openScreen(
                          context,
                          RecordDetails(
                            collection: widget.collection,
                            id: doc.id,
                            profile: widget.profile,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if ((data['images'] as List?)?.isNotEmpty == true)
                              Image.network(
                                data['images'][0],
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox(
                                  height: 100,
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['name'] ?? 'Transport opportunity',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('${data['location'] ?? data['pickup']}'),
                                  BusinessIdentity(uid: data['ownerId']),
                                  if (data['price'] != null)
                                    Text(
                                      '${money(data['price'], data['currency'] ?? 'USD')} / ${data['unit']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  if (data['quantity'] != null)
                                    Text(
                                      '${data['quantity']} ${data['unit']} · ${data['status']}',
                                    ),
                                  if (data['minimum'] != null)
                                    Text(
                                      'Minimum order: ${data['minimum']} ${data['unit']}',
                                    ),
                                  if (data['requiredDate'] != null)
                                    Text('Required: ${data['requiredDate']}'),
                                  const SizedBox(height: 8),
                                  const Text('View details →'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
