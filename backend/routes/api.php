<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\SensorApiController;
use App\Http\Controllers\Api\NotificationScheduleController;

// 1. Health check & Info
Route::get('/health', function () {
    return response()->json([
        'status'    => 'ok',
        'service'   => 'Smart Motor IoT Backend API',
        'version'   => '1.0.0',
        'timestamp' => now()->toIso8601String(),
    ]);
});

// 2. Endpoint Khusus Agora Server Room (Sesuai dokumen iot-server-room-api.md)
// POST https://agora.apikkedu.com/api/iot/server-room
Route::post('/iot/server-room', [SensorApiController::class, 'serverRoom']);

// 3. Endpoint Telemetry Sensor IoT
Route::post('/sensor-readings', [SensorApiController::class, 'store']);
Route::get('/sensor-latest', [SensorApiController::class, 'latest']);
Route::get('/sensor-history', [SensorApiController::class, 'history']);

// 4. Endpoint Perangkat
Route::get('/devices', [SensorApiController::class, 'devices']);

// 5. Endpoint Jadwal Notifikasi
Route::get('/notification-schedules', [NotificationScheduleController::class, 'index']);
Route::post('/notification-schedules', [NotificationScheduleController::class, 'store']);

// 6. Endpoint Testing / Simulasi
Route::post('/simulate', function () {
    $req = request()->merge([
        'device_id'   => 'SIMULATED_ESP32',
        'mq2_value'   => rand(70, 200),
        'flame_value' => rand(2800, 3200),
        'water_value' => 0,
        'status'      => 'AMAN',
    ]);
    return app(SensorApiController::class)->store($req);
});
