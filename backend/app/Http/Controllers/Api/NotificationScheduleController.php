<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\NotificationSchedule;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationScheduleController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $providedKey = (string) $request->header('X-API-Key');
        $expectedKey = (string) config('services.sensor_api.key');
        if ($expectedKey === '' || !hash_equals($expectedKey, $providedKey)) {
            return response()->json(['message' => 'API key tidak valid'], 401);
        }

        $data = $request->validate([
            'sensor_trigger' => ['required', 'string', 'max:50'],
            'trigger' => ['required', 'string', 'max:50'],
            'date' => ['required', 'date'],
            'channel' => ['required', 'in:telegram,message,none'],
            'interval' => ['nullable', 'string', 'max:30'],
            'enabled' => ['sometimes', 'boolean'],
        ]);

        $schedule = NotificationSchedule::create($data);
        return response()->json(['message' => 'Jadwal diterima', 'data' => $schedule], 201);
    }
}
