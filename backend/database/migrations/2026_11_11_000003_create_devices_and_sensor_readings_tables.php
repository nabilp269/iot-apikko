<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // 1. Tabel Perangkat IoT
        Schema::create('devices', function (Blueprint $table) {
            $table->id();
            $table->string('device_id')->unique(); // contoh: 'server-room-1'
            $table->string('name')->default('ESP32 Server Room Monitor');
            $table->string('location')->default('Ruang Server');
            $table->enum('status', ['online', 'offline'])->default('online');
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();
        });

        // 2. Tabel Telemetry Sensor (gas MQ-2, flame, water level)
        Schema::create('sensor_readings', function (Blueprint $table) {
            $table->id();
            $table->string('device_id')->default('server-room-1');
            $table->integer('mq2_value')->default(0);    // Nilai gas (ADC 0-4095)
            $table->integer('flame_value')->default(0);  // Nilai flame (ADC 0-4095)
            $table->integer('water_value')->default(0);  // Nilai water level (ADC 0-4095)
            $table->string('status')->default('AMAN');   // AMAN, WASPADA, BAHAYA
            $table->string('trigger_reason')->nullable()->default('NONE');

            // Nilai opsional
            $table->integer('rssi')->nullable();
            $table->integer('uptime_s')->nullable();
            $table->float('temperature_c')->nullable();
            $table->float('humidity_pct')->nullable();
            $table->boolean('flame_detected')->default(false);
            $table->integer('gas_raw')->nullable();

            $table->timestamp('received_at')->useCurrent();
            $table->timestamps();

            // Indeks untuk query cepat kartu live & grafik
            $table->index(['device_id', 'received_at']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('sensor_readings');
        Schema::dropIfExists('devices');
    }
};
