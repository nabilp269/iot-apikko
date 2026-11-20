<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class NotificationSchedule extends Model
{
    protected $fillable = [
        'sensor_trigger', 'trigger', 'date', 'channel', 'interval', 'enabled',
    ];

    protected $casts = [
        'date' => 'datetime',
        'enabled' => 'boolean',
    ];
}
