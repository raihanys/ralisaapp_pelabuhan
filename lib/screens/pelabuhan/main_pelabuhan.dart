import 'package:flutter/material.dart';
import 'inbox_pelabuhan.dart';
import 'process_pelabuhan.dart';
import 'archive_pelabuhan.dart';
import '../login_screen.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/pelabuhan_service.dart';

class MainPelabuhan extends StatefulWidget {
  const MainPelabuhan({Key? key}) : super(key: key);

  @override
  _MainPelabuhanState createState() => _MainPelabuhanState();
}

class _MainPelabuhanState extends State<MainPelabuhan> {
  int _currentIndex = 0;
  List<dynamic> inboxOrders = [];
  List<dynamic> processOrders = [];
  List<dynamic> archiveOrders = [];
  bool _isLoading = true;
  Timer? _timer;
  late PelabuhanService _pelabuhanService;

  @override
  void initState() {
    super.initState();
    _pelabuhanService = PelabuhanService();
    _initializeNotifications();
    _isLoading = true;
    _fetchOrders();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchOrders();
    });
  }

  Future<void> _initializeNotifications() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'order_service_channel',
      'Order Service Channel',
      description: 'RalisaApp Service',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await _pelabuhanService.initializeService();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    await Future.delayed(Duration(seconds: 1));
    setState(() => _isLoading = true);

    try {
      final orders = await _pelabuhanService.fetchOrders();

      final prefs = await SharedPreferences.getInstance();
      // Ambil data order dari shared_preferences
      final storedOrdersString = prefs.getString('orders');
      final List<dynamic> storedOrders =
          storedOrdersString != null
              ? List<dynamic>.from(jsonDecode(storedOrdersString))
              : [];

      _checkForNewOrdersNotification(storedOrders, orders); // Panggil di sini

      orders.sort((a, b) {
        final tglA = a['keluar_pabrik_tgl'] ?? '';
        final jamA = a['keluar_pabrik_jam'] ?? '';
        final tglB = b['keluar_pabrik_tgl'] ?? '';
        final jamB = b['keluar_pabrik_jam'] ?? '';

        final dateTimeA = DateTime.tryParse('$tglA $jamA') ?? DateTime(2000);
        final dateTimeB = DateTime.tryParse('$tglB $jamB') ?? DateTime(2000);
        return dateTimeA.compareTo(dateTimeB);
      });

      final draftStringList = prefs.getStringList('rc_drafts') ?? [];
      final rawDraftOrders = draftStringList.map((e) => jsonDecode(e)).toList();

      final cleanedDraftOrders =
          rawDraftOrders.where((o) {
            final tglRC = (o['tgl_rc_dibuat'] ?? '').toString().trim();
            final jamRC = (o['jam_rc_dibuat'] ?? '').toString().trim();
            final fotoRC = (o['foto_rc'] ?? '').toString().trim();
            final isAllFilled =
                fotoRC.isNotEmpty && tglRC.isNotEmpty && jamRC.isNotEmpty;
            return !isAllFilled;
          }).toList();

      prefs.setStringList(
        'rc_drafts',
        cleanedDraftOrders.map((e) => jsonEncode(e)).toList(),
      );

      final draftSoIds =
          cleanedDraftOrders.map((e) => e['so_id'] as String).toList();

      print("Orders received: $orders");

      setState(() {
        inboxOrders =
            orders.where((o) {
              final noRo = (o['no_ro'] ?? '').toString().trim();
              if (noRo.isEmpty) return false;

              final fotoRC = o['foto_rc'];
              final soId = o['so_id']?.toString() ?? '';

              return (fotoRC == null || fotoRC.toString().trim().isEmpty) &&
                  !draftSoIds.contains(soId);
            }).toList();

        processOrders =
            cleanedDraftOrders.where((o) {
              final noRo = (o['no_ro'] ?? '').toString().trim();
              final tglRC = (o['tgl_rc_dibuat'] ?? '').toString().trim();
              final jamRC = (o['jam_rc_dibuat'] ?? '').toString().trim();
              final soId = o['so_id'].toString();

              if (noRo.isEmpty) return false;

              final isIncomplete = tglRC.isEmpty || jamRC.isEmpty;
              final isAlreadyArchived = orders.any((order) {
                final orderSoId = order['so_id'].toString();
                final fotoDone =
                    (order['foto_rc'] ?? '').toString().trim().isNotEmpty;
                return orderSoId == soId && fotoDone;
              });

              return isIncomplete && !isAlreadyArchived;
            }).toList();

        archiveOrders =
            orders.where((o) {
              final noRo = (o['no_ro'] ?? '').toString().trim();
              if (noRo.isEmpty) return false;

              final fotoRC = (o['foto_rc'] ?? '').toString().trim();
              return fotoRC.isNotEmpty;
            }).toList();

        archiveOrders.sort((b, a) {
          final tglA = a['tgl_rc_dibuat'] ?? '';
          final jamA = a['jam_rc_dibuat'] ?? '';
          final tglB = b['tgl_rc_dibuat'] ?? '';
          final jamB = b['jam_rc_dibuat'] ?? '';

          final dateTimeA = DateTime.tryParse('$tglA $jamA') ?? DateTime(2000);
          final dateTimeB = DateTime.tryParse('$tglB $jamB') ?? DateTime(2000);
          return dateTimeA.compareTo(dateTimeB);
        });

        _isLoading = false;

        // Bersihkan lastNotifiedSoIds jika order sudah di-archive
        final archivedSoIds =
            archiveOrders.map((order) => order['so_id'].toString()).toList();
        final lastNotifiedSoIdsString = prefs.getString('lastNotifiedSoIds');
        if (lastNotifiedSoIdsString != null) {
          List<String> lastNotifiedSoIds = List<String>.from(
            jsonDecode(lastNotifiedSoIdsString),
          );
          lastNotifiedSoIds.removeWhere((soId) => archivedSoIds.contains(soId));
          prefs.setString('lastNotifiedSoIds', jsonEncode(lastNotifiedSoIds));
        }
      });
    } catch (e) {
      print('Error fetching orders: $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data: ${e.toString()}')),
      );
    }
  }

  Future<void> _checkForNewOrdersNotification(
    List<dynamic> storedOrders,
    List<dynamic> currentOrders,
  ) async {
    if (currentOrders.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastNotifiedSoIdsString = prefs.getString('lastNotifiedSoIds');
    List<String> lastNotifiedSoIds =
        lastNotifiedSoIdsString != null
            ? List<String>.from(jsonDecode(lastNotifiedSoIdsString))
            : [];

    final newOrders =
        currentOrders.where((order) {
          final soId = order['so_id'].toString();
          final fotoRC = (order['foto_rc'] ?? '').toString().trim();

          // Cari order yang sesuai di storedOrders
          final storedOrder = storedOrders.firstWhere(
            (stored) => stored['so_id'].toString() == soId,
            orElse: () => null,
          );

          // Jika order ditemukan di storedOrders, gunakan foto_rc dari storedOrders
          final checkFotoRC =
              storedOrder != null
                  ? (storedOrder['foto_rc'] ?? '').toString().trim()
                  : fotoRC;

          return checkFotoRC.isEmpty && !lastNotifiedSoIds.contains(soId);
        }).toList();

    if (newOrders.isNotEmpty) {
      for (final newOrder in newOrders) {
        await _pelabuhanService.showNewOrderNotification(
          orderId: newOrder['so_id'].toString(),
          noRo: newOrder['no_ro']?.toString() ?? 'No RO',
        );
        lastNotifiedSoIds.add(newOrder['so_id'].toString());
      }
      await prefs.setString('lastNotifiedSoIds', jsonEncode(lastNotifiedSoIds));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(150.0),
        child: SafeArea(child: _buildCustomAppBar(context, _currentIndex)),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : IndexedStack(
                index: _currentIndex,
                children: [
                  InboxPelabuhan(
                    orders: inboxOrders,
                    onOrderUpdated: _fetchOrders,
                  ),
                  ProcessPelabuhan(
                    orders: processOrders,
                    onOrderUpdated: _fetchOrders,
                  ),
                  ArchivePelabuhan(
                    orders: archiveOrders,
                    onOrderUpdated: _fetchOrders,
                  ),
                ],
              ),
      bottomNavigationBar: _buildFloatingNavBar(theme),
    );
  }

  Widget _buildCustomAppBar(BuildContext context, int currentIndex) {
    String title = '';
    switch (currentIndex) {
      case 0:
        title = 'Inbox';
        break;
      case 1:
        title = 'Process';
        break;
      case 2:
        title = 'Archive';
        break;
    }

    return Container(
      decoration: const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/images/logo.png', height: 40, width: 200),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    await _pelabuhanService.logout();
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  child: const Text('Logout'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Aplikasi Pelabuhan',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: theme.colorScheme.surface,
          selectedItemColor: theme.colorScheme.primary,
          unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.6),
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.inbox_outlined),
              activeIcon: Icon(Icons.inbox),
              label: 'Inbox',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.timer_outlined),
              activeIcon: Icon(Icons.timer),
              label: 'Process',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.archive_outlined),
              activeIcon: Icon(Icons.archive),
              label: 'Archive',
            ),
          ],
        ),
      ),
    );
  }
}
