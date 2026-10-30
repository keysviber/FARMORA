import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../core/repository.dart';
import '../orders/delivery_proof.dart';
import '../shared/widgets.dart';
import '../marketplace/details.dart';
import '../orders/orders.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  String search = '';
  int limit = 50;
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: repo.db
                  .collection('conversations')
                  .where('participants', arrayContains: repo.uid)
                  .orderBy('updatedAt', descending: true)
                  .limit(limit)
                  .snapshots(),
              builder: (context, s) {
                if (s.hasError) {
                  return EmptyState(
                    'Could not load conversations',
                    friendlyError(s.error!),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = s.data!.docs
                    .where(
                      (d) =>
                          !(d.data()['hiddenBy'] as List? ?? []).contains(
                            repo.uid,
                          ) &&
                          (d.data()['title'] as String? ?? '')
                              .toLowerCase()
                              .contains(search),
                    )
                    .toList();
                if (docs.isEmpty) {
                  return ListView(
                    children: [
                      const EmptyState(
                        'Start a conversation',
                        'Open a product, buying request or transport job to message its owner.',
                        icon: Icons.chat_bubble_outline,
                      ),
                      if (s.data!.docs.length == limit)
                        TextButton(
                          onPressed: () => setState(() => limit += 50),
                          child: const Text('Search more conversations'),
                        ),
                    ],
                  );
                }
                return ListView(
                  children: [
                    for (final doc in docs)
                      ListTile(
                        leading: Badge(
                          label: Text(
                            '${doc.data()['unread']?[repo.uid] ?? 0}',
                          ),
                          isLabelVisible:
                              (doc.data()['unread']?[repo.uid] ?? 0) > 0,
                          child: const CircleAvatar(
                            child: Icon(Icons.chat_bubble_outline),
                          ),
                        ),
                        title: Text(doc.data()['title'] ?? 'Conversation'),
                        subtitle: Text(
                          doc.data()['lastMessage'] ??
                              'Discuss your requirements',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => openScreen(
                          context,
                          ChatScreen(
                            id: doc.id,
                            title: doc.data()['title'] ?? 'Conversation',
                          ),
                        ),
                      ),
                    if (s.data!.docs.length == limit)
                      TextButton(
                        onPressed: () => setState(() => limit += 50),
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
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.id, required this.title});
  final String id, title;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final text = TextEditingController();
  int limit = 100;
  String? lastRead;
  String? pendingImage;
  String? pendingKey;

  Future<void> sendPhoto() async {
    final repo = ref.read(repositoryProvider);
    if (pendingImage == null) {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 75,
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (bytes.length >= 5 * 1024 * 1024) {
        throw Exception('Choose a photo smaller than 5 MB.');
      }
      final key = repo.db.collection('uploads').doc().id;
      final path = 'chat/${widget.id}/${repo.uid}/$key.jpg';
      await FirebaseStorage.instance
          .ref(path)
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      pendingImage = path;
      pendingKey = key;
    }
    await repo.call('sendMessage', {
      'conversationId': widget.id,
      'text': '',
      'imagePath': pendingImage,
      'requestKey': pendingKey,
    });
    pendingImage = null;
    pendingKey = null;
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> action(String name) async {
    await ref.read(repositoryProvider).call('conversationAction', {
      'conversationId': widget.id,
      'action': name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Open shared record',
            icon: const Icon(Icons.link),
            onPressed: () async {
              try {
                final conversation =
                    (await repo.db
                            .collection('conversations')
                            .doc(widget.id)
                            .get())
                        .data();
                final profile =
                    (await repo.db.collection('users').doc(repo.uid).get())
                        .data();
                if (!context.mounted ||
                    conversation == null ||
                    profile == null) {
                  return;
                }
                final collection = conversation['collection'],
                    recordId = conversation['recordId'];
                if (collection == 'orders') {
                  openScreen(
                    context,
                    OrderScreen(id: recordId, role: profile['role']),
                  );
                } else if ([
                  'products',
                  'buyerRequests',
                  'transportRequests',
                ].contains(collection)) {
                  openScreen(
                    context,
                    RecordDetails(
                      collection: collection,
                      id: recordId,
                      profile: profile,
                    ),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
                }
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              try {
                if (v == 'report') {
                  await repo.call('reportRecord', {
                    'collection': 'conversations',
                    'recordId': widget.id,
                    'reason': 'User reported this conversation for administrator review.',
                  });
                } else {
                  await action(v);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$v completed')));
                  if (v == 'hide') Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
            itemBuilder: (_) => [
              'hide',
              'block',
              'unblock',
              'report',
            ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: repo.db
                  .collection('conversations')
                  .doc(widget.id)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(limit)
                  .snapshots(),
              builder: (context, s) {
                if (s.hasError) {
                  return EmptyState(
                    'Messages unavailable',
                    friendlyError(s.error!),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = s.data!.docs;
                if (docs.isNotEmpty && docs.first.id != lastRead) {
                  lastRead = docs.first.id;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      action('read').catchError((Object e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyError(e))),
                          );
                        }
                      });
                    }
                  });
                }
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: repo.db
                      .collection('conversations')
                      .doc(widget.id)
                      .snapshots(),
                  builder: (context, conversation) => ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final doc in docs)
                        MessageBubble(
                          data: doc.data(),
                          mine: doc.data()['senderId'] == repo.uid,
                          read: messageWasRead(
                            doc.data(),
                            conversation.data?.data() ?? {},
                          ),
                        ),
                      if (docs.length == limit)
                        TextButton(
                          onPressed: () => setState(() => limit += 100),
                          child: const Text('Load earlier messages'),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: text,
                    maxLength: 4000,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      AsyncAction(
                        label: 'Photo',
                        icon: Icons.photo_outlined,
                        action: sendPhoto,
                      ),
                      AsyncAction(
                        label: 'Send',
                        icon: Icons.send,
                        action: () async {
                          if (text.text.trim().isEmpty) return;
                          final sent = text.text;
                          await repo.sendMessage(widget.id, sent);
                          if (text.text == sent) text.clear();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool messageWasRead(
  Map<String, dynamic> message,
  Map<String, dynamic> conversation,
) {
  final timestamp = message['createdAt'];
  if (timestamp is! Timestamp) return false;
  final others = (conversation['participants'] as List? ?? []).where(
    (uid) => uid != message['senderId'],
  );
  final readAt = conversation['readAt'] as Map? ?? {};
  return others.isNotEmpty &&
      others.every(
        (uid) =>
            readAt[uid] is Timestamp &&
            (readAt[uid] as Timestamp).compareTo(timestamp) >= 0,
      );
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.data,
    required this.mine,
    this.read = false,
  });
  final Map<String, dynamic> data;
  final bool mine;
  final bool read;
  @override
  Widget build(BuildContext context) {
    final time = (data['createdAt'] as Timestamp?)?.toDate().toLocal();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Card(
          color: mine ? Theme.of(context).colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['imagePath'] is String)
                  PrivateImage(path: data['imagePath']),
                Text(data['text'] ?? ''),
                if (time != null)
                  Text(
                    '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                if (mine && time != null)
                  Text(
                    read ? 'Read' : 'Sent',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
