<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\SensorReading;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SensorApiController extends Controller
{
    /**
     * POST /api/iot/server-room
     * Sesuai dokumen spesifikasi iot-server-room-api.md:
     * Header: Authorization: Bearer <DEVICE_TOKEN>
     * Body: { "gas": 567, "flame": 4095, "water": 0, "device_id": "server-room-1" }
     */
    public function serverRoom(Request $request): JsonResponse
    {
        // 1. Validasi Bearer Token
        $expectedToken = (string) env('DEVICE_TOKEN', 'apikko-secret-token-2026');
        $authHeader = (string) $request->header('Authorization', '');
        
        if (!empty($expectedToken) && $expectedToken !== 'none') {
            if (!str_starts_with($authHeader, 'Bearer ') || substr($authHeader, 7) !== $expectedToken) {
                return response()->json([
                    'message' => 'Unauthorized: Token salah atau tidak ada',
                ], 401);
            }
        }

        // 2. Validasi Nilai Mentah Sensor (0 - 4095)
        $data = $request->validate([
            'gas'       => ['required', 'integer', 'between:0,4095'],
            'flame'     => ['required', 'integer', 'between:0,4095'],
            'water'     => ['required', 'integer', 'between:0,4095'],
            'device_id' => ['nullable', 'string', 'max:100'],
            'rssi'      => ['nullable', 'integer'],
            'uptime_s'  => ['nullable', 'integer'],
        ]);

        $deviceId = $data['device_id'] ?? 'server-room-1';
        $status = $this->calculateStatus((int) $data['gas'], (int) $data['flame'], (int) $data['water']);

        // 3. Simpan Telemetry ke Database
        $reading = SensorReading::create([
            'device_id'      => $deviceId,
            'mq2_value'      => (int) $data['gas'],
            'flame_value'    => (int) $data['flame'],
            'water_value'    => (int) $data['water'],
            'status'         => $status,
            'trigger_reason' => $status !== 'AMAN' ? $status : 'NONE',
            'flame_detected' => (int) $data['flame'] < 2000,
            'gas_raw'        => (int) $data['gas'],
            'received_at'    => now(),
        ]);

        // Perbarui Perangkat (Online)
        Device::updateOrCreate(
            ['device_id' => $deviceId],
            [
                'status'       => 'online',
                'last_seen_at' => now(),
            ]
        );

        return response()->json([
            'status'  => 'success',
            'message' => 'Data sensor server room berhasil diterima',
            'data'    => $reading,
        ], 200);
    }

    /**
     * POST /api/sensor-readings
     * Endpoint penerima umum untuk ESP32 / MQTT Bridge.
     */
    public function store(Request $request): JsonResponse
    {
        $deviceId = $request->input('device_id', $request->input('device', 'ESP32_SMART_MOTOR'));
        $mq2Val   = $request->input('mq2_value', $request->input('gas', $request->input('gas_raw', 0)));
        $flameVal = $request->input('flame_value', $request->input('flame', 4095));
        $waterVal = $request->input('water_value', $request->input('water', 0));
        $trigger  = $request->input('trigger_reason', 'NONE');

        $status = $request->input('status');
        if (empty($status) || $status === 'normal') {
            $status = $this->calculateStatus((int) $mq2Val, (int) $flameVal, (int) $waterVal);
        } else {
            $status = strtoupper($status);
        }

        $reading = SensorReading::create([
            'device_id'      => $deviceId,
            'mq2_value'      => (int) $mq2Val,
            'flame_value'    => (int) $flameVal,
            'water_value'    => (int) $waterVal,
            'status'         => $status,
            'trigger_reason' => $trigger,
            'temperature_c'  => $request->input('temperature_c'),
            'humidity_pct'   => $request->input('humidity_pct'),
            'flame_detected' => (int) $flameVal < 2000 || (bool) $request->input('flame_detected', false),
            'gas_raw'        => (int) $mq2Val,
            'received_at'    => now(),
        ]);

        Device::updateOrCreate(
            ['device_id' => $deviceId],
            [
                'status'       => 'online',
                'last_seen_at' => now(),
            ]
        );

        return response()->json([
            'status'  => 'success',
            'message' => 'Data telemetry sensor berhasil disimpan',
            'data'    => $reading,
        ], 201);
    }

    /**
     * GET /api/sensor-latest
     * Mengambil 1 data telemetry terbaru untuk dashboard Flutter / Web.
     */
    public function latest(Request $request): JsonResponse
    {
        $deviceId = $request->query('device_id');

        $reading = SensorReading::query()
            ->when($deviceId, fn ($query, $id) => $query->where('device_id', $id))
            ->latest('id')
            ->first();

        if (!$reading) {
            return response()->json([
                'status'  => 'success',
                'message' => 'Belum ada data sensor',
                'data'    => null,
            ]);
        }

        return response()->json([
            'status' => 'success',
            'data'   => $reading,
        ]);
    }

    /**
     * GET /api/sensor-history
     * Mengambil riwayat data telemetry untuk grafik / chart.
     */
    public function history(Request $request): JsonResponse
    {
        $deviceId = $request->query('device_id');
        $limit    = min((int) $request->query('limit', 50), 200);
        $sensor   = $request->query('sensor');

        $query = SensorReading::query()
            ->when($deviceId, fn ($q, $id) => $q->where('device_id', $id));

        if ($sensor === 'mq2' || $sensor === 'gas') {
            $query->select(['id', 'device_id', 'mq2_value', 'status', 'received_at', 'created_at']);
        } elseif ($sensor === 'flame') {
            $query->select(['id', 'device_id', 'flame_value', 'status', 'received_at', 'created_at']);
        } elseif ($sensor === 'water') {
            $query->select(['id', 'device_id', 'water_value', 'status', 'received_at', 'created_at']);
        }

        $readings = $query->latest('id')
            ->limit($limit)
            ->get()
            ->reverse()
            ->values();

        return response()->json([
            'status' => 'success',
            'total'  => $readings->count(),
            'data'   => $readings,
        ]);
    }

    /**
     * GET /api/devices
     * Mengambil status perangkat (online/offline).
     */
    public function devices(): JsonResponse
    {
        $devices = Device::all()->map(function ($device) {
            // Jika tidak mengirim data > 30 detik, anggap offline (sesuai spesifikasi)
            $isOnline = $device->last_seen_at && $device->last_seen_at->diffInSeconds(now()) < 30;
            $device->is_online = $isOnline;
            $device->status = $isOnline ? 'online' : 'offline';
            return $device;
        });

        return response()->json([
            'status' => 'success',
            'data'   => $devices,
        ]);
    }

    /**
     * Logika Ambang Batas Sensor (Threshold ADC)
     */
    private function calculateStatus(int $gas, int $flame, int $water): string
    {
        // Bahaya: Gas >= 1200, Flame < 2000, Water >= 20
        if ($gas >= 1200 || $flame < 2000 || $water >= 20) {
            return 'BAHAYA';
        }
        // Waspada: Gas >= 600, Flame < 2700
        if ($gas >= 600 || $flame < 2700) {
            return 'WASPADA';
        }
        return 'AMAN';
    }
}
