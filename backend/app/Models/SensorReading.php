<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SensorReading extends Model
{
    protected $fillable = [
        'device_id',
        'mq2_value',
        'flame_value',
        'water_value',
        'status',
        'trigger_reason',
        'rssi',
        'uptime_s',
        'temperature_c',
        'humidity_pct',
        'flame_detected',
        'gas_raw',
        'received_at',
    ];

    protected $casts = [
        'mq2_value'      => 'integer',
        'flame_value'    => 'integer',
        'water_value'    => 'integer',
        'rssi'           => 'integer',
        'uptime_s'       => 'integer',
        'flame_detected' => 'boolean',
        'received_at'    => 'datetime',
    ];
}
