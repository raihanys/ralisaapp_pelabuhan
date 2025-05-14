import 'package:flutter/material.dart';
import '../../form/form_rc_pelabuhan.dart';

class ProcessPelabuhan extends StatefulWidget {
  final List<dynamic> orders;
  final Function onOrderUpdated;

  const ProcessPelabuhan({
    Key? key,
    required this.orders,
    required this.onOrderUpdated,
  }) : super(key: key);

  @override
  State<ProcessPelabuhan> createState() => _ProcessPelabuhanState();
}

class _ProcessPelabuhanState extends State<ProcessPelabuhan> {
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
                      Text(
                        'Mohon Segera Lengkapi Data RC!',
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
                    child: const Text("Lanjut"),
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
