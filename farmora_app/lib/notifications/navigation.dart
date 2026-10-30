import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../marketplace/details.dart';
import '../messaging/messages.dart';
import '../orders/orders.dart';
import '../profile/verification.dart';
import '../shared/widgets.dart';

Future<void> openNotification(
  BuildContext context,
  Map<String, dynamic> notification,
  Map<String, dynamic> profile,
) async {
  final target = Map<String, dynamic>.from(
    notification['target'] as Map? ?? {},
  );
  final id = target['id'];
  final role = profile['role'] as String;
  final Widget? screen = switch (target['kind']) {
    'chat' when id is String => ChatScreen(id: id, title: 'Conversation'),
    'order' when id is String => OrderScreen(id: id, role: role),
    'offers' => OffersScreen(role: role),
    'products' || 'buyerRequests' when id is String => RecordDetails(
      collection: target['kind'],
      id: id,
      profile: profile,
    ),
    'verification' => const VerificationScreen(),
    _ => null,
  };
  if (screen != null && context.mounted) openScreen(context, screen);
}

Future<void> openPushNotification(
  BuildContext context,
  Map<String, dynamic> payload,
  Map<String, dynamic> profile,
  String uid,
) async {
  if (payload['userId'] != uid || payload['notificationId'] is! String) return;
  final reference = FirebaseFirestore.instance
      .collection('notifications')
      .doc(payload['notificationId']);
  final snapshot = await reference.get();
  if (!snapshot.exists || snapshot.data()?['userId'] != uid) return;
  await reference.update({'read': true});
  if (context.mounted) {
    await openNotification(context, snapshot.data()!, profile);
  }
}
