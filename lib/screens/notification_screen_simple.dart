import 'package:flutter/material.dart';
class NotificationScreenSimple extends StatelessWidget {
  const NotificationScreenSimple({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, title: const Text('Notifikasi', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _buildNotif('Suhu Normal', 'Suhu kembali normal 26°C', Icons.check_circle, Colors.green),
        _buildNotif('Gas Terdeteksi', 'Sensor gas: 180 PPM', Icons.warning, Colors.orange),
        _buildNotif('Sistem Online', 'Monitoring aktif kembali', Icons.info, Colors.blue),
      ]),
    );
  }
  Widget _buildNotif(String title, String sub, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [Icon(icon, color: color, size: 24), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), Text(sub, style: const TextStyle(fontSize: 12, color: Colors.black54))]))]),
    );
  }
}