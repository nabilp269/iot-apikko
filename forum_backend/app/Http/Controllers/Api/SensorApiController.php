<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\SensorReading;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SensorApiController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string', 'max:100'],
            'temperature_c' => ['required', 'numeric'],
            'humidity_pct' => ['required', 'numeric', 'between:0,100'],
            'flame_detected' => ['required', 'boolean'],
            'gas_raw' => ['nullable', 'integer', 'min:0'],
        ]);

        $status = $this->status($data);
        $reading = SensorReading::create([...$data, 'status' => $status, 'received_at' => now()]);
        Device::updateOrCreate(['device_id' => $data['device_id']], [
            'status' => 'online',
            'last_seen_at' => now(),
        ]);

        return response()->json(['message' => 'Data sensor diterima', 'data' => $reading], 201);
    }

    public function latest(Request $request): JsonResponse
    {
        $reading = SensorReading::query()
            ->when($request->device_id, fn ($query, $id) => $query->where('device_id', $id))
            ->latest('received_at')
            ->first();

        if (!$reading) return response()->json(['data' => null]);
        return response()->json(['data' => $reading]);
    }

    public function history(Request $request): JsonResponse
    {
        $readings = SensorReading::query()
            ->when($request->device_id, fn ($query, $id) => $query->where('device_id', $id))
            ->latest('received_at')->limit((int) $request->input('limit', 100))->get()->reverse()->values();
        return response()->json(['data' => $readings]);
    }

    private function status(array $data): string
    {
        if ($data['flame_detected'] || $data['temperature_c'] >= 32 || ($data['gas_raw'] ?? 0) >= 2800) return 'bahaya';
        if ($data['temperature_c'] >= 27 || $data['temperature_c'] < 18 || $data['humidity_pct'] < 30 || $data['humidity_pct'] > 60 || ($data['gas_raw'] ?? 0) >= 1800) return 'waspada';
        return 'normal';
    }
}
