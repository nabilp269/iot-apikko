# Integrasi Perangkat IoT Ruang Server ↔ Agora

**Status: FINAL v1.0 — disepakati dengan Tim IoT (19 November 2026). Endpoint di sisi Agora sudah dibuat dan siap diuji coba.**

Dokumen ini untuk tim pembuat perangkat IoT ruang server (ESP32 + MQ-2, flame sensor, water level sensor) dan AI agent mereka. Isinya kesepakatan cara perangkat mengirim data ke Agora. Jawaban Tim IoT atas pertanyaan v0.1 tercatat di bagian akhir dokumen.

### Perubahan dari v0.2
- Batas status di bagian 5 sekarang memakai **batas firmware** dari Tim IoT, dan sudah diterapkan di Agora.
- Body menerima `device_id` serta field opsional **`rssi`** dan **`uptime_s`** (usulan Tim IoT). Keduanya ditampilkan di dashboard.
- Endpoint, token, validasi, dan rate limit di bagian 3 dan 6 **sudah diimplementasikan**.

---

## 1. Konteks

- **Agora** adalah aplikasi web forum internal (Laravel), di `https://agora.apikkedu.com`. Dashboard-nya sudah punya bagian **"Monitoring Ruang Server"** yang menampilkan gas, api, dan air, lengkap dengan status Aman / Waspada / Bahaya dan status perangkat Online/Offline. Saat ini bagian itu masih memakai **data dummy**.
- **Perangkat:** ESP32 dengan sensor analog. Nilai yang terbaca saat pengujian:

  | Sensor | Pin | Rentang | Arti nilai | Contoh nilai |
  |---|---|---|---|---|
  | Gas MQ-2 | GPIO35 | 0–4095 | makin tinggi, makin banyak gas | udara bersih ±560, gas korek ±1750 |
  | Flame | GPIO34 | 0–4095 | **terbalik**: makin rendah, makin dekat api | tanpa api 4095 |
  | Water level | GPIO32 | 0–4095 | makin tinggi, makin banyak air | kering ±0 |

- Agora **tidak** memanggil perangkat. Yang disepakati, **perangkat mengirim data ke Agora (push)**.

## 2. Kenapa push (perangkat → Agora)

- ESP32 tidak perlu menjalankan web server, tidak perlu IP tetap, dan tidak perlu bisa diakses dari luar.
- Cukup memakai `HTTPClient` bawaan core ESP32 Arduino.
- Agora menyimpan pembacaan terakhir, jadi bisa mendeteksi **offline**: kalau tidak ada kiriman lebih dari 30 detik, perangkat dianggap offline.
- Ke depannya data yang sama bisa dipakai untuk riwayat dan notifikasi bahaya, tanpa perubahan di perangkat.

## 3. Spesifikasi

### Endpoint

```
POST https://agora.apikkedu.com/api/iot/server-room
```

### Header

| Header | Nilai |
|---|---|
| `Authorization` | `Bearer <DEVICE_TOKEN>` (token rahasia dari tim Agora, satu per perangkat) |
| `Content-Type` | `application/json` |
| `Accept` | `application/json` |

### Body (JSON)

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

| Field | Tipe | Wajib | Aturan |
|---|---|---|---|
| `gas` | integer | ya | 0–4095, nilai mentah `analogRead` GPIO35 |
| `flame` | integer | ya | 0–4095, nilai mentah `analogRead` GPIO34 |
| `water` | integer | ya | 0–4095, nilai mentah `analogRead` GPIO32 |
| `device_id` | string | tidak (disarankan) | harus sama dengan perangkat pemilik token, misalnya `"server-room-1"`. Kalau berbeda, respons `422` |
| `rssi` | integer | tidak | kekuatan sinyal WiFi dalam dBm, −127 sampai 0, misalnya `-65` (`WiFi.RSSI()`) |
| `uptime_s` | integer | tidak | detik sejak perangkat menyala, ≥ 0 (`millis() / 1000`) |

Catatan:
- Kirim **nilai mentah**, bukan status. Status (Aman/Waspada/Bahaya) dihitung oleh Agora dari batas yang sama dengan firmware (lihat bagian 5).
- Token-lah yang menentukan perangkat mana yang mengirim. `device_id` hanya dicek kecocokannya.
- **Tidak perlu timestamp.** Agora memakai waktu saat data diterima, karena jam ESP32 tanpa NTP tidak bisa diandalkan.

### Frekuensi
- Kirim setiap **5 detik**. Dashboard memperbarui tampilan juga setiap 5 detik.
- Agora menandai perangkat **offline** kalau tidak menerima data lebih dari **30 detik**.
- Batas di sisi Agora: maksimal **30 request per menit** per perangkat (token). Request ke-31 dalam satu menit mendapat `429`.

### Respons dari Agora

| Kode | Arti | Yang dilakukan perangkat |
|---|---|---|
| `204 No Content` | diterima | tidak ada |
| `401 Unauthorized` | token salah atau tidak ada | cek token. Jangan mengirim ulang terus-menerus |
| `422 Unprocessable Entity` | body tidak valid (field kurang, nilai di luar 0–4095, `device_id` tidak cocok). Body respons berisi `errors` per field | perbaiki firmware |
| `429 Too Many Requests` | terlalu sering mengirim | perlambat interval |
| `5xx` / timeout | gangguan di server | abaikan, coba lagi di siklus berikutnya. **Tidak perlu antrean atau buffer**, karena yang penting hanya data terbaru |

## 4. Yang perlu diperhatikan di firmware

1. **HTTPS.** `agora.apikkedu.com` berada di belakang Cloudflare dan hanya bisa diakses lewat HTTPS. Pakai `WiFiClientSecure`, sebaiknya dengan sertifikat root CA (`setCACert`). Hindari `setInsecure()`, karena token bisa disadap kalau koneksinya tidak diverifikasi.
2. **Token jangan di-hardcode di repo publik.** Simpan di file `secrets.h` yang di-*gitignore*, atau di NVS/Preferences. Kalau token bocor, tim Agora tinggal membuat token baru.
3. **Jangan memblokir loop utama.** Tampilan TFT dan alarm lokal (LED atau buzzer) harus **tetap jalan** walaupun WiFi putus atau Agora tidak bisa dihubungi. Pakai timeout HTTP yang pendek (sekitar 3–5 detik) dan jadwal berbasis `millis()`, bukan `delay()` yang panjang.
4. **Reconnect WiFi otomatis.** Indikator "NO WIFI" di layar sudah ada. Tambahkan percobaan sambung ulang berkala.
5. **Batas lokal tetap dipakai.** Alarm di perangkat tidak boleh bergantung pada Agora.

### Contoh (Arduino / ESP32, garis besar)

```cpp
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include "secrets.h"   // WIFI_SSID, WIFI_PASS, DEVICE_TOKEN, ROOT_CA

const char* AGORA_URL = "https://agora.apikkedu.com/api/iot/server-room";
const unsigned long SEND_EVERY_MS = 5000;
unsigned long lastSend = 0;

void sendReading(int gas, int flame, int water) {
  if (WiFi.status() != WL_CONNECTED) return;      // the display and alarm keep working

  WiFiClientSecure client;
  client.setCACert(ROOT_CA);
  HTTPClient http;
  http.setTimeout(4000);
  if (!http.begin(client, AGORA_URL)) return;

  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");
  http.addHeader("Authorization", String("Bearer ") + DEVICE_TOKEN);

  String body = String("{\"device_id\":\"server-room-1\",\"gas\":") + gas + ",\"flame\":" + flame +
                ",\"water\":" + water + ",\"rssi\":" + WiFi.RSSI() + ",\"uptime_s\":" + (millis() / 1000) + "}";
  int code = http.POST(body);                     // 204 = ok
  // 401/422: wrong token or body (log it); 429/5xx/timeout: just try again next cycle
  http.end();
}

void loop() {
  int gas = analogRead(35), flame = analogRead(34), water = analogRead(32);
  // ... update TFT + local alarm as today ...
  if (millis() - lastSend >= SEND_EVERY_MS) {
    lastSend = millis();
    sendReading(gas, flame, water);
  }
}
```

## 5. Batas status (harus sama di firmware dan Agora)

Batas firmware dari Tim IoT, **sudah diterapkan di Agora** (`config/server_room.php`):

| Sensor | Aman | Waspada | Bahaya |
|---|---|---|---|
| Gas (naik = bahaya) | `< 600` | `≥ 600` | `≥ 1200` |
| Flame (terbalik) | `≥ 2700` | `< 2700` | `< 2000` |
| Water (naik = bahaya) | `< 20` | – (tidak ada) | `≥ 20` |

Tepat di angka batas, Agora membandingkan seperti ini: gas dan air memakai `≥`, flame memakai `<` (ketat). Jadi flame **2700 = Aman**, **2699 = Waspada**, **2000 = Waspada**, **1999 = Bahaya**.

> **Mohon dicek:** jawaban v0.2 menyebut "Aman `> 2700`" dan "Waspada `< 2700`", sehingga nilai tepat 2700 tidak tercakup. Kalau `if` di firmware berbeda dari aturan di atas, kirimkan potongan kodenya supaya Agora bisa disamakan.

## 6. Yang sudah dibuat di Agora

- Endpoint `POST /api/iot/server-room` dengan autentikasi token per perangkat, validasi, dan rate limit 30 per menit.
- Penyimpanan pembacaan terakhir per perangkat, termasuk `rssi` dan `uptime_s`. Riwayat bisa menyusul.
- Dashboard membaca data asli (`SERVER_ROOM_DRIVER=device`), menggantikan data dummy. Perangkat dianggap offline kalau tidak mengirim selama lebih dari 30 detik.
- Token perangkat dibuat dengan `php artisan iot:device-token server-room-1 --name="Ruang Server 1"`. Token hanya ditampilkan **sekali**, lalu diserahkan ke Tim IoT lewat jalur aman, **tidak** lewat chat grup. Menjalankan perintah yang sama lagi akan membuat token baru, dan token lama langsung tidak berlaku.

## 7. Uji coba bersama

1. Tim Agora men-deploy dan membuat token untuk `server-room-1`.
2. Tim IoT memasang token di `secrets.h`, lalu mengirim satu request percobaan. Contoh dengan curl dari laptop:
   ```bash
   curl -i -X POST https://agora.apikkedu.com/api/iot/server-room \
     -H "Authorization: Bearer <DEVICE_TOKEN>" -H "Content-Type: application/json" -H "Accept: application/json" \
     -d '{"device_id":"server-room-1","gas":567,"flame":4095,"water":0}'
   ```
   Respons yang diharapkan: `HTTP/2 204`.
3. Pastikan dashboard Agora menampilkan nilai yang sama dengan layar TFT, termasuk saat gas korek didekatkan (status harus **Bahaya** di keduanya).

---

## Pertanyaan v0.1 dan jawaban Tim IoT

1. **Setuju dengan cara push** (perangkat mengirim ke Agora)? Kalau tidak, apa alternatifnya: Agora yang mengambil data dari perangkat (pull), MQTT, atau yang lain?
   - **Jawaban:** **Sangat SETUJU.** Metode PUSH via HTTP POST dari ESP32 ke endpoint Agora adalah yang paling tepat karena ESP32 berada di dalam jaringan lokal (NAT/WiFi) tanpa memerlukan IP publik statis atau konfigurasi port forwarding.

2. **Batas di firmware** untuk gas, flame, dan water: nilai berapa dianggap waspada dan bahaya?
   - **Jawaban:** Berdasarkan pengujian dan kalibrasi riil hardware ESP32 kami, mohon gunakan ambang batas (ADC 0–4095) berikut agar status di dashboard Agora sinkron 100% dengan layar TFT perangkat:
     - **Gas MQ-2 (GPIO35):**
       - Aman: `< 600` (kondisi udara bersih normal ±70–560)
       - Waspada: `≥ 600`
       - Bahaya: `≥ 1200`
     - **Flame Sensor (GPIO34):**
       - Aman: `> 2700` (kondisi tanpa api normal ±2928–4095)
       - Waspada: `< 2700`
       - Bahaya: `< 2000` *(catatan: pembacaan nilai Flame terbalik, makin rendah = api makin dekat/besar)*
     - **Water Level Sensor (GPIO32):**
       - Aman: `< 20` (kering normal ±0)
       - Bahaya: `≥ 20` *(sensor sangat sensitif, jika terkena tetesan atau genangan air nilai langsung naik di atas 20 hingga ratusan)*

3. Apakah **5 detik** sebagai interval kirim sudah cocok, atau lebih baik lebih jarang?
   - **Jawaban:** **Sangat cocok (5 detik / 5000 ms).** Interval ini tidak membebani loop mikrokontroler ESP32, berada jauh di bawah batas rate limit 30 req/menit (rata-rata 12 req/menit), dan cukup responsif untuk mendeteksi kondisi bahaya di ruang server.

4. Apakah perangkat **akan terhubung ke WiFi yang punya akses internet**, sehingga bisa menghubungi `agora.apikkedu.com`? Kalau hanya ada jaringan lokal kantor, perlu dibahas alamat alternatifnya.
   - **Jawaban:** **Ya, terhubung ke WiFi dengan akses internet.** Firmware ESP32 siap melakukan handshake HTTPS ke `https://agora.apikkedu.com` menggunakan `WiFiClientSecure`.

5. Apakah nanti ada **lebih dari satu perangkat** atau ruangan? Kalau ya, `device_id` dijadikan wajib.
   - **Jawaban:** **Ya, kami sepakat menyertakan field `device_id` di body JSON.** ESP32 kami akan mengirimkan identitas unik (misal: `"device_id": "server-room-1"`). Ini akan memudahkan jika nanti ada penambahan ruang server 2 atau unit rack server lain.

6. Ada data lain yang ingin dikirim juga, misalnya kekuatan sinyal WiFi (RSSI), uptime, atau versi firmware?
   - **Jawaban:** Kami mengusulkan menambahkan 2 field opsional untuk monitoring kesehatan perangkat:
     - `rssi` (integer, indikator kekuatan sinyal WiFi dalam satuan dBm, misal `-65`)
     - `uptime_s` (integer, durasi perangkat aktif dalam satuan detik)
     *(Catatan: Jika dari sisi tim Agora ingin tetap ringkas hanya menerima `gas`, `flame`, dan `water`, firmware kami juga siap menyesuaikan).*

7. Siapa kontak di tim IoT untuk serah terima token dan pengujian bersama?
   - **Jawaban:** Tim pengembang IoT kami siap berkoordinasi langsung untuk serah terima `DEVICE_TOKEN` dan melakukan uji koneksi (*handshake test*) begitu endpoint `POST /api/iot/server-room` di Agora siap diuji coba.
