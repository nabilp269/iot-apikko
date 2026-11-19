import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'mqtt_client_factory.dart';

enum MqttConnectionState { disconnected, connecting, connected }

class MqttIncomingMessage {
  final String topic;
  final String payload;
  final DateTime receivedAt;

  const MqttIncomingMessage({
    required this.topic,
    required this.payload,
    required this.receivedAt,
  });
}

/// Koneksi MQTT untuk data smart motor.
///
/// Topik yang dipantau:
/// - smart_motor/sensor: JSON nilai sensor, misalnya
///   {"temperature_c":26.4,"gas_raw":120,"flame_value":4095,
///    "flame_detected":false,"water_value":0}
/// - smart_motor/alert: JSON status/peringatan, misalnya
///   {"status":"BAHAYA","sensor":"flame","message":"Api terdeteksi"}
///
/// Nilai broker dapat diatur saat menjalankan aplikasi:
/// --dart-define=MQTT_HOST=192.168.137.1 --dart-define=MQTT_PORT=1883
/// Untuk Flutter Web, aktifkan listener WebSocket Mosquitto dan gunakan:
/// --dart-define=MQTT_WS_PORT=9001
/// --dart-define=MQTT_USERNAME=... --dart-define=MQTT_PASSWORD=...
class MqttService {
  static const sensorTopic = 'smart_motor/sensor';
  static const alertTopic = 'smart_motor/alert';

  static const _host = String.fromEnvironment(
    'MQTT_HOST',
    defaultValue: '192.168.137.1',
  );
  static const _port = int.fromEnvironment('MQTT_PORT', defaultValue: 1883);
  static const _webSocketPort =
      int.fromEnvironment('MQTT_WS_PORT', defaultValue: 9001);
  static const _username = String.fromEnvironment('MQTT_USERNAME');
  static const _password = String.fromEnvironment('MQTT_PASSWORD');

  final ValueNotifier<MqttConnectionState> connectionState =
      ValueNotifier(MqttConnectionState.disconnected);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final StreamController<MqttIncomingMessage> _messages =
      StreamController<MqttIncomingMessage>.broadcast();

  mqtt.MqttClient? _client;
  StreamSubscription<List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>>>?
      _updatesSubscription;

  Stream<MqttIncomingMessage> get messages => _messages.stream;
  bool get isConnected =>
      connectionState.value == MqttConnectionState.connected;
  String get _endpoint => kIsWeb
      ? 'ws://$_host:$_webSocketPort'
      : '$_host:$_port';

  Future<void> connect() async {
    if (isConnected || connectionState.value == MqttConnectionState.connecting) {
      return;
    }

    connectionState.value = MqttConnectionState.connecting;
    error.value = null;
    final clientId = 'flutter_smart_motor_${DateTime.now().millisecondsSinceEpoch}';
    final client = createMqttClient(
      host: _host,
      clientId: clientId,
      tcpPort: _port,
      webSocketPort: _webSocketPort,
    )
      ..logging(on: false)
      ..setProtocolV311()
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..onAutoReconnect = _onAutoReconnect
      ..onAutoReconnected = _onAutoReconnected
      ..connectionMessage = mqtt.MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(mqtt.MqttQos.atLeastOnce);
    _client = client;

    try {
      await client.connect(
        _username.isEmpty ? null : _username,
        _password.isEmpty ? null : _password,
      );
      if (client.connectionStatus?.state != mqtt.MqttConnectionState.connected) {
        throw StateError(
          'Broker menolak koneksi: ${client.connectionStatus?.returnCode}',
        );
      }
      _subscribe();
    } catch (exception) {
      error.value = 'MQTT $_endpoint gagal: $exception';
      connectionState.value = MqttConnectionState.disconnected;
      client.disconnect();
    }
  }

  void _onConnected() {
    connectionState.value = MqttConnectionState.connected;
    error.value = null;
  }

  void _onDisconnected() {
    if (connectionState.value != MqttConnectionState.connecting) {
      connectionState.value = MqttConnectionState.disconnected;
    }
  }

  void _onAutoReconnect() {
    connectionState.value = MqttConnectionState.connecting;
  }

  void _onAutoReconnected() {
    connectionState.value = MqttConnectionState.connected;
    error.value = null;
  }

  void _subscribe() {
    final client = _client;
    if (client == null) return;
    client.subscribe(sensorTopic, mqtt.MqttQos.atLeastOnce);
    client.subscribe(alertTopic, mqtt.MqttQos.atLeastOnce);
    _updatesSubscription ??= client.updates?.listen(
      _onMessages,
      onError: (Object exception) {
        error.value = 'Pesan MQTT gagal dibaca: $exception';
      },
    );
  }

  void _onMessages(
    List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> events,
  ) {
    for (final event in events) {
      final publish = event.payload as mqtt.MqttPublishMessage;
      final payload = mqtt.MqttPublishPayload.bytesToStringAsString(
        publish.payload.message,
      );
      _messages.add(
        MqttIncomingMessage(
          topic: event.topic,
          payload: payload,
          receivedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> disconnect() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    _client?.disconnect();
    _client = null;
    connectionState.value = MqttConnectionState.disconnected;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    connectionState.dispose();
    error.dispose();
  }
}
