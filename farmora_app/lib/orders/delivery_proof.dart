import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/repository.dart';
import '../shared/widgets.dart';

class DeliveryProofPanel extends ConsumerWidget {
  const DeliveryProofPanel({
    super.key,
    required this.orderId,
    this.path,
    required this.canUpload,
  });
  final String orderId;
  final String? path;
  final bool canUpload;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (path != null) PrivateImage(path: path!),
      if (canUpload)
        AsyncAction(
          label: 'Upload proof of delivery',
          icon: Icons.add_a_photo_outlined,
          action: () async {
            final image = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              imageQuality: 75,
            );
            if (image == null) return;
            final bytes = await image.readAsBytes();
            if (bytes.length > 5 * 1024 * 1024) {
              throw Exception('Choose an image smaller than 5 MB.');
            }
            final repo = ref.read(repositoryProvider);
            final location =
                'deliveries/$orderId/${repo.uid}/${repo.db.collection('uploads').doc().id}.jpg';
            await FirebaseStorage.instance
                .ref(location)
                .putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
            await repo.call('submitDeliveryProof', {
              'orderId': orderId,
              'path': location,
            });
          },
        ),
    ],
  );
}

class PrivateImage extends StatefulWidget {
  const PrivateImage({super.key, required this.path});
  final String path;
  @override
  State<PrivateImage> createState() => _PrivateImageState();
}

class _PrivateImageState extends State<PrivateImage> {
  late var image = FirebaseStorage.instance
      .ref(widget.path)
      .getData(5 * 1024 * 1024);
  @override
  void didUpdateWidget(covariant PrivateImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      image = FirebaseStorage.instance
          .ref(widget.path)
          .getData(5 * 1024 * 1024);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: image,
    builder: (context, s) {
      if (s.hasError) return Text(friendlyError(s.error!));
      if (!s.hasData) return const LinearProgressIndicator();
      return SizedBox(
        height: 220,
        child: InteractiveViewer(
          child: Image.memory(s.data!, fit: BoxFit.contain),
        ),
      );
    },
  );
}
