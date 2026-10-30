import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/repository.dart';
import '../core/models.dart';
import '../shared/widgets.dart';

class TransportEstimatePanel extends ConsumerStatefulWidget {
  const TransportEstimatePanel({
    super.key,
    required this.productId,
    required this.quantity,
    required this.destination,
    required this.price,
  });
  final String productId;
  final TextEditingController quantity, destination;
  final num price;
  @override
  ConsumerState<TransportEstimatePanel> createState() =>
      _TransportEstimatePanelState();
}

class _TransportEstimatePanelState
    extends ConsumerState<TransportEstimatePanel> {
  Map<String, dynamic>? result;
  String? signature;
  @override
  void initState() {
    super.initState();
    widget.quantity.addListener(clear);
    widget.destination.addListener(clear);
  }

  void clear() {
    if (result != null) setState(() => result = null);
  }

  @override
  void dispose() {
    widget.quantity.removeListener(clear);
    widget.destination.removeListener(clear);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Delivery fees are estimates until a transporter confirms a quotation.',
      ),
      AsyncAction(
        label: 'Calculate road transport estimate',
        icon: Icons.local_shipping_outlined,
        action: () async {
          final quantity = positiveNumber(widget.quantity.text),
              destination = widget.destination.text.trim();
          if (destination.isEmpty) {
            throw Exception('Enter a delivery destination.');
          }
          final input = '${widget.quantity.text}|${widget.destination.text}';
          final estimate = await ref.read(repositoryProvider).call(
            'estimateTransport',
            {
              'productId': widget.productId,
              'quantity': quantity,
              'destination': destination,
            },
          );
          if (mounted &&
              input == '${widget.quantity.text}|${widget.destination.text}') {
            setState(() {
              result = estimate;
              signature = input;
            });
          }
        },
      ),
      if (result != null) ...[
        Text(result!['reason']),
        if (result!['roadKm'] != null)
          Text(
            'Road distance: ${(result!['roadKm'] as num).toStringAsFixed(1)} km',
          ),
        for (final estimate in (result!['estimates'] as List? ?? []))
          ListTile(
            title: Text(
              '${estimate['name']}: ${money(estimate['amount'], result!['currency'] ?? 'USD')} estimated',
            ),
            subtitle: Text(
              'Estimated total: ${money((double.tryParse(widget.quantity.text) ?? 0) * widget.price + (estimate['amount'] as num), result!['currency'] ?? 'USD')}',
            ),
          ),
      ],
    ],
  );
}
