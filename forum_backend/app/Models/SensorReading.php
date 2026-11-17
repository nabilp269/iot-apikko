<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SensorReading extends Model
{
    protected $fillable = ['device_id', 'temperature_c', 'humidity_pct', 'flame_detected', 'gas_raw', 'status', 'received_at'];
    protected $casts = ['flame_detected' => 'boolean', 'received_at' => 'datetime'];
}
