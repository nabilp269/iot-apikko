import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../app_theme.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _enabled = true;
  bool _telegram = true;
  bool _message = false;
  String _schedule = 'Setiap 1 menit';
  bool _saving = false;

  static const _apiKey = String.fromEnvironment('API_KEY');

  String get _apiUrl => kIsWeb
      ? 'http://127.0.0.1:8000/api/notification-schedules'
      : 'http://10.0.2.2:8000/api/notification-schedules';

  Future<void> _save() async {
    if (_apiKey.isEmpty) {
      _showMessage('API key belum diatur. Jalankan dengan --dart-define=API_KEY=...');
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-API-Key': _apiKey,
        },
        body: jsonEncode({
          'sensor_trigger': 'all',
          'trigger': _enabled ? 'schedule' : 'disabled',
          'date': DateTime.now().toIso8601String(),
          'channel': _telegram ? 'telegram' : (_message ? 'message' : 'none'),
          'interval': _schedule,
          'enabled': _enabled,
        }),
      );
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _showMessage('Jadwal berhasil dikirim ke server');
      } else {
        _showMessage('Gagal menyimpan jadwal (${response.statusCode})');
      }
    } catch (_) {
      if (mounted) _showMessage('Server tidak dapat dihubungi');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.surface, elevation: 0, title: Text('Jadwal Pengiriman', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)), actions: [IconButton(icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode), onPressed: AppTheme.toggle)]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF3B82F6).withValues(alpha: .1), shape: BoxShape.circle), child: const Icon(Icons.send_time_extension, color: Color(0xFF3B82F6))), const SizedBox(width: 12), const Expanded(child: Text('Kirim data sensor otomatis', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))), Switch(value: _enabled, onChanged: (value) => setState(() => _enabled = value))]),
            const SizedBox(height: 8),
            Text(_enabled ? 'Aktif dan akan berjalan sesuai interval.' : 'Jadwal sedang dinonaktifkan.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            const Text('Interval pengiriman', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _schedule,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 15),
              icon: Icon(Icons.keyboard_arrow_down, color: theme.colorScheme.onSurfaceVariant),
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.brightness == Brightness.dark ? const Color(0xFF24314A) : const Color(0xFFF5F7FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: const ['Setiap 1 menit', 'Setiap 5 menit', 'Setiap 15 menit', 'Setiap 1 jam'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
              onChanged: (value) => setState(() => _schedule = value ?? _schedule),
            ),
            const SizedBox(height: 20),
            const Text('Kirim melalui', style: TextStyle(fontWeight: FontWeight.w600)),
            _channelTile(Icons.telegram, 'Telegram', 'Bot Telegram', _telegram, (value) => setState(() => _telegram = value)),
            _channelTile(Icons.sms_outlined, 'Pesan', 'SMS / pesan teks', _message, (value) => setState(() => _message = value)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'Mengirim...' : 'Simpan Jadwal'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
          ]),
        ),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(16)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: Color(0xFF2563EB)), SizedBox(width: 10), Expanded(child: Text('Setiap pengiriman berisi nilai terbaru suhu, kelembapan, gas, dan status api. Hubungkan bot atau nomor penerima di Profil.', style: TextStyle(color: Color(0xFF1E40AF), height: 1.4)))])),
      ]),
    );
  }

  Widget _channelTile(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon, color: const Color(0xFF3B82F6), size: 28), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(subtitle), trailing: Switch(value: value, onChanged: onChanged));
}
