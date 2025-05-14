import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ArchivePelabuhan extends StatelessWidget {
  final List<dynamic> orders;
  final Function onOrderUpdated;

  const ArchivePelabuhan({
    Key? key,
    required this.orders,
    required this.onOrderUpdated,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (orders.isEmpty) {
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
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final roNumber = order['no_ro'] ?? '-';
              final user = order['agent'];

              final rawDate = order['tgl_rc_dibuat'];
              final rawTime = order['jam_rc_dibuat'];

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
                  formattedTime = DateFormat('HH:mm').format(parsedTime);
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
                            'Tanggal RC Diproses: $formattedDate',
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
                            'Jam RC Diproses: $formattedTime',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Diproses oleh: $user',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
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
