import 'dart:convert';

import 'package:http/http.dart' as http;

class Esp32HttpService {
  // Untuk lokal bisa memakai IP ESP32 langsung.
  // Untuk LocalTunnel, jalankan Flutter dengan:
  // --dart-define=SENSOR_API_URL=https://alamat.loca.lt/api/sensor-latest
  static const sensorUrl = String.fromEnvironment(
    'SENSOR_API_URL',
    defaultValue: 'http://192.168.137.118/sensor',
  );

  static Future<Map<String, dynamic>> fetchSensors() async {
    final response = await http
        .get(Uri.parse(sensorUrl), headers: {'Accept': 'application/json'})
        // ESP32 bisa sesekali membutuhkan waktu lebih dari 2 detik saat Wi-Fi
        // sedang sibuk. Jangan terlalu cepat menganggap perangkat offline.
        .timeout(const Duration(seconds: 2));

    if (response.statusCode != 200) {
      throw Exception('ESP32 mengembalikan HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Format response ESP32 tidak valid');
    return Map<String, dynamic>.from(decoded);
  }

  static Future<bool> sendNotification({
    required String sensor,
    required String level,
    required String message,
    required num value,
  }) async {
    try {
      final baseUrl = Uri.parse(sensorUrl);
      final endpoint = baseUrl.replace(path: '/notification', query: null);
      final response = await http
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sensor': sensor,
              'level': level,
              'value': value,
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 3));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      // Notifikasi tidak boleh menghentikan polling sensor.
      return false;
    }
  }
}
