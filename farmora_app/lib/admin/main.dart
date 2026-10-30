import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/config.dart';
import '../core/services.dart';
import '../shared/widgets.dart';
import '../orders/delivery_proof.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  if (FirebaseConfig.configured) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      await initializeServices();
    } catch (_) {
      error = 'Firebase initialization failed. Check the admin configuration.';
    }
  }
  runApp(
    MaterialApp(
      title: 'Farmora Administration',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xff237548),
        useMaterial3: true,
      ),
      home: !FirebaseConfig.configured || error != null
          ? Scaffold(
              body: EmptyState(
                'Admin configuration required',
                error ?? 'Supply the Firebase web configuration.',
              ),
            )
          : const AdminGate(),
    ),
  );
}

class AdminGate extends StatelessWidget {
  const AdminGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.idTokenChanges(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const AdminLogin();
      return FutureBuilder<IdTokenResult>(
        future: snapshot.data!.getIdTokenResult(),
        builder: (context, token) {
          if (!token.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (token.data!.claims?['admin'] != true) {
            return Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const EmptyState(
                    'Administrator access required',
                    'This account has no server-issued administrator privileges.',
                  ),
                  TextButton(
                    onPressed: FirebaseAuth.instance.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            );
          }
          return const AdminDashboard();
        },
      );
    },
  );
}

class AdminLogin extends StatefulWidget {
  const AdminLogin({super.key});
  @override
  State<AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<AdminLogin> {
  final email = TextEditingController(), password = TextEditingController();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Farmora Administration',
                style: TextStyle(fontSize: 26),
              ),
              const SizedBox(height: 24),
              FormFieldInput(email, 'Administrator email'),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 24),
              AsyncAction(
                label: 'Sign in',
                action: () async {
                  await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: email.text.trim(),
                    password: password.text,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String collection = 'users';
  Future<Map<String, dynamic>>? result;
  final records = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    (await FirebaseFunctions.instanceFor(region: 'africa-south1')
                .httpsCallable(name)
                .call(data))
            .data
        as Map,
  );
  @override
  void initState() {
    super.initState();
    result = call('adminList', {'collection': collection});
  }

  void refresh() => setState(() {
    records.clear();
    result = call('adminList', {'collection': collection});
  });
  Future<void> editCategory() async {
    final name = TextEditingController(), reason = TextEditingController();
    bool active = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manage category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Category name'),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              SwitchListTile(
                title: const Text('Available for new listings'),
                value: active,
                onChanged: (value) => setDialogState(() => active = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final categoryName = name.text.trim(), auditReason = reason.text.trim();
    name.dispose();
    reason.dispose();
    if (accepted != true) return;
    await call('manageCategory', {
      'name': categoryName,
      'active': active,
      'reason': auditReason,
    });
    if (mounted) {
      collection = 'categories';
      refresh();
    }
  }

  Future<void> editCurrencies() async {
    final codes = TextEditingController(text: 'USD'),
        reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marketplace currencies'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Supported: USD, ZWG, ZAR, BWP, EUR, GBP. Keep USD enabled. Prices are never converted between currencies.',
            ),
            TextField(
              controller: codes,
              decoration: const InputDecoration(
                labelText: 'Enabled codes, separated by commas',
              ),
            ),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final currencies = codes.text
            .split(',')
            .map((value) => value.trim().toUpperCase())
            .toList(),
        auditReason = reason.text.trim();
    codes.dispose();
    reason.dispose();
    if (accepted != true) return;
    await call('configureCurrencies', {
      'currencies': currencies,
      'reason': auditReason,
    });
    if (mounted) {
      collection = 'platformSettings';
      refresh();
    }
  }

  Future<void> act(String action, String id, {String? outcome}) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(action),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason / reconciliation reference',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    if (reason.trim().isEmpty) throw Exception('A reason is required.');
    await call('adminAction', {
      'action': action,
      'id': id,
      'reason': reason,
      'outcome': ?outcome,
    });
    refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Farmora Administration'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
        ),
        TextButton(
          onPressed: FirebaseAuth.instance.signOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AsyncAction(label: 'Manage categories', action: editCategory),
              AsyncAction(
                label: 'Configure currencies',
                action: editCurrencies,
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            children:
                [
                      'users',
                      'products',
                      'orders',
                      'payments',
                      'reports',
                      'vehicles',
                      'transportRequests',
                      'verificationRequests',
                      'categories',
                      'platformSettings',
                    ]
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: collection == c,
                          onSelected: (_) {
                            collection = c;
                            refresh();
                          },
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: result,
            builder: (context, s) {
              if (s.hasError) {
                return EmptyState(
                  'Administration unavailable',
                  friendlyError(s.error!),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final page = (s.data!['records'] as List)
                  .map((r) => Map<String, dynamic>.from(r as Map))
                  .toList();
              final all = [...records, ...page];
              if (all.isEmpty) {
                return const EmptyState(
                  'No records',
                  'No records in this collection.',
                );
              }
              return ListView(
                children: [
                  for (final r in all)
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['name'] ?? r['id'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            SelectableText(r.toString()),
                            if (collection == 'verificationRequests')
                              PrivateImage(path: r['path']),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (collection == 'verificationRequests' &&
                                    r['status'] == 'pending') ...[
                                  AsyncAction(
                                    label: 'Approve documents',
                                    action: () =>
                                        act('approveVerification', r['id']),
                                  ),
                                  AsyncAction(
                                    label: 'Reject documents',
                                    action: () =>
                                        act('rejectVerification', r['id']),
                                  ),
                                ],
                                if (collection == 'users') ...[
                                  if (r['role'] == 'supplier' &&
                                      r['verified'] == true)
                                    AsyncAction(
                                      label: r['featured'] == true
                                          ? 'Unfeature supplier'
                                          : 'Feature supplier',
                                      action: () => act(
                                        r['featured'] == true
                                            ? 'unfeatureSupplier'
                                            : 'featureSupplier',
                                        r['id'],
                                      ),
                                    ),
                                  AsyncAction(
                                    label: 'Verify',
                                    action: () => act('verify', r['id']),
                                  ),
                                  AsyncAction(
                                    label: r['suspended'] == true
                                        ? 'Reinstate'
                                        : 'Suspend',
                                    action: () => act(
                                      r['suspended'] == true
                                          ? 'reinstate'
                                          : 'suspend',
                                      r['id'],
                                    ),
                                  ),
                                ],
                                if (collection == 'reports' &&
                                    r['status'] == 'open')
                                  AsyncAction(
                                    label: 'Resolve report / support request',
                                    action: () => act('resolveReport', r['id']),
                                  ),
                                if (collection == 'products')
                                  AsyncAction(
                                    label: 'Pause listing',
                                    action: () =>
                                        act('moderateProduct', r['id']),
                                  ),
                                if (collection == 'payments' &&
                                    r['status'] == 'awaitingVerification') ...[
                                  AsyncAction(
                                    label: 'Reconcile as paid',
                                    action: () => act('verifyPayment', r['id']),
                                  ),
                                  AsyncAction(
                                    label: 'Reject',
                                    action: () => act('rejectPayment', r['id']),
                                  ),
                                ],
                                if (collection == 'payments' &&
                                    r['status'] == 'paid')
                                  AsyncAction(
                                    label: 'Record verified refund',
                                    action: () => act('refundPayment', r['id']),
                                  ),
                                if (collection == 'orders' &&
                                    r['status'] == 'deliveryFailed') ...[
                                  AsyncAction(
                                    label: 'Retry delivery',
                                    action: () => act('retryDelivery', r['id']),
                                  ),
                                  if (r['paymentStatus'] == 'pending')
                                    AsyncAction(
                                      label: 'Reassign delivery',
                                      action: () =>
                                          act('reassignDelivery', r['id']),
                                    ),
                                ],
                                if (collection == 'orders' &&
                                    [
                                      'disputed',
                                      'deliveryFailed',
                                    ].contains(r['status'])) ...[
                                  AsyncAction(
                                    label: 'Resolve completed',
                                    action: () => act(
                                      'resolveDispute',
                                      r['id'],
                                      outcome: 'completed',
                                    ),
                                  ),
                                  AsyncAction(
                                    label: 'Resolve cancelled',
                                    action: () => act(
                                      'resolveDispute',
                                      r['id'],
                                      outcome: 'cancelled',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (page.length == 50)
                    TextButton(
                      onPressed: () => setState(() {
                        records.addAll(page);
                        result = call('adminList', {
                          'collection': collection,
                          'after': s.data!['after'],
                        });
                      }),
                      child: const Text('Load more'),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
