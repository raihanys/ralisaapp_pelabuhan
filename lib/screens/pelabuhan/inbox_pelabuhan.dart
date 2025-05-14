import 'package:flutter/material.dart';
import '../../form/form_rc_pelabuhan.dart';
import 'package:intl/intl.dart';

class InboxPelabuhan extends StatefulWidget {
  final List<dynamic> orders;
  final Function onOrderUpdated;

  const InboxPelabuhan({
    Key? key,
    required this.orders,
    required this.onOrderUpdated,
  }) : super(key: key);

  @override
  State<InboxPelabuhan> createState() => _InboxPelabuhanState();
}

class _InboxPelabuhanState extends State<InboxPelabuhan> {
  late List<dynamic> _orders;
  late Function onOrderUpdated;

  @override
  void initState() {
    super.initState();
    _orders = widget.orders;
    onOrderUpdated = widget.onOrderUpdated;
  }

  void _refreshOrders() {
    setState(() {
      _orders = List.from(_orders);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_orders.isEmpty) {
      return Center(
        child: Text(
          "Tidak ada data",
          style: theme.textTheme.titleMedium!.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _orders.length,
            itemBuilder: (context, index) {
              final order = _orders[index];
              final roNumber = order['no_ro'] ?? '-';

              final rawDate = order['keluar_pabrik_tgl'];
              final rawTime = order['keluar_pabrik_jam'];

              String formattedDate = '-';
              String formattedTime = '-';

              if (rawDate != null) {
                final parsedDate = DateTime.tryParse(rawDate);
                if (parsedDate != null) {
                  formattedDate = DateFormat('dd/MM/yyyy').format(parsedDate);
                }
              }

              if (rawTime != null) {
                try {
                  final parsedTime = DateFormat('HH:mm:ss').parse(rawTime);
                  formattedTime =
                      '${DateFormat('HH:mm').format(parsedTime)} WIB';
                } catch (_) {}
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(
                    'Nomor RO: $roNumber',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tanggal Keluar Pabrik: $formattedDate',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Jam Keluar Pabrik: $formattedTime',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'RC Perlu di Proses!',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[300],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => FormPelabuhanScreen(order: order),
                        ),
                      );

                      onOrderUpdated();

                      if (result == true) {
                        _refreshOrders();
                      }
                    },
                    child: const Text("Proses"),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
