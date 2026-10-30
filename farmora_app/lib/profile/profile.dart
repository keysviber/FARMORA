import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import 'account_settings.dart';
import 'addresses.dart';
import 'verification.dart';
import 'saved_suppliers.dart';
import '../notifications/navigation.dart';
import 'financial_history.dart';
import '../orders/delivery_proof.dart';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../core/repository.dart';
import '../shared/widgets.dart';
import '../marketplace/home.dart';
import '../marketplace/details.dart';
import '../marketplace/editor.dart';
import '../orders/orders.dart';
import '../authentication/auth_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider), role = profile['role'];
    final collection = role == 'buyer'
        ? 'buyerRequests'
        : role == 'supplier'
        ? 'products'
        : 'vehicles';
    void page(Widget p) => openScreen(context, p);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (profile['avatarPath'] is String)
            PrivateImage(path: profile['avatarPath'])
          else
            const CircleAvatar(
              radius: 36,
              child: Icon(Icons.person_outline, size: 40),
            ),
          const SizedBox(height: 12),
          AsyncAction(
            label: 'Change profile photo',
            icon: Icons.add_a_photo_outlined,
            action: () async {
              final selected = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 800,
                imageQuality: 80,
              );
              if (selected == null) return;
              final bytes = await selected.readAsBytes();
              if (bytes.length >= 5 * 1024 * 1024) {
                throw Exception('Choose a photo smaller than 5 MB.');
              }
              final path =
                  'avatars/${repo.uid}/${repo.db.collection('uploads').doc().id}.jpg';
              await FirebaseStorage.instance
                  .ref(path)
                  .putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
              await repo.call('setAvatar', {'path': path});
            },
          ),
          Text(
            profile['name'],
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            '${AccountRole.parse(role).label} · ${profile['location']}',
            textAlign: TextAlign.center,
          ),
          Text(
            profile['verified'] == true ? 'Verified business' : 'Not verified',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Business verification'),
            onTap: () => page(const VerificationScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Account details & deletion'),
            onTap: () => page(AccountSettings(profile: profile)),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & support'),
            onTap: () => page(const SupportScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(
              role == 'buyer'
                  ? 'Delivery addresses'
                  : 'Pickup & service locations',
            ),
            onTap: () => page(const AddressesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(
              role == 'buyer'
                  ? 'My buying requests'
                  : role == 'supplier'
                  ? 'My products'
                  : 'My vehicles',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => page(
              Scaffold(
                appBar: AppBar(title: const Text('My records')),
                body: RecordsList(
                  collection: collection,
                  profile: profile,
                  own: true,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: Text(
              role == 'buyer'
                  ? 'Post buying request'
                  : role == 'supplier'
                  ? 'Add product'
                  : 'Add vehicle',
            ),
            onTap: () =>
                page(RecordEditor(collection: collection, profile: profile)),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Orders & deliveries'),
            onTap: () => page(OrdersScreen(role: role)),
          ),
          if (role != 'logistics')
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(
                role == 'buyer' ? 'Payment history' : 'Sales history',
              ),
              onTap: () => page(FinancialHistory(role: role)),
            ),
          if (role == 'logistics')
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Delivery earnings'),
              onTap: () => page(FinancialHistory(role: role)),
            ),
          if (role != 'logistics')
            ListTile(
              leading: const Icon(Icons.request_quote_outlined),
              title: const Text('Quotations'),
              onTap: () => page(OffersScreen(role: role)),
            ),
          if (role == 'logistics')
            ListTile(
              leading: const Icon(Icons.request_quote_outlined),
              title: const Text('My transport quotes'),
              onTap: () => page(SentTransportQuotes(profile: profile)),
            ),
          if (role == 'buyer')
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Saved suppliers'),
              onTap: () => page(SavedSuppliers(profile: profile)),
            ),
          if (role == 'buyer')
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: const Text('Saved products'),
              onTap: () => page(SavedProducts(profile: profile)),
            ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification settings'),
            onTap: () => page(const NotificationSettings()),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Terms & privacy'),
            onTap: () => page(const PolicyScreen()),
          ),
          AsyncAction(
            label: 'Sign out',
            icon: Icons.logout,
            action: repo.signOut,
          ),
        ],
      ),
    );
  }
}

class SavedProducts extends ConsumerWidget {
  const SavedProducts({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved products')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection('users')
            .doc(repo.uid)
            .collection('savedProducts')
            .snapshots(),
        builder: (context, s) {
          if (s.hasError) {
            return EmptyState(
              'Could not load saved products',
              friendlyError(s.error!),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.docs.isEmpty) {
            return const EmptyState(
              'Nothing saved yet',
              'Save products from their details page.',
            );
          }
          return ListView(
            children: s.data!.docs
                .map(
                  (d) => ListTile(
                    title:
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: repo.db
                              .collection('products')
                              .doc(d.id)
                              .snapshots(),
                          builder: (context, product) => Text(
                            product.data?.exists == false
                                ? 'No longer available'
                                : product.data?.data()?['name'] ??
                                      'Saved product',
                          ),
                        ),
                    onTap: () => openScreen(
                      context,
                      RecordDetails(
                        collection: 'products',
                        id: d.id,
                        profile: profile,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove saved product',
                      icon: const Icon(Icons.bookmark_remove_outlined),
                      onPressed: () =>
                          d.reference.delete().catchError((Object e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(friendlyError(e))),
                              );
                            }
                          }),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.db
            .collection('notifications')
            .where('userId', isEqualTo: repo.uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, s) {
          if (s.hasError) {
            return EmptyState(
              'Could not load notifications',
              friendlyError(s.error!),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.docs.isEmpty) {
            return const EmptyState(
              'You’re all caught up',
              'New messages, offers and order activity will appear here.',
            );
          }
          return ListView(
            children: s.data!.docs
                .map(
                  (d) => ListTile(
                    leading: Icon(
                      d['read'] == true
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(d['title']),
                    subtitle: Text(d['body']),
                    onTap: () async {
                      try {
                        await d.reference.update({'read': true});
                        final profile = await repo.db
                            .collection('users')
                            .doc(repo.uid)
                            .get();
                        if (context.mounted && profile.exists) {
                          await openNotification(
                            context,
                            d.data(),
                            profile.data()!,
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyError(error))),
                          );
                        }
                      }
                    },
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class NotificationSettings extends ConsumerWidget {
  const NotificationSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Enable device notifications to receive marketplace activity. If permission was previously denied, allow notifications in your device settings and retry.',
          ),
          const SizedBox(height: 16),
          AsyncAction(
            label: 'Enable / retry push registration',
            icon: Icons.notifications_active_outlined,
            action: () async {
              final settings = await FirebaseMessaging.instance
                  .requestPermission()
                  .timeout(const Duration(seconds: 20));
              if (settings.authorizationStatus == AuthorizationStatus.denied) {
                throw Exception(
                  'Notifications are disabled. Enable them in device settings, then retry.',
                );
              }
              final token = await FirebaseMessaging.instance.getToken().timeout(
                const Duration(seconds: 20),
              );
              if (token == null) {
                throw Exception(
                  'Could not register this device. Check Firebase messaging configuration and retry.',
                );
              }
              await repo.db
                  .collection('users')
                  .doc(repo.uid)
                  .collection('devices')
                  .doc(token)
                  .set({
                    'token': token,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Device registered for notifications.'),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 16),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: repo.db
                .collection('users')
                .doc(repo.uid)
                .collection('settings')
                .doc('notifications')
                .snapshots(),
            builder: (context, s) {
              if (s.hasError) return Text(friendlyError(s.error!));
              final settings = s.data?.data() ?? {};
              return Column(
                children:
                    [
                          'messages',
                          'orders',
                          'offers',
                          'transport',
                          'requests',
                          'prices',
                          'account',
                        ]
                        .map(
                          (category) => SwitchListTile(
                            title: Text(
                              category[0].toUpperCase() + category.substring(1),
                            ),
                            value: settings[category] != false,
                            onChanged: (value) => repo.db
                                .collection('users')
                                .doc(repo.uid)
                                .collection('settings')
                                .doc('notifications')
                                .set({category: value}, SetOptions(merge: true))
                                .catchError((Object e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(friendlyError(e))),
                                    );
                                  }
                                }),
                          ),
                        )
                        .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
