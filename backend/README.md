# Backend IoT Smart Motor & Agora Server Room (Laravel)

Backend REST API untuk menerima, menyimpan, dan menyajikan data telemetry sensor dari mikrokontroler **ESP32** (Sensor Gas MQ-2, Flame/Api, dan Water Level) ke **Dashboard Web Agora** dan **Dashboard Flutter**.

---

## 🚀 Cara Menjalankan Backend

1. Buka terminal di folder backend:
   ```bash
   cd D:\dasboardflutter\iot-apikko\backend
   ```

2. Jalankan server Laravel:
   ```bash
   php artisan serve --host=0.0.0.0 --port=8000
   ```
   *Server akan berjalan di `http://127.0.0.1:8000` (atau IP lokal komputer Anda).*

---

## 📡 Daftar Endpoint API

### 1. Integrasi Agora Server Room (Sesuai `iot-server-room-api.md`)
- **URL:** `POST /api/iot/server-room`
- **Headers:**
  - `Authorization: Bearer apikko-secret-token-2026`
  - `Content-Type: application/json`
  - `Accept: application/json`
- **Body JSON:**
  ```json
  {
    "device_id": "server-room-1",
    "gas": 567,
    "flame": 4095,
    "water": 0,
    "rssi": -65,
    "uptime_s": 3600
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "Data sensor server room berhasil diterima",
    "data": { ... }
  }
  ```

---

### 2. Telemetry Umum (ESP32 / MQTT Bridge)
- **URL:** `POST /api/sensor-readings`
- **Body JSON:**
  ```json
  {
    "device_id": "ESP32_SMART_MOTOR_01",
    "mq2_value": 75,
    "flame_value": 2928,
    "water_value": 0,
    "status": "AMAN"
  }
  ```

---

### 3. Data Terkini (Untuk Flutter / Agora Dashboard)
- **URL:** `GET /api/sensor-latest`
- **Query Parameter (Opsional):** `?device_id=server-room-1`
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "data": {
      "id": 1,
      "device_id": "server-room-1",
      "mq2_value": 567,
      "flame_value": 4095,
      "water_value": 0,
      "status": "AMAN",
      "received_at": "2026-11-19T07:55:23.000000Z"
    }
  }
  ```

---

### 4. Riwayat Data Telemetry (Untuk Grafik / Chart)
- **URL:** `GET /api/sensor-history`
- **Query Parameters (Opsional):**
  - `limit=50` (maksimal 200)
  - `sensor=mq2` atau `sensor=flame` atau `sensor=water`
- **Response (200 OK):** Mengembalikan daftar titik data terurut waktu untuk rendering grafik.

---

### 5. Status Perangkat (Online / Offline)
- **URL:** `GET /api/devices`
- **Response (200 OK):** Otomatis mendeteksi perangkat offline jika tidak mengirim data > 30 detik.

---

### 6. Jadwal Notifikasi (Dari Menu Flutter Jadwal Kirim)
- **URL:** `GET /api/notification-schedules`
- **URL:** `POST /api/notification-schedules`

---

### 7. Simulasi Testing (Tanpa Hardware)
- **URL:** `POST /api/simulate`
- Langsung membuat data acak untuk menguji responsivitas dashboard.

---

## 🗄️ Database
Menggunakan **SQLite** (`database/database.sqlite`) yang sudah siap pakai tanpa instalasi server database eksternal. Jika ingin me-reset data:
```bash
php artisan migrate:fresh
```
