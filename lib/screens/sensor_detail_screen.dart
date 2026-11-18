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

  Widget _buildScreen(BuildContext context) {
    final statusColor = _getStatusColor();
    final percentage = _getPercentage();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
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
              _sensor.location ?? 'Server Room',
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
                  _sensor.status.name.toUpperCase(),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Main reading cards
            Row(
              children: [
                Expanded(
                  child: _buildCircularGauge(
                    'CURRENT',
                    _sensor.currentValue,
                    _sensor.unit,
                    statusColor,
                    percentage,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCircularGauge(
                    'AVG 24H',
                    _calculateAverage(),
                    _sensor.unit,
                    const Color(0xFF2563EB),
                    0.65,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Control section
            Container(
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
                    'CONTROLS',
                    style: TextStyle(
                      color: Colors.black45,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Monitoring toggle
                  _buildControlButton(
                    icon: _isMonitoring
                        ? Icons.pause_circle
                        : Icons.play_circle,
                    label: _isMonitoring ? 'STOP' : 'START',
                    subtitle: 'Monitoring',
                    color: _isMonitoring
                        ? Colors.white
                        : const Color(0xFF1E3A8A),
                    textColor: _isMonitoring ? Colors.black87 : Colors.white,
                    onTap: () => setState(() => _isMonitoring = !_isMonitoring),
                  ),
                  const SizedBox(height: 12),

                  // Alert button
                  _buildControlButton(
                    icon: Icons.notifications_active,
                    label: 'ALERTS',
                    subtitle: _isMonitoring ? 'Active' : 'Inactive',
                    color: const Color(0xFF1E3A8A),
                    textColor: Colors.white,
                    onTap: () {},
                  ),
                  const SizedBox(height: 12),

                  // Reset button
                  _buildControlButton(
                    icon: Icons.refresh,
                    label: 'RESET',
                    subtitle: 'Clear data',
                    color: const Color(0xFF1E3A8A),
                    textColor: Colors.white,
                    onTap: () {},
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Stats cards
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'MIN',
                    _getMin(),
                    _sensor.unit,
                    const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'MAX',
                    _getMax(),
                    _sensor.unit,
                    const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'BATTERY',
                    _sensor.batteryLevel != null ? '%' : 'N/A',
                    '',
                    const Color(0xFF8B5CF6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'UPTIME',
                    '24h',
                    '',
                    const Color(0xFF06B6D4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
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
      ),
    );
  }

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
                // Background arc
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _CircularGaugePainter(
                    percentage: 1.0,
                    color: Colors.grey.shade200,
                    strokeWidth: 12,
                  ),
                ),
                // Animated value arc
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
                // Value text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value.toStringAsFixed(1),
                      style: TextStyle(
                        color: color,
                        fontSize: 32,
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
              '%',
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

  double _getPercentage() {
    final thresholds = _sensor.thresholds;
    if (thresholds == null || thresholds.dangerThreshold == null) return 0.5;
    return (_sensor.currentValue / thresholds.dangerThreshold!).clamp(0.0, 1.0);
  }

  double _calculateAverage() {
    final data = _sensor.historicalData;
    if (data == null || data.isEmpty) return _sensor.currentValue;
    return data.map((e) => e.value).reduce((a, b) => a + b) / data.length;
  }

  String _getMin() {
    final data = _sensor.historicalData;
    if (data == null || data.isEmpty)
      return _sensor.currentValue.toStringAsFixed(1);
    return data.map((e) => e.value).reduce(math.min).toStringAsFixed(1);
  }

  String _getMax() {
    final data = _sensor.historicalData;
    if (data == null || data.isEmpty)
      return _sensor.currentValue.toStringAsFixed(1);
    return data.map((e) => e.value).reduce(math.max).toStringAsFixed(1);
  }
}

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
