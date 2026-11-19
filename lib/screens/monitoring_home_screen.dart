import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/sensor_data.dart';
import 'sensor_detail_screen.dart';
import '../app_theme.dart';
import 'bluetooth_connection_sheet.dart';
import '../services/mqtt_service.dart';
import '../services/notification_store.dart';

class MonitoringHomeScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;
  const MonitoringHomeScreen({Key? key, this.onNavigate}) : super(key: key);
  @override
  State<MonitoringHomeScreen> createState() => _MonitoringHomeScreenState();
}

class _MonitoringHomeScreenState extends State<MonitoringHomeScreen> {
  // Harus selaras dengan FLAME_THRESHOLD dan WATER_THRESHOLD pada firmware
  // ESP32 agar warna kartu menunjukkan kondisi yang sama dengan perangkat.
  static const int _flameDangerThreshold = 2500;
  static const int _flameWarningThreshold = 3500;
  static const int _waterDangerThreshold = 20;
  static const int _waterWarningThreshold = 10;
  static const int _gasDangerThreshold = 1200;
  static const int _gasWarningThreshold = 600;

  double _temp = 26.5;
  int _gas = 145;
  int _water = 0;
  int _flameValue = 4095;
  bool _flame = false;
  String _esp32Status = '';
  bool _alarmOn = true;
  bool _fanOn = false;
  bool _bluetoothConnected = false;
  bool _apiConnected = false;
  bool _mqttConnected = false;
  final FlutterTts _tts = FlutterTts();
  bool _soundEnabled = false;
  bool _speakingWarning = false;
  String _lastAlarmState = 'Aman';
  String? _apiError;
  final MqttService _mqtt = MqttService();
  StreamSubscription<MqttIncomingMessage>? _mqttSubscription;
  late final VoidCallback _mqttStateListener;
  late final VoidCallback _mqttErrorListener;
  final List<double> _temperatureHistory = [
    26.2,
    26.4,
    26.1,
    26.7,
    26.5,
    26.8,
    26.6,
    26.9,
    26.5,
    26.7,
    26.4,
    26.5,
  ];
  final List<double> _waterHistory = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  final List<double> _gasHistory = [145, 145, 145, 145, 145, 145, 145, 145, 145, 145, 145, 145];
  final List<double> _flameHistory = [4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095];
  ValueNotifier<SensorData>? _detailSensorNotifier;

  @override
  void initState() {
    super.initState();
    _connectMqtt();
  }

  void _connectMqtt() {
    _mqttStateListener = () {
      if (!mounted) return;
      setState(() {
        _mqttConnected = _mqtt.isConnected;
        _apiConnected = _mqttConnected;
      });
    };
    _mqttErrorListener = () {
      if (!mounted) return;
      setState(() => _apiError = _mqtt.error.value);
    };
    _mqtt.connectionState.addListener(_mqttStateListener);
    _mqtt.error.addListener(_mqttErrorListener);
    _mqttSubscription = _mqtt.messages.listen(_onMqttMessage);
    unawaited(_mqtt.connect());
  }

  void _onMqttMessage(MqttIncomingMessage message) {
    try {
      final decoded = jsonDecode(message.payload);
      if (decoded is! Map) {
        throw const FormatException('Payload MQTT harus berbentuk JSON object');
      }
      final data = Map<String, dynamic>.from(decoded);
      if (message.topic == MqttService.sensorTopic) {
        final nestedData = data['data'] ?? data['payload'];
        _applySensorData(
          nestedData is Map
              ? Map<String, dynamic>.from(nestedData)
              : data,
        );
      } else if (message.topic == MqttService.alertTopic) {
        _applyMqttAlert(data);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _apiError = 'Payload MQTT tidak valid: $error');
    }
  }

  void _applyMqttAlert(Map<String, dynamic> data) {
    final nestedData = data['data'] ?? data['payload'];
    _applySensorData(
      nestedData is Map ? Map<String, dynamic>.from(nestedData) : data,
    );

    final status = (data['status'] ?? data['level'] ?? data['severity'] ?? '')
        .toString()
        .toUpperCase();
    final message = (data['message'] ?? data['alert'] ?? '').toString();
    if (!mounted) return;
    setState(() {
      if (status.isNotEmpty) _esp32Status = status;
    });
    if (message.isNotEmpty && (status.contains('BAHAYA') || status.contains('WASPADA'))) {
      _showAlertBanner(message, status.contains('BAHAYA') ? 'Bahaya' : 'Waspada');
    }
  }

  String _temperatureStatus() => _temp >= 32
      ? 'Bahaya'
      : (_temp >= 27 || _temp < 18 ? 'Waspada' : 'Normal');
  String _gasStatus() {
    if (_gas >= _gasDangerThreshold) {
      return 'Bahaya';
    }
    if (_gas >= _gasWarningThreshold) {
      return 'Waspada';
    }
    return 'Aman';
  }

  String _flameStatus() {
    if (_flameValue < _flameDangerThreshold || _flame) {
      return 'Bahaya';
    }
    if (_flameValue < _flameWarningThreshold) {
      return 'Waspada';
    }
    return 'Aman';
  }

  String _waterStatus() {
    if (_water >= _waterDangerThreshold) {
      return 'Bahaya';
    }
    if (_water >= _waterWarningThreshold) {
      return 'Waspada';
    }
    return 'Aman';
  }

  void _playAlarmIfNeeded() {
    String currentState = 'Aman';
    String message = '';
    if (_flameStatus() == 'Bahaya') {
      currentState = 'api:Bahaya';
      message = 'Bahaya, api terdeteksi';
    } else if (_flameStatus() == 'Waspada') {
      currentState = 'api:Waspada';
      message = 'Waspada, sensor api';
    } else if (_gasStatus() == 'Bahaya') {
      currentState = 'gas:Bahaya';
      message = 'Bahaya, sensor gas';
    } else if (_waterStatus() == 'Bahaya') {
      currentState = 'air:Bahaya';
      message = 'Bahaya, level air tinggi';
    } else if (_gasStatus() == 'Waspada') {
      currentState = 'gas:Waspada';
      message = 'Waspada, sensor gas';
    } else if (_waterStatus() == 'Waspada') {
      currentState = 'air:Waspada';
      message = 'Waspada, level air';
    }

    // Bunyi hanya ketika status berubah, supaya tidak berbunyi tiap 500 ms.
    if (currentState == _lastAlarmState || currentState == 'Aman') {
      _lastAlarmState = currentState;
      return;
    }

    _lastAlarmState = currentState;
    final separator = currentState.indexOf(':');
    final sensor = currentState.substring(0, separator);
    final level = currentState.substring(separator + 1);
    final value = sensor == 'gas'
        ? _gas
        : sensor == 'api'
        ? _flameValue
        : _water;
    _showAlertBanner(message, level);
    NotificationStore.add(
      sensor: sensor,
      level: level,
      message: message,
      value: value,
    );
    // Notifikasi tetap dicatat dan dikirim walaupun suara/buzzer OFF.
    if (!_soundEnabled || !_alarmOn) return;
    unawaited(_speakWarning(message));
  }

  void _showAlertBanner(String message, String level) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: level == 'Bahaya'
              ? const Color(0xFFFEE2E2)
              : const Color(0xFFFEF3C7),
          leadingPadding: const EdgeInsets.only(right: 14),
          leading: Icon(
            level == 'Bahaya' ? Icons.warning_rounded : Icons.info_rounded,
            color: level == 'Bahaya'
                ? const Color(0xFFDC2626)
                : const Color(0xFFD97706),
            size: 32,
          ),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: const Text(
                'Tutup',
                style: TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      );
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) messenger.hideCurrentMaterialBanner();
    });
  }

  Future<void> _speakWarning(String message) async {
    if (_speakingWarning) return;
    _speakingWarning = true;
    try {
      for (var i = 0; i < 2; i++) {
        await _tts.speak(message);
        // Beri jeda agar Chrome tidak memotong ucapan berikutnya.
        if (i < 1) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }
    } finally {
      _speakingWarning = false;
    }
  }

  @override
  void dispose() {
    _mqtt.connectionState.removeListener(_mqttStateListener);
    _mqtt.error.removeListener(_mqttErrorListener);
    unawaited(_mqttSubscription?.cancel());
    unawaited(_mqtt.dispose());
    unawaited(_tts.stop());
    _detailSensorNotifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Monitoring R Server',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sambungkan ESP32 Bluetooth',
            icon: Icon(
              _bluetoothConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            ),
            color: _bluetoothConnected ? const Color(0xFF10B981) : null,
            onPressed: _openBluetooth,
          ),
          IconButton(
            tooltip: 'Ganti tema',
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: AppTheme.toggle,
          ),
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (!_apiConnected && !_bluetoothConnected)
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                  : (_esp32Status.contains('BAHAYA')
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : (_esp32Status.contains('WASPADA')
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                          : const Color(0xFF10B981).withValues(alpha: 0.15))),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  color: (!_apiConnected && !_bluetoothConnected)
                      ? const Color(0xFFF59E0B)
                      : (_esp32Status.contains('BAHAYA')
                          ? const Color(0xFFEF4444)
                          : (_esp32Status.contains('WASPADA')
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF10B981))),
                  size: 8,
                ),
                const SizedBox(width: 6),
                Text(
                  _bluetoothConnected
                      ? 'BLE Online'
                      : (!_apiConnected
                          ? 'MQTT Offline'
                          : (_esp32Status.contains('BAHAYA')
                              ? 'Status: BAHAYA'
                              : (_esp32Status.contains('WASPADA')
                                  ? 'Status: WASPADA'
                                  : 'MQTT Online'))),
                  style: TextStyle(
                    color: (!_apiConnected && !_bluetoothConnected)
                        ? const Color(0xFFD97706)
                        : (_esp32Status.contains('BAHAYA')
                            ? const Color(0xFFDC2626)
                            : (_esp32Status.contains('WASPADA')
                                ? const Color(0xFFD97706)
                                : const Color(0xFF059669))),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_apiError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Koneksi API: $_apiError',
                  style: const TextStyle(
                    color: Color(0xFF9A3412),
                    fontSize: 12,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _buildSensorCard(
                    'Suhu Ruangan',
                    '${_temp.toStringAsFixed(1)} °C',
                    'Normal: 18-27°C',
                    _temperatureStatus(),
                    const Color(0xFF3B82F6),
                    Icons.thermostat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSensorCard(
                    'Level Air',
                    '$_water ADC',
                    _waterStatus() == 'Bahaya'
                        ? 'Bahaya Air Tinggi!'
                        : (_waterStatus() == 'Waspada'
                            ? 'Waspada Ada Air'
                            : 'Normal Kering (<10)'),
                    _waterStatus(),
                    const Color(0xFF0EA5E9),
                    Icons.water,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSensorCard(
                    'Sensor Gas',
                    '$_gas PPM',
                    _gasStatus() == 'Bahaya'
                        ? 'Bahaya Gas Pekat!'
                        : (_gasStatus() == 'Waspada'
                            ? 'Waspada Gas Naik'
                            : 'Maks Aman: 600 PPM'),
                    _gasStatus(),
                    const Color(0xFF10B981),
                    Icons.air,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSensorCard(
                    'Deteksi Api',
                    _flameStatus() == 'Bahaya'
                        ? 'API ADA'
                        : (_flameStatus() == 'Waspada' ? 'WASPADA API' : 'TIDAK ADA API'),
                    'Nilai: $_flameValue ADC',
                    _flameStatus(),
                    const Color(0xFFEF4444),
                    Icons.local_fire_department,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Grafik Suhu & Level Air',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 150,
                    child: CustomPaint(
                      painter: _ChartPainter(
                        temperature: _temperatureHistory,
                        water: _waterHistory,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children:
                        [
                              '12h',
                              '2h',
                              '3h',
                              '4h',
                              '7h',
                              '8h',
                              '9h',
                              '12h',
                              '12h',
                            ]
                            .map(
                              (t) => Text(
                                t,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kontrol Cepat',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildToggle(
                          'Alarm / Buzzer',
                          _alarmOn,
                          _setAlarmEnabled,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildToggle(
                          'Exhaust Fan',
                          _fanOn,
                          (v) => setState(() => _fanOn = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openBluetooth() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BluetoothConnectionSheet(
        onConnectionChanged: (connected) =>
            setState(() => _bluetoothConnected = connected),
        onSensorData: _applySensorData,
      ),
    );
  }

  Future<void> _enableSound() async {
    // Tap pengguna diperlukan browser sebelum audio otomatis diizinkan.
    setState(() => _soundEnabled = true);
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak('Suara alarm aktif');
  }

  void _setAlarmEnabled(bool enabled) {
    setState(() {
      _alarmOn = enabled;
      if (!enabled) {
        _tts.stop();
        _lastAlarmState = 'Aman';
      } else {
        // Jika sensor sudah kuning/merah sebelum alarm diaktifkan,
        // izinkan suara diputar pada pembacaan berikutnya.
        _lastAlarmState = 'Aman';
      }
    });
    if (enabled) unawaited(_enableSound());
  }

  void _applySensorData(Map<String, dynamic> data) {
    final temperature = _asNum(
      data['temperature_c'] ?? data['temperature'] ?? data['temp'],
    )?.toDouble();
    final gas = _asNum(data['gas_raw'] ?? data['mq2_value'] ?? data['gas'])
        ?.toInt();
    final rawFlame =
        data['flame_detected'] ?? data['flame'] ?? data['fire'] ?? data['api'];
    final flame = _asBool(rawFlame);
    final flameValue = _asNum(data['flame_value'] ??
            data['flame_raw'] ??
            data['flame_adc'])
        ?.toInt();
    final water = _asNum(data['water_value'] ??
            data['water_raw'] ??
            data['water'] ??
            data['level_air'] ??
            data['water_level'])
        ?.toInt();
    final esp32Status = (data['status'] ?? '').toString().toUpperCase();
    if (!mounted) return;
    setState(() {
      if (esp32Status.isNotEmpty) _esp32Status = esp32Status;
      if (temperature != null) {
        _temp = temperature;
        _temperatureHistory.add(temperature);
        if (_temperatureHistory.length > 12) _temperatureHistory.removeAt(0);
      }
      if (gas != null) {
        _gas = gas;
        _gasHistory.add(gas.toDouble());
        if (_gasHistory.length > 12) _gasHistory.removeAt(0);
      }
      if (flameValue != null) {
        _flameValue = flameValue;
        _flame = flameValue < _flameDangerThreshold;
        _flameHistory.add(flameValue.toDouble());
        if (_flameHistory.length > 12) _flameHistory.removeAt(0);
      }
      if (water != null) {
        _water = water;
        _waterHistory.add(_water.toDouble());
        if (_waterHistory.length > 12) _waterHistory.removeAt(0);
      }
      if (rawFlame != null) _flame = flame;
    });
    _publishDetailUpdate();
    // BLE notification langsung memicu perubahan warna, popup, notifikasi,
    // dan suara tanpa menunggu request HTTP berikutnya.
    _playAlarmIfNeeded();
  }

  num? _asNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString().trim() ?? '');
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return switch (value?.toString().trim().toLowerCase()) {
      'true' || '1' || 'on' || 'detected' || 'ada' => true,
      _ => false,
    };
  }

  Widget _buildSensorCard(
    String title,
    String value,
    String time,
    String status,
    Color color,
    IconData icon,
  ) {
    final currentValue = title == 'Suhu Ruangan'
        ? '${_temp.toStringAsFixed(1)} °C'
        : title == 'Sensor Gas'
        ? '$_gas PPM'
        : title == 'Deteksi Api'
        ? _flameStatus() == 'Bahaya'
              ? 'API ADA'
              : _flameStatus() == 'Waspada'
              ? 'WASPADA API'
              : 'TIDAK ADA API'
        : '$_water ADC';
    final currentStatus = title == 'Suhu Ruangan'
        ? _temperatureStatus()
        : title == 'Sensor Gas'
        ? _gasStatus()
        : title == 'Deteksi Api'
        ? _flameStatus()
        : _waterStatus();
    final statusColor = currentStatus == 'Bahaya'
        ? const Color(0xFFEF4444)
        : currentStatus == 'Waspada'
        ? const Color(0xFFF59E0B)
        : const Color(0xFF10B981);

    final isBahaya = currentStatus == 'Bahaya';
    final isWaspada = currentStatus == 'Waspada';
    final isAlert = isBahaya || isWaspada;

    final cardBgColor = isBahaya
        ? const Color(0xFFEF4444)
        : (isWaspada ? const Color(0xFFF59E0B) : Colors.white);
    final cardBorderColor = isBahaya
        ? const Color(0xFFDC2626)
        : (isWaspada ? const Color(0xFFD97706) : Colors.black.withValues(alpha: 0.04));
    final primaryTextColor = isAlert ? Colors.white : Colors.black87;
    final secondaryTextColor = isAlert ? Colors.white.withValues(alpha: 0.9) : Colors.black54;
    final activeIconColor = isAlert ? Colors.white : color;
    final iconBgColor = isAlert ? Colors.white.withValues(alpha: 0.22) : color.withValues(alpha: 0.1);
    final badgeBgColor = isAlert ? Colors.white.withValues(alpha: 0.25) : statusColor.withValues(alpha: 0.12);
    final badgeTextColor = isAlert ? Colors.white : statusColor;

    return SizedBox(
      height: 175,
      child: InkWell(
        onTap: () => _openSensorDetail(title),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cardBorderColor, width: isAlert ? 1.5 : 1),
            boxShadow: [
              BoxShadow(
                color: isAlert
                    ? statusColor.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: isAlert ? 16 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: secondaryTextColor.withValues(alpha: 0.6),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: activeIconColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            currentValue,
                            key: ValueKey(currentValue),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  currentStatus,
                  style: TextStyle(
                    fontSize: 11,
                    color: badgeTextColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSensorDetail(String title) {
    final sensor = _createDetailSensor(title);
    _detailSensorNotifier?.dispose();
    _detailSensorNotifier = ValueNotifier<SensorData>(sensor);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SensorDetailScreen(
          sensorData: sensor,
          liveSensorData: _detailSensorNotifier,
          onNavigate: widget.onNavigate,
        ),
      ),
    );
    return;
    /*
    final isTemperature = title == 'Suhu Ruangan';
    final isFlame = title == 'Deteksi Api';
    final isWater = title == 'Level Air';
    final type = isTemperature
        ? SensorType.temperature
        : isFlame
        ? SensorType.flame
        : SensorType.gas;
    final value = isTemperature
        ? _temp
        : isFlame
        ? (_flame ? 1.0 : 0.0)
        : isWater
        ? _water.toDouble()
        : _gas.toDouble();
    final sensor = SensorData(
      id: title,
      name: title,
      currentValue: value,
      unit: isTemperature
          ? '°C'
          : isFlame
          ? ''
          : isWater
          ? 'ADC'
          : 'PPM',
      status: isFlame && _flame ? SensorStatus.danger : SensorStatus.normal,
      type: type,
      lastUpdate: DateTime.now(),
      location: 'Ruang Server',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SensorDetailScreen(
          sensorData: sensor,
          onNavigate: widget.onNavigate,
        ),
      ),
    );
    */
  }

  SensorData _createDetailSensor(String title) {
    final isTemperature = title == 'Suhu Ruangan';
    final isFlame = title == 'Deteksi Api';
    final isWater = title == 'Level Air';

    final SensorType type = isTemperature
        ? SensorType.temperature
        : isFlame
            ? SensorType.flame
            : isWater
                ? SensorType.humidity
                : SensorType.gas;

    final double value = isTemperature
        ? _temp
        : isFlame
            ? _flameValue.toDouble()
            : isWater
                ? _water.toDouble()
                : _gas.toDouble();

    final String unit = isTemperature
        ? '°C'
        : isFlame
            ? 'ADC'
            : isWater
                ? 'ADC'
                : 'PPM';

    final statusText = isTemperature
        ? _temperatureStatus()
        : isFlame
            ? _flameStatus()
            : isWater
                ? _waterStatus()
                : _gasStatus();

    final history = isTemperature
        ? _temperatureHistory
        : isWater
            ? _waterHistory
            : isFlame
                ? _flameHistory
                : _gasHistory;

    final dangerThreshold = isTemperature
        ? 32.0
        : isFlame
            ? _flameDangerThreshold.toDouble()
            : isWater
                ? _waterDangerThreshold.toDouble()
                : _gasDangerThreshold.toDouble();

    final warningThreshold = isTemperature
        ? 27.0
        : isFlame
            ? _flameWarningThreshold.toDouble()
            : isWater
                ? _waterWarningThreshold.toDouble()
                : _gasWarningThreshold.toDouble();

    return SensorData(
      id: title,
      name: title,
      currentValue: value,
      unit: unit,
      status: statusText == 'Bahaya'
          ? SensorStatus.danger
          : statusText == 'Waspada'
              ? SensorStatus.warning
              : SensorStatus.normal,
      type: type,
      lastUpdate: DateTime.now(),
      location: 'Ruang Server',
      thresholds: SensorThresholds(
        warningThreshold: warningThreshold,
        dangerThreshold: dangerThreshold,
      ),
      historicalData: history
          .asMap()
          .entries
          .map(
            (entry) => SensorDataPoint(
              timestamp: DateTime.now().subtract(
                Duration(minutes: history.length - entry.key),
              ),
              value: entry.value,
            ),
          )
          .toList(),
    );
  }

  void _publishDetailUpdate() {
    final notifier = _detailSensorNotifier;
    if (notifier == null || !mounted) return;
    notifier.value = _createDetailSensor(notifier.value.name);
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF24314A)
            : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: theme.colorScheme.primary,
            activeTrackColor: theme.colorScheme.primary.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> temperature;
  final List<double> water;

  const _ChartPainter({required this.temperature, required this.water});

  @override
  void paint(Canvas canvas, Size size) {
    final values = [...temperature, ...water];
    final minValue = values.reduce(min) - 2;
    final maxValue = values.reduce(max) + 2;
    final drawLine = (List<double> data, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final x = size.width * i / (data.length - 1);
        final y =
            size.height -
            ((data[i] - minValue) / (maxValue - minValue) * size.height);
        if (i == 0)
          path.moveTo(x, y);
        else
          path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    };
    drawLine(temperature, const Color(0xFF3B82F6));
    drawLine(water, const Color(0xFF06B6D4));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) => true;
}
