import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createMqttClient({
  required String host,
  required String clientId,
  required int tcpPort,
  required int webSocketPort,
}) =>
    MqttServerClient.withPort(host, clientId, tcpPort);
