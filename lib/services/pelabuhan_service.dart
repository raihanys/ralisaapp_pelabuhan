import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import 'package:device_info_plus/device_info_plus.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void pelabuhanOnStart(ServiceInstance service) async {
  final pelabuhanService = PelabuhanService();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  try {
    final token = await pelabuhanService.getValidToken();
    if (token == null) {
      await service.stopSelf();
      return;
    }
    await pelabuhanService._checkForNewOrders(service);
  } catch (e) {
    print('Background service error: $e');
  }
}

class PelabuhanService {
  final String _loginUrl =
      'http://192.168.20.65/ralisa_api/index.php/api/login';
  // final String _loginUrl = 'https://api3.ralisa.co.id/index.php/api/login';
  final String _ordersUrl =
      'http://192.168.20.65/ralisa_api/index.php/api/get_new_salesorder_for_krani_pelabuhan';
  // final String _ordersUrl =
  //     'https://api3.ralisa.co.id/index.php/api/get_new_salesorder_for_krani_pelabuhan';
  final String _submitRcUrl =
      'http://192.168.20.65/ralisa_api/index.php/api/agent_create_rc';
  // final String _submitRcUrl =
  //     'https://api3.ralisa.co.id/index.php/api/agent_create_rc';

  Future<String> _getDeviceImei() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id;
  }

  Future<Map<String, dynamic>?> login({
    required String username,
    required String password,
  }) async {
    // final imei = 'ac9ba078-0a12-45ad-925b-2d761ad9770f';
    final imei = await _getDeviceImei();
    final _loginConfigs = [
      {
        'role': '3', // Pelabuhan
        'versions': ['1.0'],
      },
    ];

    for (final config in _loginConfigs) {
      final role = config['role'] as String;
      for (final version in config['versions'] as List<String>) {
        try {
          final body = {
            'username': username,
            'password': password,
            'type': role,
            'version': version,
            'imei': imei,
            'firebase': 'dummy_token',
          };

          final res = await http
              .post(
                Uri.parse(_loginUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 5));

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data['error'] == false && data['data'] != null) {
              final user = data['data'];
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isLoggedIn', true);
              await prefs.setString('username', username);
              await prefs.setString('password', password);
              await prefs.setString('role', role);
              await prefs.setString('version', version);
              await prefs.setString('token', user['token'] ?? '');
              return user;
            }
          }
        } catch (e) {}
      }
    }
    return null;
  }

  Future<void> logout() async {
    try {
      // Hentikan background service dengan cara yang benar
      final service = FlutterBackgroundService();
      service.invoke(
        'stopService',
      ); // Ini akan diproses di pelabuhanOnStart jika kamu atur

      // Hapus semua data login
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      print("Logout berhasil, service dihentikan dan data dibersihkan.");
    } catch (e) {
      print("Gagal logout: $e");
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  Future<void> saveAuthData(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('token_saved_at', DateTime.now().toIso8601String());
  }

  Future<String?> getValidToken() async {
    final currentToken = await getToken();
    if (currentToken == null) return null;
    if (await isTokenValid()) return currentToken;
    return await softLoginRefresh();
  }

  Future<bool> isTokenValid() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAt = prefs.getString('token_saved_at');
    if (savedAt == null) return false;
    return DateTime.now().difference(DateTime.parse(savedAt)).inHours < 12;
  }

  Future<String?> softLoginRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final password = prefs.getString('password');
    if (username == null || password == null) return null;
    try {
      final result = await login(username: username, password: password);
      return result?['token'];
    } catch (e) {
      return null;
    }
  }

  // Fungsi PelabuhanService Asli
  Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: pelabuhanOnStart,
        isForegroundMode: true,
        autoStart: true,
        notificationChannelId: 'order_service_channel',
        initialNotificationTitle: 'Ralisa App Service',
        initialNotificationContent: 'Monitoring Progress...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: pelabuhanOnStart,
        onBackground: (_) async => true,
      ),
    );
    await service.startService();

    const String groupKey = 'com.ralisa.group.RO_NOTIF';

    const AndroidNotificationDetails summaryAndroidDetails =
        AndroidNotificationDetails(
          'order_service_channel',
          'Order Service Channel',
          channelDescription: 'Ralisa Background Service',
          groupKey: groupKey,
          setAsGroupSummary: true,
          importance: Importance.low,
          priority: Priority.low,
          showWhen: false,
        );

    const NotificationDetails summaryPlatformDetails = NotificationDetails(
      android: summaryAndroidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      999999, // summary notif ID
      'Ralisa App Service',
      'Monitoring Progress...',
      summaryPlatformDetails,
    );
  }

  Future<List<dynamic>> fetchOrders() async {
    final token = await getValidToken();
    if (token == null) return [];
    final response = await http.get(Uri.parse('$_ordersUrl?token=$token'));
    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      return jsonData['data'] is List ? jsonData['data'] : [];
    }
    return [];
  }

  Future<bool> submitRC({
    required String soId,
    required String containerNum,
    required String sealNumber,
    required String sealNumber2,
    required String fotoRcPath,
    required String agent,
  }) async {
    final token = await getValidToken();
    if (token == null) return false;

    final request =
        http.MultipartRequest('POST', Uri.parse(_submitRcUrl))
          ..fields.addAll({
            'so_id': soId,
            'container_num': containerNum,
            'seal_number': sealNumber,
            'seal_number2': sealNumber2,
            'agent': agent,
            'token': token,
          })
          ..files.add(
            await http.MultipartFile.fromPath(
              'foto_rc',
              fotoRcPath,
              contentType: MediaType('image', 'jpeg'),
            ),
          );

    final response = await request.send();
    final resBody = await response.stream.bytesToString();
    final data = jsonDecode(resBody);

    if (response.statusCode == 401 || data['error'] == true) {
      final newToken = await softLoginRefresh();
      if (newToken != null) {
        return submitRC(
          soId: soId,
          containerNum: containerNum,
          sealNumber: sealNumber,
          sealNumber2: sealNumber2,
          fotoRcPath: fotoRcPath,
          agent: agent,
        );
      }
    }
    return response.statusCode == 200 &&
        (data['status'] == true || data['error'] == false);
  }

  Future<void> _checkForNewOrders(ServiceInstance service) async {
    try {
      final token = await getValidToken();
      if (token == null) {
        service.invoke('force_relogin');
        return;
      }

      final response = await http.get(Uri.parse('$_ordersUrl?token=$token'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = json.decode(response.body);
        if (jsonData.containsKey('data') && jsonData['data'] is List) {
          final List<dynamic> orders = jsonData['data'];
          if (orders.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            // Simpan data order ke shared_preferences
            await prefs.setString('orders', jsonEncode(orders));
            final lastOrderId = prefs.getString('lastOrderId');
            final newOrder = orders.first;
            final currentOrderId = newOrder['so_id'].toString();

            if (currentOrderId != lastOrderId) {
              await prefs.setString('lastOrderId', currentOrderId);
              await showNewOrderNotification(
                orderId: currentOrderId,
                noRo: newOrder['no_ro']?.toString() ?? 'No RO',
              );
            }
          }
        }
      }
    } catch (e) {
      print('Error in _checkForNewOrders: $e');
    }
  }

  Future<void> showNewOrderNotification({
    required String orderId,
    required String noRo,
  }) async {
    const String groupKey = 'com.ralisa.group.RO_NOTIF'; // harus sama

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'order_service_channel',
          'Order Service Channel',
          channelDescription: 'New order notifications from background service',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          groupKey: groupKey,
          setAsGroupSummary: false, // ⬅️ Penting: jangan jadi summary
          groupAlertBehavior: GroupAlertBehavior.all,
          styleInformation: BigTextStyleInformation(
            'Nomor RO: $noRo',
            contentTitle: 'Data RO Baru Masuk!',
            htmlFormatContentTitle: true,
          ),
        );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    final notificationId = int.tryParse(orderId) ?? orderId.hashCode;

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      'Data RO Baru Masuk!',
      'Nomor RO: $noRo',
      platformDetails,
      payload: 'order_$orderId',
    );
  }
}
