/*
  ESP32 Smart Room Sensor
  - BLE Server: mengirim JSON dengan notify untuk Flutter
  - Wi-Fi API: mengirim data ke Laravel /api/sensor-readings

  Library Arduino IDE:
  - DHT sensor library by Adafruit
  - Adafruit Unified Sensor
  BLE, WiFi, HTTPClient sudah tersedia di ESP32 Arduino Core.
*/

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <DHT.h>

// =========================
// KONFIGURASI WIFI DAN API
// =========================
const char* WIFI_SSID = "NAMA_WIFI";
const char* WIFI_PASSWORD = "PASSWORD_WIFI";

// Ganti dengan IP komputer yang menjalankan Laravel.
// Contoh: http://192.168.1.10:8000/api/sensor-readings
const char* API_URL = "http://192.168.1.10:8000/api/sensor-readings";
const char* API_KEY = "monitoring-iot-dev-key";
const char* DEVICE_ID = "esp32-ruangan-01";

// Matikan dulu agar kegagalan POST Laravel tidak membuat API Flutter timeout.
const bool ENABLE_LARAVEL_API = false;

// =========================
// PIN SENSOR
// =========================
const int MQ2_PIN = 35;
const int FLAME_PIN = 34;
const int WATER_PIN = 32;
const int DHT_PIN = 27;
const int DHT_TYPE = DHT22;

const int FLAME_THRESHOLD = 2500;
const int WATER_THRESHOLD = 20;

DHT dht(DHT_PIN, DHT_TYPE);
WebServer server(80);
String latestPayload = "{\"status\":\"starting\"}";
String latestNotification = "";
float cachedTemperature = 0;
float cachedHumidity = 0;
unsigned long lastDhtRead = 0;

// =========================
// UUID BLE
// =========================
static const char* BLE_DEVICE_NAME = "ESP32_Smart_Dashboard";
static const char* BLE_SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static const char* BLE_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

BLECharacteristic* sensorCharacteristic = nullptr;
bool bleConnected = false;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    bleConnected = true;
    Serial.println("BLE Flutter terhubung");
  }

  void onDisconnect(BLEServer* server) override {
    bleConnected = false;
    Serial.println("BLE Flutter terputus");
    delay(100);
    server->getAdvertising()->start();
  }
};

void startBleServer() {
  BLEDevice::init(BLE_DEVICE_NAME);

  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* service = server->createService(BLE_SERVICE_UUID);
  sensorCharacteristic = service->createCharacteristic(
      BLE_CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);

  sensorCharacteristic->addDescriptor(new BLE2902());
  sensorCharacteristic->setValue("{\"status\":\"ready\"}");
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE Server aktif: ESP32_Smart_Dashboard");
}

void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Menghubungkan Wi-Fi");

  int attempt = 0;
  while (WiFi.status() != WL_CONNECTED && attempt < 30) {
    delay(500);
    Serial.print('.');
    attempt++;
  }

  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Wi-Fi aktif. IP ESP32: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("Wi-Fi gagal terhubung");
  }
}

String buildSensorJson(float temperature, float humidity, int gas, int flameRaw, int water) {
  const bool flame = flameRaw < FLAME_THRESHOLD;
  String json = "{";
  json += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
  json += "\"temperature_c\":" + String(temperature, 1) + ",";
  json += "\"humidity_pct\":" + String(humidity, 1) + ",";
  json += "\"gas_raw\":" + String(gas) + ",";
  json += "\"flame_value\":" + String(flameRaw) + ",";
  json += "\"flame_detected\":" + String(flame ? "true" : "false") + ",";
  json += "\"water_value\":" + String(water) + ",";
  json += "\"water_raw\":" + String(water);
  json += "}";
  return json;
}

void sendToBluetooth(const String& payload) {
  if (!bleConnected || sensorCharacteristic == nullptr) return;
  sensorCharacteristic->setValue(payload.c_str());
  sensorCharacteristic->notify();
}

void sendToLaravel(const String& payload) {
  if (WiFi.status() != WL_CONNECTED) return;

  WiFiClient client;
  HTTPClient http;
  if (!http.begin(client, API_URL)) return;

  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");
  http.addHeader("X-API-Key", API_KEY);

  int statusCode = http.POST(payload);
  Serial.print("API status: ");
  Serial.println(statusCode);
  if (statusCode > 0) Serial.println(http.getString());
  http.end();
}

void handleSensorApi() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Accept");
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", latestPayload);
}

void handleSensorOptions() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Accept");
  server.send(204, "text/plain", "");
}

void handleNotificationApi() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Accept");

  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"body kosong\"}");
    return;
  }

  latestNotification = server.arg("plain");
  Serial.print("Notifikasi Flutter: ");
  Serial.println(latestNotification);

  // Hubungkan latestNotification ke fungsi TFT jika ingin menampilkannya di layar.
  server.send(200, "application/json", "{\"ok\":true}");
}

void handleNotificationOptions() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, Accept");
  server.send(204, "text/plain", "");
}

void setup() {
  Serial.begin(115200);
  delay(500);
  dht.begin();
  pinMode(MQ2_PIN, INPUT);
  pinMode(FLAME_PIN, INPUT);
  pinMode(WATER_PIN, INPUT);

  connectWifi();
  startBleServer();

  server.on("/sensor", HTTP_GET, handleSensorApi);
  server.on("/sensor", HTTP_OPTIONS, handleSensorOptions);
  server.on("/notification", HTTP_POST, handleNotificationApi);
  server.on("/notification", HTTP_OPTIONS, handleNotificationOptions);
  server.begin();
  Serial.print("ESP32 API: http://");
  Serial.print(WiFi.localIP());
  Serial.println("/sensor");
}

void loop() {
  server.handleClient();

  const int gas = analogRead(MQ2_PIN);
  const int flameRaw = analogRead(FLAME_PIN);
  const int water = analogRead(WATER_PIN);

  // DHT22 tidak boleh dibaca setiap loop. Simpan nilai selama 2 detik
  // agar endpoint API tetap cepat merespons sensor analog.
  if (millis() - lastDhtRead >= 2000 || lastDhtRead == 0) {
    const float temperature = dht.readTemperature();
    const float humidity = dht.readHumidity();
    if (!isnan(temperature)) cachedTemperature = temperature;
    if (!isnan(humidity)) cachedHumidity = humidity;
    lastDhtRead = millis();
  }

  const String payload = buildSensorJson(
      cachedTemperature, cachedHumidity, gas, flameRaw, water);
  latestPayload = payload;
  Serial.println(payload);

  sendToBluetooth(payload);
  if (ENABLE_LARAVEL_API) sendToLaravel(payload);
  delay(50);
}
