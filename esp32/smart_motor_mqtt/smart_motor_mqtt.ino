// =============================================================================
// MONITORING RUANG SERVER - ESP32 ↔ AGORA (SESUAI DOKUMEN IOT-SERVER-ROOM-API.MD V1.0)
// Hardware: MQ-2 Gas (GPIO35), Flame Analog (GPIO34), Water Level (GPIO32),
//           TFT ILI9341 Fast-SPI, LED Indikator (5, 4, 2), Buzzer (25)
// =============================================================================

#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h> 
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

// Kredensial, Token & Root CA dimuat dari file terpisah (secrets.h)
#include "secrets.h"

// ==========================================
// 1. PIN HARDWARE ASLI
// ==========================================
#define TFT_CS     23 
#define TFT_RST    22 
#define TFT_DC     21 
#define TFT_MOSI   19 
#define TFT_SCLK   18 

Adafruit_ILI9341 tft = Adafruit_ILI9341(&SPI, TFT_DC, TFT_CS, TFT_RST);

const int mq2Pin        = 35; // Sensor Gas MQ-2
const int flamePin      = 34; // Sensor Api (Flame Analog)
const int waterLevelPin = 32; // Sensor Ketinggian Air

const int ledMerah  = 5; 
const int ledKuning = 4; 
const int ledHijau  = 2; 
const int buzzerPin = 25; 

// ==========================================
// 2. AMBANG BATAS SENSOR (KALIBRASI RIIL)
// Sesuai Bagian 5 pada iot-server-room-api.md v1.0
// ==========================================
const int THRESHOLD_MQ2_SEDANG = 600;   // Waspada Gas (>= 600)
const int THRESHOLD_MQ2_TINGGI = 1200;  // Bahaya Gas (>= 1200)
const int THRESHOLD_FLAME_WARN = 2700;  // Waspada Api (< 2700)
const int THRESHOLD_FLAME_DANG = 2000;  // Bahaya Api (< 2000, nilai terbalik)
const int THRESHOLD_WATER      = 20;    // Bahaya Air (>= 20, tergenang air)

// Cache Tampilan TFT
int lastGasValue       = -1;
int lastFlameValue     = -1;
int lastWaterValue     = -1;
String lastGasStat     = "";
bool lastWifiStatus    = false;

// Pelacak Interval Waktu Pengiriman (Non-Blocking)
unsigned long lastSendTime          = 0;
unsigned long lastWifiReconnectTime = 0;
const unsigned long SEND_INTERVAL_MS = 5000; // Kirim rutin setiap 5 Detik

// Proteksi agar tidak membombardir server saat otentikasi gagal (401)
unsigned long authErrorBackoffUntil = 0;
const unsigned long AUTH_BACKOFF_MS = 60000; // Jeda 60 detik jika dapat kode 401

// Variabel Global Sensor
int currentMq2Val   = 0;
int currentFlameVal = 0;
int currentWaterVal = 0;
String currentStatus = "AMAN";

// ==========================================
// 3. INDIKATOR JARINGAN PADA TFT
// ==========================================
void updateNetworkIndicator(bool wifiOk) {
  tft.fillRect(215, 8, 100, 22, ILI9341_BLACK);
  tft.drawRect(215, 8, 100, 22, ILI9341_DARKGREY);
  
  tft.setTextSize(1);
  tft.setCursor(222, 15);
  if (wifiOk) {
    tft.setTextColor(ILI9341_GREEN);
    tft.print("WIFI: ONLINE");
  } else {
    tft.setTextColor(ILI9341_RED);
    tft.print("NO WIFI");
  }
}

// ==========================================
// 4. PENGIRIMAN DATA KE AGORA (HTTPS POST DENGAN ROOT CA)
// Sesuai Bagian 3 & 4 pada iot-server-room-api.md v1.0
// ==========================================
void sendReadingToAgora(int gas, int flame, int water) {
  if (WiFi.status() != WL_CONNECTED) {
    return;
  }

  // Jika token salah (401), jeda sementara agar tidak membanjiri server
  if (millis() < authErrorBackoffUntil) {
    Serial.println("[AGORA HTTP] Menunggu jeda otentikasi 401 (cek DEVICE_TOKEN di secrets.h)...");
    return;
  }

  HTTPClient http;
  http.setTimeout(4000); // Timeout 4 detik agar loop TFT & alarm tidak terblokir

  bool isHttps = String(AGORA_URL).startsWith("https://");
  WiFiClient plainClient;
  WiFiClientSecure secClient;

  if (isHttps) {
    // Mode Cloud (HTTPS): Pasang sertifikat Root CA resmi
    secClient.setCACert(ROOT_CA);
    if (!http.begin(secClient, AGORA_URL)) {
      Serial.println("[AGORA TLS] Gagal menginisialisasi koneksi HTTPS");
      return;
    }
  } else {
    // Mode Lokal (HTTP): Menggunakan koneksi plain HTTP ke server lokal
    if (!http.begin(plainClient, AGORA_URL)) {
      Serial.println("[AGORA HTTP] Gagal menginisialisasi koneksi HTTP");
      return;
    }
  }

  // Header wajib sesuai spesifikasi dokumen
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");
  // Token TIDAK PERNAH dicetak ke Serial Monitor demi keamanan
  http.addHeader("Authorization", String("Bearer ") + DEVICE_TOKEN);

  // Body JSON sesuai spesifikasi v1.0:
  // { "device_id": "server-room-1", "gas": 567, "flame": 4095, "water": 0, "rssi": -65, "uptime_s": 120 }
  String body = "{";
  body += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
  body += "\"gas\":" + String(gas) + ",";
  body += "\"flame\":" + String(flame) + ",";
  body += "\"water\":" + String(water) + ",";
  body += "\"rssi\":" + String(WiFi.RSSI()) + ",";
  body += "\"uptime_s\":" + String(millis() / 1000);
  body += "}";

  int httpCode = http.POST(body);

  // Logging Serial sesuai kode respons HTTP (tanpa mencetak token)
  if (httpCode == 204 || httpCode == 200) {
    Serial.printf("[AGORA HTTP %d] Sukses: Data telemetry berhasil diterima Agora.\n", httpCode);
  } else if (httpCode == 401) {
    Serial.println("[AGORA HTTP 401] Unauthorized: Token salah atau belum berawalan 'iot_'.");
    Serial.println("[AGORA HTTP 401] Menjeda pengiriman selama 60 detik. Periksa DEVICE_TOKEN di secrets.h!");
    authErrorBackoffUntil = millis() + AUTH_BACKOFF_MS;
  } else if (httpCode == 422) {
    String respBody = http.getString();
    Serial.printf("[AGORA HTTP 422] Validasi gagal! Body respons server: %s\n", respBody.c_str());
  } else if (httpCode == 429) {
    Serial.println("[AGORA HTTP 429] Too Many Requests: Terlalu sering mengirim. Menjaga interval 5 detik.");
  } else if (httpCode < 0) {
    Serial.printf("[AGORA TLS/NET ERROR %d] Gagal koneksi/TLS: %s\n", httpCode, http.errorToString(httpCode).c_str());
  } else {
    Serial.printf("[AGORA HTTP %d] Respons server: %s\n", httpCode, http.getString().c_str());
  }

  http.end();
}

// ==========================================
// 5. SETUP
// ==========================================
void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(ledMerah, OUTPUT);
  pinMode(ledKuning, OUTPUT);
  pinMode(ledHijau, OUTPUT);
  pinMode(buzzerPin, OUTPUT); 
  pinMode(waterLevelPin, INPUT_PULLDOWN);

  digitalWrite(ledMerah, LOW);
  digitalWrite(ledKuning, LOW);
  digitalWrite(ledHijau, LOW);
  digitalWrite(buzzerPin, LOW);

  // Inisialisasi Layar TFT Fast-SPI
  SPI.begin(TFT_SCLK, -1, TFT_MOSI, TFT_CS);
  tft.begin(40000000);
  tft.setRotation(1); 
  tft.fillScreen(ILI9341_BLACK);

  tft.drawRect(10, 10, 300, 220, ILI9341_CYAN);
  tft.setTextColor(ILI9341_WHITE);
  tft.setTextSize(2);
  tft.setCursor(35, 40);
  tft.println("MULTI-SENSOR MONITOR");
  
  tft.setCursor(65, 75);
  tft.setTextColor(ILI9341_YELLOW);
  tft.println("AGORA SERVER ROOM");

  // Inisialisasi WiFi
  tft.setTextSize(1);
  tft.setTextColor(ILI9341_CYAN);
  tft.setCursor(75, 120);
  tft.println("Menghubungkan ke WiFi...");

  Serial.println("\n[SYSTEM] Memulai ESP32 Server Room Monitor...");
  Serial.printf("[WIFI] Menghubungkan ke SSID: %s\n", WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  WiFi.setSleep(false); // Cegah sleep agar latency rendah

  int timeout = 0;
  while (WiFi.status() != WL_CONNECTED && timeout < 25) {
    delay(500);
    tft.print(".");
    Serial.print(".");
    timeout++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n[WIFI] Tersambung! IP ESP32: %s, RSSI: %d dBm\n", 
                  WiFi.localIP().toString().c_str(), WiFi.RSSI());
  } else {
    Serial.println("\n[WIFI] Belum tersambung, akan terus mencoba di background...");
  }

  // Gambar Layout Dashboard TFT
  tft.fillScreen(ILI9341_BLACK);

  tft.drawRect(15, 10, 290, 70, ILI9341_DARKGREY);
  tft.setTextColor(ILI9341_YELLOW);
  tft.setTextSize(1);
  tft.setCursor(25, 15);
  tft.println("MQ-2 GAS (P35)");

  tft.drawRect(15, 85, 140, 60, ILI9341_DARKGREY);
  tft.setCursor(25, 92);
  tft.setTextColor(ILI9341_YELLOW);
  tft.println("FLAME (P34)");

  tft.drawRect(165, 85, 140, 60, ILI9341_DARKGREY);
  tft.setCursor(175, 92);
  tft.setTextColor(ILI9341_YELLOW);
  tft.println("WATER LVL (P32)");

  tft.drawRect(15, 150, 290, 75, ILI9341_DARKGREY);
  tft.setCursor(25, 160);
  tft.setTextColor(ILI9341_YELLOW);
  tft.println("STATUS KONDISI SISTEM:");

  updateNetworkIndicator(WiFi.status() == WL_CONNECTED);
  lastWifiStatus = (WiFi.status() == WL_CONNECTED);
}

// ==========================================
// 6. LOOP UTAMA (NON-BLOCKING)
// ==========================================
void loop() {
  unsigned long now = millis();

  // 1. Reconnect WiFi Non-Blocking
  bool wifiConnected = (WiFi.status() == WL_CONNECTED);
  if (!wifiConnected) {
    if (now - lastWifiReconnectTime >= 5000) {
      lastWifiReconnectTime = now;
      Serial.println("[WIFI] Koneksi terputus, mencoba menyambung ulang...");
      WiFi.disconnect();
      WiFi.reconnect();
    }
  }

  if (wifiConnected != lastWifiStatus) {
    updateNetworkIndicator(wifiConnected);
    if (wifiConnected) {
      Serial.printf("[WIFI] Tersambung kembali! IP ESP32: %s, RSSI: %d dBm\n", 
                    WiFi.localIP().toString().c_str(), WiFi.RSSI());
    }
    lastWifiStatus = wifiConnected;
  }

  // 2. Baca Sensor Analog & Rata-rata Water Level
  currentMq2Val   = analogRead(mq2Pin);
  currentFlameVal = analogRead(flamePin);

  long waterSum = 0;
  for (int i = 0; i < 5; i++) {
    waterSum += analogRead(waterLevelPin);
  }
  currentWaterVal = waterSum / 5;

  // 3. Update Visual TFT: Gas MQ-2
  if (abs(currentMq2Val - lastGasValue) > 10) {
    tft.fillRect(25, 30, 150, 20, ILI9341_BLACK);
    tft.setTextSize(2);
    tft.setCursor(25, 30);
    tft.setTextColor(ILI9341_WHITE);
    tft.print("VAL: ");
    tft.print(currentMq2Val);

    int barWidth = map(currentMq2Val, 0, 4095, 0, 100);
    barWidth = constrain(barWidth, 0, 100);
    tft.fillRect(185, 30, 100, 16, ILI9341_BLACK); 
    tft.drawRect(184, 29, 102, 18, ILI9341_DARKGREY);
    
    uint16_t barColor = ILI9341_GREEN;
    if (currentMq2Val >= THRESHOLD_MQ2_TINGGI) barColor = ILI9341_RED;
    else if (currentMq2Val >= THRESHOLD_MQ2_SEDANG) barColor = ILI9341_YELLOW;
    
    tft.fillRect(185, 30, barWidth, 16, barColor); 
    lastGasValue = currentMq2Val;
  }

  // 4. Update Visual TFT: Flame (Api)
  if (abs(currentFlameVal - lastFlameValue) > 10) {
    tft.fillRect(25, 106, 120, 34, ILI9341_BLACK);
    tft.setTextSize(1);
    tft.setCursor(25, 108);
    tft.setTextColor(currentFlameVal < THRESHOLD_FLAME_DANG ? ILI9341_RED : (currentFlameVal < THRESHOLD_FLAME_WARN ? ILI9341_YELLOW : ILI9341_GREEN));
    tft.print(currentFlameVal < THRESHOLD_FLAME_DANG ? "API BAHAYA!" : (currentFlameVal < THRESHOLD_FLAME_WARN ? "WASPADA API" : "AMAN (Normal)"));
    tft.setCursor(25, 124);
    tft.setTextColor(ILI9341_WHITE);
    tft.print("VAL: " + String(currentFlameVal));
    lastFlameValue = currentFlameVal;
  }

  // 5. Update Visual TFT: Water Level
  if (abs(currentWaterVal - lastWaterValue) > 2) {
    tft.fillRect(175, 106, 120, 34, ILI9341_BLACK);
    tft.setTextSize(1);
    tft.setCursor(175, 108);
    tft.setTextColor(currentWaterVal >= THRESHOLD_WATER ? ILI9341_RED : ILI9341_GREEN);
    tft.print(currentWaterVal >= THRESHOLD_WATER ? "TERKENA AIR!" : "AMAN (Kering)");
    tft.setCursor(175, 124);
    tft.setTextColor(ILI9341_WHITE);
    tft.print("VAL: " + String(currentWaterVal));
    lastWaterValue = currentWaterVal;
  }

  // 6. Evaluasi Ambang Batas Sensor
  String gasStat = "AMAN";
  uint16_t gasColor = ILI9341_GREEN;
  
  bool isGasDanger    = (currentMq2Val >= THRESHOLD_MQ2_TINGGI);
  bool isGasWarning   = (currentMq2Val >= THRESHOLD_MQ2_SEDANG && currentMq2Val < THRESHOLD_MQ2_TINGGI);
  bool isFlameDanger  = (currentFlameVal < THRESHOLD_FLAME_DANG); 
  bool isFlameWarning = (currentFlameVal < THRESHOLD_FLAME_WARN && !isFlameDanger);
  bool isWaterDanger  = (currentWaterVal >= THRESHOLD_WATER); 

  bool isAnyDanger  = (isGasDanger || isFlameDanger || isWaterDanger);
  bool isAnyWarning = (isGasWarning || isFlameWarning);

  if (isAnyDanger) {
    gasStat = "BAHAYA!";
    gasColor = ILI9341_RED;
  } else if (isAnyWarning) {
    gasStat = "WASPADA";
    gasColor = ILI9341_YELLOW;
  }
  
  currentStatus = gasStat;

  // 7. Update Status TFT & Alarm Fisik Seketika
  if (gasStat != lastGasStat) {
    tft.fillRect(25, 180, 270, 38, ILI9341_BLACK);
    tft.setTextSize(2);
    tft.setCursor(30, 190);
    tft.setTextColor(gasColor);
    tft.print(gasStat);
    lastGasStat = gasStat;
  }

  if (isAnyDanger) {
    digitalWrite(ledMerah, HIGH);
    digitalWrite(ledKuning, LOW);
    digitalWrite(ledHijau, LOW);
    digitalWrite(buzzerPin, HIGH); 
  } else if (isAnyWarning) {
    digitalWrite(ledMerah, LOW);
    digitalWrite(ledKuning, HIGH);
    digitalWrite(ledHijau, LOW);
    digitalWrite(buzzerPin, LOW);
  } else {
    digitalWrite(ledMerah, LOW);
    digitalWrite(ledKuning, LOW);
    digitalWrite(ledHijau, HIGH);
    digitalWrite(buzzerPin, LOW);
  }

  // =========================================================================
  // 8. PENGIRIMAN DATA KE AGORA SETIAP 5 DETIK SEKALI (NON-BLOCKING)
  // =========================================================================
  if (now - lastSendTime >= SEND_INTERVAL_MS) {
    lastSendTime = now;
    sendReadingToAgora(currentMq2Val, currentFlameVal, currentWaterVal);
  }

  delay(15);
}
