import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/sensor_data.dart';
import 'sensor_detail_screen.dart';
import '../app_theme.dart';
import 'bluetooth_connection_sheet.dart';
import '../services/esp32_http_service.dart';
import '../services/notification_store.dart';

class MonitoringHomeScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigate;
  const MonitoringHomeScreen({Key? key, this.onNavigate}) : super(key: key);
  @override
  State<MonitoringHomeScreen> createState() => _MonitoringHomeScreenState();
}

class _MonitoringHomeScreenState extends State<MonitoringHomeScreen> {
  double _temp = 26.5;
  int _gas = 145;
  int _water = 0;
  int _flameValue = 4095;
  bool _flame = false;
  bool _alarmOn = true;
  bool _fanOn = false;
  bool _bluetoothConnected = false;
  bool _apiConnected = false;
  bool _fetchInFlight = false;
  int _consecutiveFailures = 0;
  final FlutterTts _tts = FlutterTts();
  bool _soundEnabled = false;
  bool _speakingWarning = false;
  String _lastAlarmState = 'Aman';
  String? _apiError;
  Timer? _timer;
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

  @override
  void initState() {
    super.initState();
    _fetchEsp32Data();
    // ESP32 memperbarui sensor sekitar 200 ms; polling 500 ms membuat
    // perubahan flame/water lebih cepat terlihat di web.
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _fetchEsp32Data(),
    );
  }

  Future<void> _fetchEsp32Data() async {
    if (_bluetoothConnected || _fetchInFlight) return;
    _fetchInFlight = true;
    try {
      final data = await Esp32HttpService.fetchSensors();
      if (!mounted) return;

      final temperature = (data['temperature_c'] ??
          data['temperature'] ??
          data['temp']) as num?;
      final gas = (data['gas_raw'] ?? data['mq2_value']) as num?;
      final flameValue = data['flame_value'] as num?;
      final water = (data['water_value'] ?? data['water_raw']) as num?;
      final flame = flameValue != null
          ? flameValue < 2500
          : data['flame_detected'] == true;

      setState(() {
        _apiConnected = true;
        _consecutiveFailures = 0;
        _apiError = null;
        if (temperature != null) {
          _temp = temperature.toDouble();
          _temperatureHistory.add(_temp);
          if (_temperatureHistory.length > 12) {
            _temperatureHistory.removeAt(0);
          }
        }
        if (gas != null) _gas = gas.toInt();
        if (flameValue != null) _flameValue = flameValue.toInt();
        if (water != null) {
          _water = water.toInt();
          _waterHistory.add(_water.toDouble());
          if (_waterHistory.length > 12) _waterHistory.removeAt(0);
        }
        _flame = flame;
      });
      _playAlarmIfNeeded();
    } catch (error) {
      if (!mounted) return;
      _consecutiveFailures++;
      setState(() {
        // Pertahankan status online untuk gangguan singkat jaringan.
        // Baru tampilkan offline setelah 3 request berturut-turut gagal.
        if (_consecutiveFailures >= 3) _apiConnected = false;
        // Jangan menampilkan banner pada satu kegagalan jaringan sementara.
        _apiError = _consecutiveFailures >= 3 ? error.toString() : null;
      });
    } finally {
      _fetchInFlight = false;
    }
  }

  String _temperatureStatus() => _temp >= 32
      ? 'Bahaya'
      : (_temp >= 27 || _temp < 18 ? 'Waspada' : 'Normal');
  String _gasStatus() =>
      _gas >= 1200 ? 'Bahaya' : (_gas >= 600 ? 'Waspada' : 'Aman');
  String _flameStatus() => (_flame || _flameValue < 2500)
      ? 'Bahaya'
      : (_flameValue < 3500 ? 'Waspada' : 'Aman');
  String _waterStatus() =>
      _water >= 20 ? 'Bahaya' : (_water >= 10 ? 'Waspada' : 'Aman');

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
    unawaited(
      Esp32HttpService.sendNotification(
        sensor: sensor,
        level: level,
        message: message,
        value: value,
      ),
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
    _timer?.cancel();
    unawaited(_tts.stop());
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
              color:
                  (_apiConnected
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B))
                      .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  color: _apiConnected
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                  size: 8,
                ),
                const SizedBox(width: 6),
                Text(
                  _apiConnected ? 'API Online' : 'API Offline',
                  style: TextStyle(
                    color: _apiConnected
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
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
                  'Gagal membaca ESP32: $_apiError',
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
                    ' °C',
                    '42sp',
                    'Normal',
                    const Color(0xFF3B82F6),
                    Icons.thermostat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSensorCard(
                    'Level Air',
                    ' ADC',
                    '42sp',
                    'Aman',
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
                    ' PPM',
                    '42sp',
                    'Aman',
                    const Color(0xFF10B981),
                    Icons.air,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSensorCard(
                    'Deteksi Api',
                    _flame ? 'API ADA' : 'TIDAK ADA API',
                    '42sp',
                    'Aman',
                    const Color(0xFF10B981),
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
        onSensorData: _applyBluetoothSensorData,
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
      }
    });
    if (enabled) unawaited(_enableSound());
  }

  void _applyBluetoothSensorData(Map<String, dynamic> data) {
    final temperature = (data['temperature_c'] as num?)?.toDouble();
    final gas = (data['gas_raw'] as num?)?.toInt();
    final flame = data['flame_detected'];
      final flameValue = (data['flame_value'] as num?)?.toInt();
    if (!mounted) return;
    setState(() {
      if (temperature != null) {
        _temp = temperature;
        _temperatureHistory.add(temperature);
        if (_temperatureHistory.length > 12) _temperatureHistory.removeAt(0);
      }
      if (gas != null) _gas = gas;
      if (flameValue != null) {
        _flameValue = flameValue;
        _flame = flameValue < 2500;
      }
      final water = (data['water_value'] ?? data['water_raw']) as num?;
      if (water != null) {
        _water = water.toInt();
        _waterHistory.add(_water.toDouble());
        if (_waterHistory.length > 12) _waterHistory.removeAt(0);
      }
      if (flame is bool) _flame = flame;
    });
    _playAlarmIfNeeded();
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
    final cardColor = currentStatus == 'Bahaya'
        ? const Color(0xFFEF4444)
        : currentStatus == 'Waspada'
        ? const Color(0xFFFBBF24)
        : Colors.white;
    final cardTextColor = Colors.black87;
    return SizedBox(
      height: 145,
      child: InkWell(
        onTap: () => _openSensorDetail(title),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(
                  alpha:
                      currentStatus == 'Normal' ||
                          currentStatus == 'Ideal' ||
                          currentStatus == 'Aman'
                      ? 0.08
                      : 0.3,
                ),
                blurRadius:
                    currentStatus == 'Bahaya' || currentStatus == 'Waspada'
                    ? 14
                    : 8,
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
                        color: cardTextColor.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '14sp',
                    style: TextStyle(
                      fontSize: 10,
                      color: cardTextColor.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: animation,
                                  child: child,
                                ),
                              ),
                          child: Text(
                            currentValue,
                            key: ValueKey(currentValue),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            color: cardTextColor.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      currentStatus == 'Normal' ||
                          currentStatus == 'Ideal' ||
                          currentStatus == 'Aman'
                      ? statusColor.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  currentStatus,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
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
