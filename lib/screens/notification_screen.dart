import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/notification_store.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text('Notifikasi', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: NotificationStore.clear),
          IconButton(icon: Icon(theme.brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode), onPressed: AppTheme.toggle),
        ],
      ),
      body: ValueListenableBuilder<List<MonitoringNotification>>(
        valueListenable: NotificationStore.items,
        builder: (context, notifications, _) {
          if (notifications.isEmpty) return const Center(child: Text('Belum ada notifikasi sensor'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) => _item(context, notifications[index]),
          );
        },
      ),
    );
  }

  Widget _item(BuildContext context, MonitoringNotification notification) {
    final isDanger = notification.level == 'Bahaya';
    final color = isDanger ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final title = notification.sensor == 'api'
        ? 'Deteksi Api'
        : notification.sensor == 'gas'
        ? 'Sensor Gas'
        : 'Level Air';
    final time = notification.createdAt.toLocal().toString().substring(11, 16);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      child: Row(
        children: [
          Icon(isDanger ? Icons.warning_rounded : Icons.info_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$title - ${notification.level}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${notification.message} (${notification.value})', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Text(time, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
