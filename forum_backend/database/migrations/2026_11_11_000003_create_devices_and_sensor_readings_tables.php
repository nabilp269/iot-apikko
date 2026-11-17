<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // 1. Tabel Perangkat IoT (PRD Bagian 26 & 28)
        Schema::create('devices', function (Blueprint $table) {
            $table->id();
            $table->string('device_id')->unique(); // contoh: 'esp32-srv-01'
            $table->string('name')->default('Ruang Server A');
            $table->string('location')->default('Gedung Server Utama');
            $table->enum('status', ['online', 'offline'])->default('offline');
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();
        });

        // 2. Tabel Telemetry Sensor (PostgreSQL)
        Schema::create('sensor_readings', function (Blueprint $table) {
            $table->id();
            $table->string('device_id');
            $table->float('temperature_c');
            $table->float('humidity_pct');
            $table->boolean('flame_detected')->default(false);
            $table->integer('gas_raw')->nullable();
            $table->string('status')->default('normal'); // normal, waspada, bahaya
            $table->timestamp('received_at')->useCurrent();
            $table->timestamps();

            // Indeks untuk query performa kartu live & grafik (PRD Bagian 26)
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
