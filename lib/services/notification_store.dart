import 'package:flutter/foundation.dart';

class MonitoringNotification {
  final String sensor;
  final String level;
  final String message;
  final num value;
  final DateTime createdAt;

  const MonitoringNotification({
    required this.sensor,
    required this.level,
    required this.message,
    required this.value,
    required this.createdAt,
  });
}

class NotificationStore {
  static final ValueNotifier<List<MonitoringNotification>> items =
      ValueNotifier<List<MonitoringNotification>>(<MonitoringNotification>[]);

  static void add({
    required String sensor,
    required String level,
    required String message,
    required num value,
  }) {
    final next = [
      MonitoringNotification(
        sensor: sensor,
        level: level,
        message: message,
        value: value,
        createdAt: DateTime.now(),
      ),
      ...items.value,
    ];
    items.value = next.take(50).toList(growable: false);
  }

  static void clear() => items.value = const [];
}
