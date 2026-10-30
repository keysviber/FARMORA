import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/repository.dart';
import '../orders/delivery_proof.dart';
import '../shared/widgets.dart';

class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});
  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final description = TextEditingController();
  String? uploadedPath;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Business verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Submit a clear photo of your business registration or operating permit. Documents are private to you and authorized administrators. Submission does not grant a verification badge.',
          ),
          const SizedBox(height: 16),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: repo.db
                .collection('verificationRequests')
                .doc(repo.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(friendlyError(snapshot.error!));
              }
              final record = snapshot.data?.data();
              if (record == null) {
                return const Text('No verification request submitted.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Review status: ${record['status']}'),
                  if (record['reason'] != null)
                    Text('Reviewer feedback: ${record['reason']}'),
                  PrivateImage(path: record['path']),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          FormFieldInput(
            description,
            'Document type and business details',
            lines: 3,
          ),
          AsyncAction(
            label: 'Choose document photo',
            icon: Icons.upload_file,
            action: () async {
              final selected = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 2000,
                imageQuality: 85,
              );
              if (selected == null) return;
              final bytes = await selected.readAsBytes();
              if (bytes.length >= 5 * 1024 * 1024) {
                throw Exception('Choose a photo smaller than 5 MB.');
              }
              final path =
                  'verification/${repo.uid}/${repo.db.collection('uploads').doc().id}.jpg';
              await FirebaseStorage.instance
                  .ref(path)
                  .putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
              if (mounted) setState(() => uploadedPath = path);
            },
          ),
          if (uploadedPath != null) PrivateImage(path: uploadedPath!),
          AsyncAction(
            label: 'Submit for review',
            action: () async {
              if (uploadedPath == null || description.text.trim().isEmpty) {
                throw Exception('Add a document photo and description first.');
              }
              await repo.call('submitVerification', {
                'path': uploadedPath,
                'description': description.text.trim(),
              });
              if (context.mounted) {
                setState(() => uploadedPath = null);
                description.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Documents submitted for review.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
