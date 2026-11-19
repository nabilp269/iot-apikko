import 'dart:convert';

import 'package:http/http.dart' as http;

class Esp32HttpService {
  // Untuk lokal bisa memakai IP ESP32 langsung.
  // Untuk LocalTunnel, jalankan Flutter dengan:
  // --dart-define=SENSOR_API_URL=https://alamat.loca.lt/api/sensor-latest
  static const sensorUrl = String.fromEnvironment(
    'SENSOR_API_URL',
    defaultValue: 'http://192.168.137.108/sensor',
  );

  static Future<Map<String, dynamic>> fetchSensors() async {
    final uri = Uri.parse(sensorUrl);
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 5));

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
    // Pada Flutter Web, browser memblokir request POST langsung ke IP ESP32 lokal
    // karena aturan CORS Preflight (OPTIONS). Notifikasi tetap dicatat di aplikasi Flutter.
    return false;
  }
}
