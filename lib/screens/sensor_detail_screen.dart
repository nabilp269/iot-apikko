import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import '../models/sensor_data.dart';

class SensorDetailScreen extends StatefulWidget {
  final SensorData sensorData;
  final ValueListenable<SensorData>? liveSensorData;
  final ValueChanged<int>? onNavigate;
  const SensorDetailScreen({
    Key? key,
    required this.sensorData,
    this.liveSensorData,
    this.onNavigate,
  }) : super(key: key);

  @override
  State<SensorDetailScreen> createState() => _SensorDetailScreenState();
}

class _SensorDetailScreenState extends State<SensorDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isMonitoring = true;

  SensorData get _sensor => widget.liveSensorData?.value ?? widget.sensorData;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveSensorData = widget.liveSensorData;
    if (liveSensorData != null) {
      return ValueListenableBuilder<SensorData>(
        valueListenable: liveSensorData,
        builder: (_, __, ___) => _buildScreen(context),
      );
    }
    return _buildScreen(context);
  }

  // ─── Routing berdasarkan SensorType ───
  Widget _buildScreen(BuildContext context) {
    final statusColor = _getStatusColor();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: _buildAppBar(statusColor),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildSensorSpecificBody(statusColor),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildSensorSpecificBody(Color statusColor) {
    switch (_sensor.type) {
      case SensorType.temperature:
        return _buildTemperatureBody(statusColor);
      case SensorType.flame:
        return _buildFlameBody(statusColor);
      case SensorType.gas:
        return _buildGasBody(statusColor);
      case SensorType.humidity:
        return _buildWaterBody(statusColor);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  SUHU (Temperature) Detail
  // ══════════════════════════════════════════════════════════════
  Widget _buildTemperatureBody(Color statusColor) {
    final percentage = _getPercentage();
    final avg = _calculateAverage();
    final avgPct = _sensor.thresholds?.dangerThreshold != null
        ? (avg / _sensor.thresholds!.dangerThreshold!).clamp(0.0, 1.0)
        : 0.5;

    return Column(
      children: [
        // Gauge besar tengah
        Row(
          children: [
            Expanded(
              child: _buildCircularGauge(
                'SAAT INI',
                _sensor.currentValue,
                _sensor.unit,
                statusColor,
                percentage,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildCircularGauge(
                'RATA-RATA',
                avg,
                _sensor.unit,
                const Color(0xFF2563EB),
                avgPct,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Threshold indicator
        _buildThresholdBar(
          label: 'Ambang Batas Suhu',
          currentValue: _sensor.currentValue,
          warningValue: 27,
          dangerValue: 32,
          minValue: 10,
          maxValue: 50,
          unit: '°C',
          statusColor: statusColor,
        ),
        const SizedBox(height: 20),

        // Stats MIN / MAX
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'MIN',
                '${_getMinValue().toStringAsFixed(1)}',
                '°C',
                const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'MAX',
                '${_getMaxValue().toStringAsFixed(1)}',
                '°C',
                const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'RATA-RATA',
                avg.toStringAsFixed(1),
                '°C',
                const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'STATUS',
                _statusLabel(),
                '',
                statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Mini chart
        if (_sensor.historicalData != null &&
            _sensor.historicalData!.isNotEmpty)
          _buildHistoryChart(
            'Riwayat Suhu',
            const Color(0xFF3B82F6),
          ),

        const SizedBox(height: 20),
        _buildControlSection(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  DETEKSI API (Flame) Detail
  // ══════════════════════════════════════════════════════════════
  Widget _buildFlameBody(Color statusColor) {
    final isFireDetected = _sensor.status == SensorStatus.danger;
    final isWaspada = _sensor.status == SensorStatus.warning;
    final flameAdc = _sensor.currentValue;

    return Column(
      children: [
        // Alert besar jika api terdeteksi
        AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final pulse = isFireDetected
                ? (0.6 + 0.4 * math.sin(_animController.value * math.pi * 2))
                : 1.0;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isFireDetected
                    ? Color.lerp(
                        const Color(0xFFEF4444),
                        const Color(0xFFDC2626),
                        pulse,
                      )
                    : isWaspada
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  if (isFireDetected)
                    BoxShadow(
                      color: const Color(0xFFEF4444)
                          .withValues(alpha: 0.5 * pulse),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    isFireDetected
                        ? Icons.local_fire_department
                        : isWaspada
                            ? Icons.warning_rounded
                            : Icons.check_circle,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isFireDetected
                        ? '🔥 API TERDETEKSI!'
                        : isWaspada
                            ? '⚠️ WASPADA API'
                            : '✅ TIDAK ADA API',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isFireDetected
                        ? 'Sensor mendeteksi api di area monitoring'
                        : isWaspada
                            ? 'Sensor mendekati ambang batas'
                            : 'Area monitoring aman dari api',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),

        // ADC Value gauge
        _buildCircularGauge(
          'NILAI ADC SENSOR',
          flameAdc,
          'ADC',
          statusColor,
          (flameAdc / 4095).clamp(0.0, 1.0),
        ),
        const SizedBox(height: 20),

        // Threshold bar
        _buildThresholdBar(
          label: 'Ambang Batas Api (ADC)',
          currentValue: flameAdc,
          warningValue: 3500,
          dangerValue: 2500,
          minValue: 0,
          maxValue: 4095,
          unit: 'ADC',
          statusColor: statusColor,
          invertedScale: true,
        ),
        const SizedBox(height: 20),

        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'INFO SENSOR',
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                  'Nilai ADC', flameAdc.toStringAsFixed(0)),
              _buildInfoRow('Bahaya jika', '< 2500 ADC'),
              _buildInfoRow('Waspada jika', '< 3500 ADC'),
              _buildInfoRow(
                'Status',
                isFireDetected
                    ? 'API TERDETEKSI'
                    : isWaspada
                        ? 'WASPADA'
                        : 'AMAN',
              ),
              _buildInfoRow(
                'Update terakhir',
                _formatTime(_sensor.lastUpdate),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildControlSection(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SENSOR GAS (MQ-2) Detail
  // ══════════════════════════════════════════════════════════════
  Widget _buildGasBody(Color statusColor) {
    final ppm = _sensor.currentValue;
    final percentage = _getPercentage();

    return Column(
      children: [
        // Gauge PPM
        _buildCircularGauge(
          'KONSENTRASI GAS',
          ppm,
          'PPM',
          statusColor,
          percentage,
        ),
        const SizedBox(height: 20),

        // Concentration bar
        _buildConcentrationBar(ppm, statusColor),
        const SizedBox(height: 20),

        // Threshold bar
        _buildThresholdBar(
          label: 'Ambang Batas Gas',
          currentValue: ppm,
          warningValue: 600,
          dangerValue: 1200,
          minValue: 0,
          maxValue: 2000,
          unit: 'PPM',
          statusColor: statusColor,
        ),
        const SizedBox(height: 20),

        // Stats
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'SAAT INI',
                ppm.toStringAsFixed(0),
                'PPM',
                statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'STATUS',
                _statusLabel(),
                '',
                statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'WASPADA',
                '≥ 600',
                'PPM',
                const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'BAHAYA',
                '≥ 1200',
                'PPM',
                const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // History chart
        if (_sensor.historicalData != null &&
            _sensor.historicalData!.isNotEmpty)
          _buildHistoryChart(
            'Riwayat Gas',
            const Color(0xFF10B981),
          ),
        const SizedBox(height: 20),
        _buildControlSection(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  LEVEL AIR (Water Level) Detail
  // ══════════════════════════════════════════════════════════════
  Widget _buildWaterBody(Color statusColor) {
    final waterVal = _sensor.currentValue;
    final percentage = _getPercentage();

    return Column(
      children: [
        // Water level visual
        Row(
          children: [
            Expanded(
              child: _buildCircularGauge(
                'LEVEL AIR',
                waterVal,
                'ADC',
                statusColor,
                percentage,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildWaterTankVisual(waterVal, statusColor)),
          ],
        ),
        const SizedBox(height: 20),

        // Threshold bar
        _buildThresholdBar(
          label: 'Ambang Batas Air',
          currentValue: waterVal,
          warningValue: 10,
          dangerValue: 20,
          minValue: 0,
          maxValue: 40,
          unit: 'ADC',
          statusColor: statusColor,
        ),
        const SizedBox(height: 20),

        // Stats
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'MIN',
                '${_getMinValue().toStringAsFixed(0)}',
                'ADC',
                const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'MAX',
                '${_getMaxValue().toStringAsFixed(0)}',
                'ADC',
                const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'RATA-RATA',
                _calculateAverage().toStringAsFixed(1),
                'ADC',
                const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'STATUS',
                _statusLabel(),
                '',
                statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // History chart
        if (_sensor.historicalData != null &&
            _sensor.historicalData!.isNotEmpty)
          _buildHistoryChart(
            'Riwayat Level Air',
            const Color(0xFF0EA5E9),
          ),
        const SizedBox(height: 20),
        _buildControlSection(),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ══════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(Color statusColor) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _sensor.name,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _sensor.location ?? 'Ruang Server',
            style: const TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _statusLabel(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Beranda'),
        BottomNavigationBarItem(
          icon: Icon(Icons.schedule),
          label: 'Jadwal Kirim',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.notifications),
          label: 'Notifikasi',
        ),
      ],
      onTap: (index) {
        if (index == 0) {
          Navigator.pop(context);
        } else {
          widget.onNavigate?.call(index);
          Navigator.pop(context);
        }
      },
    );
  }

  // ─── Circular Gauge ───
  Widget _buildCircularGauge(
    String label,
    double value,
    String unit,
    Color color,
    double percentage,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black45,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _CircularGaugePainter(
                    percentage: 1.0,
                    color: Colors.grey.shade200,
                    strokeWidth: 12,
                  ),
                ),
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(120, 120),
                      painter: _CircularGaugePainter(
                        percentage: percentage,
                        color: color,
                        strokeWidth: 12,
                      ),
                    );
                  },
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sensor.type == SensorType.temperature
                          ? value.toStringAsFixed(1)
                          : value.toStringAsFixed(0),
                      style: TextStyle(
                        color: color,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      unit,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${(percentage * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Threshold Bar ───
  Widget _buildThresholdBar({
    required String label,
    required double currentValue,
    required double warningValue,
    required double dangerValue,
    required double minValue,
    required double maxValue,
    required String unit,
    required Color statusColor,
    bool invertedScale = false,
  }) {
    final range = maxValue - minValue;
    final clampedVal = currentValue.clamp(minValue, maxValue);
    final position = (clampedVal - minValue) / range;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black45,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth;
                final indicatorPos = position * barWidth;
                final warnPos =
                    ((warningValue - minValue) / range) * barWidth;
                final dangerPos =
                    ((dangerValue - minValue) / range) * barWidth;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Bar background
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: invertedScale
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFEF4444),
                                    Color(0xFFFBBF24),
                                    Color(0xFF10B981),
                                  ],
                                )
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF10B981),
                                    Color(0xFFFBBF24),
                                    Color(0xFFEF4444),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    // Warning marker
                    Positioned(
                      top: 8,
                      left: warnPos - 1,
                      child: Container(
                        width: 2,
                        height: 24,
                        color: Colors.black38,
                      ),
                    ),
                    // Danger marker
                    Positioned(
                      top: 8,
                      left: dangerPos - 1,
                      child: Container(
                        width: 2,
                        height: 24,
                        color: Colors.black38,
                      ),
                    ),
                    // Current value indicator
                    Positioned(
                      top: 0,
                      left: indicatorPos - 8,
                      child: Container(
                        width: 16,
                        height: 40,
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${minValue.toStringAsFixed(0)} $unit',
                style: const TextStyle(color: Colors.black45, fontSize: 10),
              ),
              Text(
                'Waspada: ${warningValue.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                'Bahaya: ${dangerValue.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${maxValue.toStringAsFixed(0)} $unit',
                style: const TextStyle(color: Colors.black45, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Concentration Bar (Gas) ───
  Widget _buildConcentrationBar(double ppm, Color statusColor) {
    final fill = (ppm / 2000).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
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
              const Text(
                'KONSENTRASI',
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '${ppm.toStringAsFixed(0)} PPM',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 20,
              child: LinearProgressIndicator(
                value: fill,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('0', style: TextStyle(color: Colors.black45, fontSize: 10)),
              Text('600',
                  style: TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
              Text('1200',
                  style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
              Text('2000',
                  style: TextStyle(color: Colors.black45, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Water Tank Visual ───
  Widget _buildWaterTankVisual(double waterVal, Color statusColor) {
    final fillPercent = (waterVal / 40).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'VISUALISASI',
            style: TextStyle(
              color: Colors.black45,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 80,
            height: 120,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Tank outline
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                // Water fill
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      height: 120 * fillPercent,
                      width: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            statusColor.withValues(alpha: 0.5),
                            statusColor,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Level text
                Center(
                  child: Text(
                    '${(fillPercent * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: fillPercent > 0.4 ? Colors.white : Colors.black54,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${waterVal.toStringAsFixed(0)} ADC',
            style: TextStyle(
              color: statusColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─── History Chart ───
  Widget _buildHistoryChart(String title, Color lineColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 120,
            child: CustomPaint(
              painter: _MiniChartPainter(
                data:
                    _sensor.historicalData!.map((e) => e.value).toList(),
                lineColor: lineColor,
                fillColor: lineColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_sensor.historicalData!.length} titik data',
                style: const TextStyle(color: Colors.black45, fontSize: 10),
              ),
              Text(
                'Update: ${_formatTime(_sensor.lastUpdate)}',
                style: const TextStyle(color: Colors.black45, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Control Section ───
  Widget _buildControlSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'KONTROL',
            style: TextStyle(
              color: Colors.black45,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          _buildControlButton(
            icon:
                _isMonitoring ? Icons.pause_circle : Icons.play_circle,
            label: _isMonitoring ? 'STOP' : 'START',
            subtitle: 'Monitoring',
            color:
                _isMonitoring ? Colors.white : const Color(0xFF1E3A8A),
            textColor: _isMonitoring ? Colors.black87 : Colors.white,
            onTap: () => setState(() => _isMonitoring = !_isMonitoring),
          ),
          const SizedBox(height: 12),
          _buildControlButton(
            icon: Icons.notifications_active,
            label: 'ALERTS',
            subtitle: _isMonitoring ? 'Aktif' : 'Nonaktif',
            color: const Color(0xFF1E3A8A),
            textColor: Colors.white,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  // ─── Control Button ───
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color == Colors.white ? Colors.grey.shade300 : color,
            width: 2,
          ),
          boxShadow: color != Colors.white
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: textColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: textColor.withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Stat Card ───
  Widget _buildStatCard(String label, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Info Row ───
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════════

  Color _getStatusColor() {
    switch (_sensor.status) {
      case SensorStatus.normal:
        return const Color(0xFF10B981);
      case SensorStatus.warning:
        return const Color(0xFFF59E0B);
      case SensorStatus.danger:
        return const Color(0xFFEF4444);
    }
  }

  String _statusLabel() {
    switch (_sensor.status) {
      case SensorStatus.normal:
        return _sensor.type == SensorType.temperature ? 'NORMAL' : 'AMAN';
      case SensorStatus.warning:
        return 'WASPADA';
      case SensorStatus.danger:
        return 'BAHAYA';
    }
  }

  double _getPercentage() {
    final thresholds = _sensor.thresholds;
    if (thresholds == null || thresholds.dangerThreshold == null) return 0.5;

    if (_sensor.type == SensorType.flame) {
      // Flame: semakin rendah semakin bahaya (inverted)
      return (1.0 - _sensor.currentValue / 4095).clamp(0.0, 1.0);
    }
    return (_sensor.currentValue / thresholds.dangerThreshold!).clamp(0.0, 1.0);
  }

  double _calculateAverage() {
    final data = _sensor.historicalData;
    if (data == null || data.isEmpty) return _sensor.currentValue;
    return data.map((e) => e.value).reduce((a, b) => a + b) / data.length;
  }

  double _getMinValue() {
    final data = _sensor.historicalData;
    if (data == null || data.isEmpty) return _sensor.currentValue;
    return data.map((e) => e.value).reduce(math.min);
  }

  double _getMaxValue() {
    final data = _sensor.historicalData;
    if (data == null || data.isEmpty) return _sensor.currentValue;
    return data.map((e) => e.value).reduce(math.max);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════════
//  PAINTERS
// ══════════════════════════════════════════════════════════════

class _CircularGaugePainter extends CustomPainter {
  final double percentage;
  final Color color;
  final double strokeWidth;

  _CircularGaugePainter({
    required this.percentage,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2 - (math.pi * 0.75);
    final sweepAngle = (math.pi * 1.5) * percentage;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _MiniChartPainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color fillColor;

  _MiniChartPainter({
    required this.data,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final minVal = data.reduce(math.min) - 1;
    final maxVal = data.reduce(math.max) + 1;
    final range = maxVal - minVal;
    if (range <= 0) return;

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final linePath = Path();
    final fillPath = Path();

    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - ((data[i] - minVal) / range * size.height);
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);

    // Draw dots
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y = size.height - ((data[i] - minVal) / range * size.height);
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
