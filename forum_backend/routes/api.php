<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\SensorApiController;
use App\Http\Controllers\Api\NotificationScheduleController;

// Endpoint penerima data dari ESP32 (POST /api/sensor-readings)
Route::post('/sensor-readings', [SensorApiController::class, 'store']);

// Endpoint telemetry sensor live untuk aplikasi Mobile / Web (GET /api/sensor-latest)
Route::get('/sensor-latest', [SensorApiController::class, 'latest']);

// Endpoint riwayat data sensor untuk grafik (GET /api/sensor-history)
Route::get('/sensor-history', [SensorApiController::class, 'history']);

// Endpoint jadwal pengiriman dari aplikasi (header X-API-Key wajib)
Route::post('/notification-schedules', [NotificationScheduleController::class, 'store']);
