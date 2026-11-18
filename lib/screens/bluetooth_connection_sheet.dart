import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothConnectionSheet extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>>? onSensorData;
  final ValueChanged<bool>? onConnectionChanged;

  const BluetoothConnectionSheet({
    super.key,
    this.onSensorData,
    this.onConnectionChanged,
  });

  @override
  State<BluetoothConnectionSheet> createState() => _BluetoothConnectionSheetState();
}

class _BluetoothConnectionSheetState extends State<BluetoothConnectionSheet> {
  StreamSubscription<List<int>>? _dataSubscription;
  BluetoothDevice? _connectedDevice;
  bool _scanning = false;
  String? _error;
  String? _lastPayload;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception('Perangkat/browser tidak mendukung Bluetooth');
      }
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(ScanResult result) async {
    setState(() => _error = null);
    try {
      await FlutterBluePlus.stopScan();
      await result.device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );

      final services = await result.device.discoverServices();
      BluetoothCharacteristic? characteristic;
      for (final service in services) {
        for (final item in service.characteristics) {
          if (item.properties.notify || item.properties.read) {
            characteristic = item;
            break;
          }
        }
        if (characteristic != null) break;
      }

      if (characteristic == null) {
        await result.device.disconnect();
        throw Exception('Characteristic sensor tidak ditemukan');
      }

      _dataSubscription?.cancel();
      _connectedDevice = result.device;
      if (characteristic.properties.notify) {
        await characteristic.setNotifyValue(true);
        _dataSubscription = characteristic.onValueReceived.listen(_handleData);
      }
      if (characteristic.properties.read) {
        _handleData(await characteristic.read());
      }
      widget.onConnectionChanged?.call(true);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _handleData(List<int> bytes) {
    final payload = utf8.decode(bytes, allowMalformed: true).trim();
    if (payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        // Teruskan seluruh payload BLE agar monitoring menerima nilai asli
        // dari ESP32, termasuk mq2_value, flame_value, water_value, status,
        // dan trigger_reason.
        final data = Map<String, dynamic>.from(decoded);
        if (data.isEmpty) return;
        widget.onSensorData?.call(data);
        if (mounted) setState(() => _lastPayload = payload);
      }
    } catch (_) {
      if (mounted) setState(() => _lastPayload = payload);
    }
  }

  Future<void> _disconnect() async {
    await _dataSubscription?.cancel();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    widget.onConnectionChanged?.call(false);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectedDevice?.disconnect();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth, color: Color(0xFF2563EB)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Bluetooth ESP32', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(onPressed: _scanning ? null : _scan, icon: const Icon(Icons.refresh)),
              ],
            ),
            Text(
              _connectedDevice == null ? 'Pilih perangkat ESP32 untuk membaca sensor.' : 'Terhubung: ${_connectedDevice!.platformName}',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_lastPayload != null) ...[
              const SizedBox(height: 8),
              Text('Data terakhir: $_lastPayload', maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            if (_connectedDevice != null)
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _disconnect, icon: const Icon(Icons.bluetooth_disabled), label: const Text('Putuskan')))
            else
              StreamBuilder<List<ScanResult>>(
                stream: FlutterBluePlus.scanResults,
                initialData: const [],
                builder: (context, snapshot) {
                  final results = snapshot.data ?? const <ScanResult>[];
                  if (_scanning && results.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                  if (results.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('ESP32 belum ditemukan')));
                  return SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
                        final name = result.device.platformName.isEmpty ? 'ESP32 (${result.device.remoteId})' : result.device.platformName;
                        return ListTile(leading: const Icon(Icons.memory), title: Text(name), subtitle: Text(result.device.remoteId.toString()), trailing: const Icon(Icons.chevron_right), onTap: () => _connect(result));
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
