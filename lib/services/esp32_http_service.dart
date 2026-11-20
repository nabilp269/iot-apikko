import 'dart:convert';

import 'package:http/http.dart' as http;

class Esp32HttpService {
  static const sensorUrl = String.fromEnvironment(
    'SENSOR_API_URL',
    defaultValue: 'http://127.0.0.1:8000/api/sensor-latest',
  );

  static Future<Map<String, dynamic>> fetchSensors() async {
    final uri = Uri.parse(sensorUrl);
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) {
      throw Exception('Server API mengembalikan HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Format response tidak valid');
    final data = decoded['data'] ?? decoded;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
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
