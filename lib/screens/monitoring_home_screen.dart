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

class _MonitoringHomeScreenState extends State<MonitoringHomeScreen>
    with SingleTickerProviderStateMixin {
  static const int _flameDangerThreshold = 2000;
  static const int _flameWarningThreshold = 2700;
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
  DateTime _lastPacketTime = DateTime.now();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<double> _temperatureHistory = [
    26.2, 26.4, 26.1, 26.7, 26.5, 26.8, 26.6, 26.9, 26.5, 26.7, 26.4, 26.5,
  ];
  final List<double> _waterHistory = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  final List<double> _gasHistory = [
    145, 145, 145, 145, 145, 145, 145, 145, 145, 145, 145, 145,
  ];
  final List<double> _flameHistory = [
    4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095, 4095,
  ];
  ValueNotifier<SensorData>? _detailSensorNotifier;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
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
    if (_gas >= _gasDangerThreshold) return 'Bahaya';
    if (_gas >= _gasWarningThreshold) return 'Waspada';
    return 'Aman';
  }

  String _flameStatus() {
    if (_flameValue < _flameDangerThreshold || _flame) return 'Bahaya';
    if (_flameValue < _flameWarningThreshold) return 'Waspada';
    return 'Aman';
  }

  String _waterStatus() {
    if (_water >= _waterDangerThreshold) return 'Bahaya';
    if (_water >= _waterWarningThreshold) return 'Waspada';
    return 'Aman';
  }

  String _getOverallSystemStatus() {
    if (_flameStatus() == 'Bahaya' || _gasStatus() == 'Bahaya' || _waterStatus() == 'Bahaya' || _temperatureStatus() == 'Bahaya') {
      return 'Bahaya';
    }
    if (_flameStatus() == 'Waspada' || _gasStatus() == 'Waspada' || _waterStatus() == 'Waspada' || _temperatureStatus() == 'Waspada') {
      return 'Waspada';
    }
    return 'Optimal';
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
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: const Text('Tutup', style: TextStyle(color: Colors.black87)),
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
    _pulseController.dispose();
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildModernAppBar(context, isDark),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_apiError != null && !_mqttConnected) _buildErrorCard(isDark),
                  _buildHeroOverview(context, isDark),
                  const SizedBox(height: 24),
                  _buildSectionHeader('STATUS SENSOR LIVE', Icons.sensors),
                  const SizedBox(height: 14),
                  _buildSensorGrid(context, isDark),
                  const SizedBox(height: 28),
                  _buildSectionHeader('TREN TELEMETRI REAL-TIME', Icons.show_chart),
                  const SizedBox(height: 14),
                  _buildChartCard(context, isDark),
                  const SizedBox(height: 28),
                  _buildSectionHeader('PANEL KONTROL SISTEM', Icons.tune),
                  const SizedBox(height: 14),
                  _buildControlPanel(context, isDark),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar(BuildContext context, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.memory,
                  color: Color(0xFF3B82F6),
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Smart IoT Server',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Row(
                children: [
                  FadeTransition(
                    opacity: _pulseAnimation,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _mqttConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _mqttConnected ? 'MQTT Live Stream' : 'Broker Offline',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black45,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Koneksi Bluetooth ESP32',
          icon: Icon(
            _bluetoothConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: _bluetoothConnected ? const Color(0xFF10B981) : (isDark ? Colors.white70 : Colors.black54),
          ),
          onPressed: _openBluetooth,
        ),
        IconButton(
          tooltip: isDark ? 'Mode Terang' : 'Mode Gelap',
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: isDark ? const Color(0xFFFBBF24) : Colors.black87,
          ),
          onPressed: AppTheme.toggle,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF3B82F6)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFEF4444).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Color(0xFFEF4444), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Koneksi MQTT Terputus',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFFDC2626),
                  ),
                ),
                Text(
                  _apiError ?? 'Pastikan Mosquitto dan skrip bridge aktif.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : const Color(0xFF7F1D1D),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => unawaited(_mqtt.connect()),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Konek Ulang', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroOverview(BuildContext context, bool isDark) {
    final overall = _getOverallSystemStatus();
    final isDanger = overall == 'Bahaya';
    final isWarning = overall == 'Waspada';

    final Color statusColor = isDanger
        ? const Color(0xFFEF4444)
        : (isWarning ? const Color(0xFFF59E0B) : const Color(0xFF10B981));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFF1E3A8A), const Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(isDark ? 0.2 : 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _mqttConnected ? Icons.wifi : Icons.wifi_off,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _mqttConnected ? 'MQTT AKTIF' : 'OFFLINE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.25),
                      border: Border.all(color: statusColor.withOpacity(0.6), width: 1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'STATUS: $overall'.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'ESP32 Server Node',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Monitoring Ruang Server',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Telemetri terpusat untuk mendeteksi bahaya kebakaran, kebocoran gas, suhu ekstrem, dan genangan air secara instan.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickMetric('Suhu', '${_temp.toStringAsFixed(1)}°C', Icons.thermostat),
                _buildDivider(),
                _buildQuickMetric('Gas MQ-2', '$_gas PPM', Icons.air),
                _buildDivider(),
                _buildQuickMetric('Level Air', '$_water ADC', Icons.water_drop),
                _buildDivider(),
                _buildQuickMetric('Api', _flame ? 'ADA' : 'AMAN', Icons.local_fire_department),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMetric(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 24,
      width: 1,
      color: Colors.white.withOpacity(0.15),
    );
  }

  Widget _buildSensorGrid(BuildContext context, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final cards = [
          _buildModernSensorCard(
            title: 'Suhu Ruangan',
            value: '${_temp.toStringAsFixed(1)} °C',
            subtitle: 'Target: 18 - 27°C',
            status: _temperatureStatus(),
            accentColor: const Color(0xFF3B82F6),
            icon: Icons.thermostat_rounded,
            progress: (_temp / 50.0).clamp(0.0, 1.0),
            isDark: isDark,
          ),
          _buildModernSensorCard(
            title: 'Level Air',
            value: '$_water ADC',
            subtitle: _waterStatus() == 'Bahaya'
                ? 'Air Terdeteksi Tinggi!'
                : (_waterStatus() == 'Waspada' ? 'Waspada Ada Air' : 'Kering Normal (<10)'),
            status: _waterStatus(),
            accentColor: const Color(0xFF06B6D4),
            icon: Icons.water_drop_rounded,
            progress: (_water / 100.0).clamp(0.0, 1.0),
            isDark: isDark,
          ),
          _buildModernSensorCard(
            title: 'Sensor Gas MQ-2',
            value: '$_gas PPM',
            subtitle: _gasStatus() == 'Bahaya'
                ? 'Gas Sangat Pekat!'
                : (_gasStatus() == 'Waspada' ? 'Gas Meningkat' : 'Batas Aman: 600 PPM'),
            status: _gasStatus(),
            accentColor: const Color(0xFF10B981),
            icon: Icons.air_rounded,
            progress: (_gas / 1200.0).clamp(0.0, 1.0),
            isDark: isDark,
          ),
          _buildModernSensorCard(
            title: 'Deteksi Api',
            value: _flameStatus() == 'Bahaya'
                ? 'API TERDETEKSI'
                : (_flameStatus() == 'Waspada' ? 'WASPADA API' : 'TIDAK ADA API'),
            subtitle: 'Nilai ADC: $_flameValue',
            status: _flameStatus(),
            accentColor: const Color(0xFFEF4444),
            icon: Icons.local_fire_department_rounded,
            progress: (1.0 - (_flameValue / 4095.0)).clamp(0.0, 1.0),
            isDark: isDark,
          ),
        ];

        if (isNarrow) {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: c,
                    ))
                .toList(),
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 14),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 14),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildModernSensorCard({
    required String title,
    required String value,
    required String subtitle,
    required String status,
    required Color accentColor,
    required IconData icon,
    required double progress,
    required bool isDark,
  }) {
    final isBahaya = status == 'Bahaya';
    final isWaspada = status == 'Waspada';

    final Color statusColor = isBahaya
        ? const Color(0xFFEF4444)
        : (isWaspada ? const Color(0xFFF59E0B) : const Color(0xFF10B981));

    final Color cardBg = isBahaya
        ? (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2))
        : (isWaspada
            ? (isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB))
            : (isDark ? const Color(0xFF1E293B) : Colors.white));

    final Color borderColor = isBahaya
        ? const Color(0xFFEF4444)
        : (isWaspada ? const Color(0xFFF59E0B) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSensorDetail(title.replaceFirst(' MQ-2', '')),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: (isBahaya || isWaspada) ? 1.8 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: (isBahaya || isWaspada)
                    ? statusColor.withOpacity(0.18)
                    : Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: accentColor, size: 24),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Riwayat Suhu & Level Air',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '12 Pembacaan Terakhir',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _buildLegendItem('Suhu (°C)', const Color(0xFF3B82F6)),
                  const SizedBox(width: 14),
                  _buildLegendItem('Air (ADC)', const Color(0xFF06B6D4)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 160,
            child: CustomPaint(
              painter: _SmoothChartPainter(
                temperature: _temperatureHistory,
                water: _waterHistory,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              6,
              (i) => Text(
                '-${(5 - i) * 2}m',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildControlPanel(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Otomasi & Peringatan',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Text(
                _alarmOn ? 'Sistem Siaga' : 'Alarm Dibisukan',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _alarmOn ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInteractiveControlTile(
                  title: 'Alarm / Buzzer Suara',
                  subtitle: _alarmOn ? 'Suara peringatan aktif' : 'Dinonaktifkan',
                  icon: _alarmOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  activeColor: const Color(0xFF3B82F6),
                  value: _alarmOn,
                  onChanged: _setAlarmEnabled,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildInteractiveControlTile(
                  title: 'Exhaust Fan Ventilasi',
                  subtitle: _fanOn ? 'Kipas menyala (manual)' : 'Standby otomatis',
                  icon: Icons.wind_power_rounded,
                  activeColor: const Color(0xFF10B981),
                  value: _fanOn,
                  onChanged: (v) => setState(() => _fanOn = v),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveControlTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? activeColor.withOpacity(0.5) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: value ? activeColor.withOpacity(0.15) : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: value ? activeColor : (isDark ? Colors.white60 : Colors.black45), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }

  void _openBluetooth() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BluetoothConnectionSheet(
        onConnectionChanged: (connected) =>
            setState(() => _bluetoothConnected = connected),
        onSensorData: _applySensorData,
      ),
    );
  }

  Future<void> _enableSound() async {
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
      _lastPacketTime = DateTime.now();
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
}

class _SmoothChartPainter extends CustomPainter {
  final List<double> temperature;
  final List<double> water;
  final bool isDark;

  const _SmoothChartPainter({
    required this.temperature,
    required this.water,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.05)
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawSmoothArea(canvas, size, temperature, const Color(0xFF3B82F6), 15.0, 40.0);
    _drawSmoothArea(canvas, size, water, const Color(0xFF06B6D4), 0.0, 50.0);
  }

  void _drawSmoothArea(
    Canvas canvas,
    Size size,
    List<double> data,
    Color color,
    double defaultMin,
    double defaultMax,
  ) {
    if (data.isEmpty) return;
    final minVal = defaultMin;
    final maxVal = defaultMax;
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final normalized = ((data[i] - minVal) / range).clamp(0.0, 1.0);
      final y = size.height - (normalized * (size.height - 16)) - 8;
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.22), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);

    final dotPaint = Paint()..color = color;
    final innerDot = Paint()..color = Colors.white;
    for (final p in points) {
      canvas.drawCircle(p, 3.5, dotPaint);
      canvas.drawCircle(p, 1.5, innerDot);
    }
  }

  @override
  bool shouldRepaint(covariant _SmoothChartPainter oldDelegate) => true;
}
