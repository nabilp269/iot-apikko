// =====================================================================
// SMART MOTOR DASHBOARD - ESP32 (MQTT REAL-TIME EDITION - 5 DETIK)
// Hardware: MQ-2 (P35), Flame Analog (P34), Water Level (P32),
//           TFT ILI9341 Fast-SPI, LED Traffic Light, Buzzer, MQTT
// =====================================================================

#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ILI9341.h> 
#include <WiFi.h>
#include <PubSubClient.h>

// ==========================================
// 1. KREDENSIAL WIFI & BROKER MQTT MOSQUITTO
// ==========================================
const char* ssid        = "s";
const char* password    = "28092007";

const char* mqtt_server       = "192.168.101.142"; // Ganti dengan IP laptop Anda jika berubah
const int   mqtt_port         = 1883;
const char* mqtt_topic_sensor = "smart_motor/sensor"; // Stream sensor ke Flutter
const char* mqtt_topic_alert  = "smart_motor/alert";  // Khusus trigger notifikasi bahaya

WiFiClient espClient;
PubSubClient mqttClient(espClient);

// ==========================================
// 2. KONFIGURASI PIN HARDWARE ASLI
// ==========================================
#define TFT_CS     23 
#define TFT_RST    22 
#define TFT_DC     21 
#define TFT_MOSI   19 
#define TFT_SCLK   18 

Adafruit_ILI9341 tft = Adafruit_ILI9341(&SPI, TFT_DC, TFT_CS, TFT_RST);

const int mq2Pin        = 35; 
const int flamePin      = 34; 
const int waterLevelPin = 32; 

const int ledMerah  = 5; 
const int ledKuning = 4; 
const int ledHijau  = 2; 
const int buzzerPin = 25; 

// ==========================================
// 3. AMBANG BATAS SENSOR (THRESHOLD ASLI)
// ==========================================
const int THRESHOLD_MQ2_SEDANG = 600;   // Masuk WASPADA (Lampu Kuning)
const int THRESHOLD_MQ2_TINGGI = 1200;  // Masuk BAHAYA! (Lampu Merah + Alert)
const int THRESHOLD_FLAME      = 2500;  // Masuk BAHAYA! jika nilai turun < 2500
const int THRESHOLD_WATER      = 20;    // Masuk BAHAYA! jika nilai naik >= 20

// Cache Tampilan TFT
int lastGasValue       = -1;
int lastFlameValue     = -1;
int lastWaterValue     = -1;
String lastGasStat     = "";
bool lastNetStatus     = false;

// Pelacak Interval Waktu Pengiriman MQTT
unsigned long lastMqttPublishTime   = 0;
unsigned long lastMqttReconnectTime = 0;
unsigned long lastWifiReconnectTime = 0;
const unsigned long MQTT_HEARTBEAT_MS = 5000; // Kirim rutin setiap 5 DETIK (5000ms)

int lastMqttMq2      = -1;
int lastMqttFlame    = -1;
int lastMqttWater    = -1;
String lastMqttStatus = "";
bool wasInDanger      = false;

// Variabel Global Sensor
int currentMq2Val   = 0;
int currentFlameVal = 0;
int currentWaterVal = 0;
String currentStatus = "AMAN";

// ==========================================
// 4. HELPER JSON & INDIKATOR TFT
// ==========================================
String buildSensorJson(String triggerReason = "NONE") {
  String json = "{";
  json += "\"device\":\"SMART_MOTOR_DASHBOARD\",";
  json += "\"mq2_value\":" + String(currentMq2Val) + ",";
  json += "\"flame_value\":" + String(currentFlameVal) + ",";
  json += "\"water_value\":" + String(currentWaterVal) + ",";
  json += "\"status\":\"" + currentStatus + "\",";
  json += "\"trigger_reason\":\"" + triggerReason + "\"";
  json += "}";
  return json;
}

void updateNetworkIndicator(bool wifiOk, bool mqttOk) {
  tft.fillRect(215, 8, 100, 22, ILI9341_BLACK);
  tft.drawRect(215, 8, 100, 22, ILI9341_DARKGREY);
  
  tft.setTextSize(1);
  tft.setCursor(222, 15);
  if (wifiOk && mqttOk) {
    tft.setTextColor(ILI9341_GREEN);
    tft.print("MQTT: ONLINE");
  } else if (wifiOk) {
    tft.setTextColor(ILI9341_YELLOW);
    tft.print("WIFI OK/NO MQTT");
  } else {
    tft.setTextColor(ILI9341_RED);
    tft.print("NO WIFI");
  }
}

bool reconnectMQTT() {
  String clientId = "ESP32_SMART_MOTOR_" + String((uint32_t)ESP.getEfuseMac(), HEX);
  Serial.print("[MQTT] Menyambungkan ke Mosquitto (" + String(mqtt_server) + ")... ");
  
  if (mqttClient.connect(clientId.c_str())) {
    Serial.println("TERHUBUNG!");
    lastMqttStatus = ""; // Paksa kirim paket penuh begitu tersambung
    return true;
  } else {
    Serial.print("GAGAL, rc=");
    Serial.println(mqttClient.state());
    return false;
  }
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

  // Inisialisasi TFT ILI9341 Fast-SPI
  SPI.begin(TFT_SCLK, -1, TFT_MOSI, TFT_CS);
  tft.begin(40000000);
  tft.setRotation(1); 
  tft.fillScreen(ILI9341_BLACK);

  tft.drawRect(10, 10, 300, 220, ILI9341_CYAN);
  tft.setTextColor(ILI9341_WHITE);
  tft.setTextSize(2);
  tft.setCursor(35, 40);
  tft.println("MULTI-SENSOR MONITOR");
  
  tft.setCursor(95, 75);
  tft.setTextColor(ILI9341_YELLOW);
  tft.println("MQTT EDITION");

  // Inisialisasi WiFi
  tft.setTextSize(1);
  tft.setTextColor(ILI9341_CYAN);
  tft.setCursor(75, 120);
  tft.println("Menghubungkan ke WiFi...");

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  WiFi.setSleep(false); // PENTING: Mencegah WiFi sleep agar stabil

  int timeout = 0;
  while (WiFi.status() != WL_CONNECTED && timeout < 25) {
    delay(500);
    tft.print(".");
    timeout++;
  }

  // Konfigurasi MQTT Broker
  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setBufferSize(512);
  mqttClient.setKeepAlive(15);

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WIFI] Connected! IP ESP32: " + WiFi.localIP().toString());
    reconnectMQTT();
  }

  // Gambar Layout Dashboard Utama pada TFT
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

  bool netOk = (WiFi.status() == WL_CONNECTED && mqttClient.connected());
  updateNetworkIndicator(WiFi.status() == WL_CONNECTED, mqttClient.connected());
  lastNetStatus = netOk;
}

// ==========================================
// 6. LOOP UTAMA
// ==========================================
void loop() {
  unsigned long now = millis();

  // 1. Kelola Koneksi WiFi & MQTT Non-Blocking
  bool wifiConnected = (WiFi.status() == WL_CONNECTED);
  bool mqttConnected = false;

  if (!wifiConnected) {
    if (now - lastWifiReconnectTime >= 5000) {
      lastWifiReconnectTime = now;
      Serial.println("[WIFI] Terputus, menyambung ulang...");
      WiFi.disconnect();
      WiFi.reconnect();
    }
  } else {
    if (!mqttClient.connected()) {
      if (now - lastMqttReconnectTime >= 2000) {
        lastMqttReconnectTime = now;
        mqttConnected = reconnectMQTT();
      }
    } else {
      mqttClient.loop(); // Jaga heartbeat koneksi MQTT tetap hidup
      mqttConnected = true;
    }
  }

  bool currentNetStatus = (wifiConnected && mqttConnected);
  if (currentNetStatus != lastNetStatus) {
    updateNetworkIndicator(wifiConnected, mqttConnected);
    lastNetStatus = currentNetStatus;
  }

  // 2. Baca Sensor Analog & Rata-rata Air
  currentMq2Val   = analogRead(mq2Pin);
  currentFlameVal = analogRead(flamePin);

  long waterSum = 0;
  for (int i = 0; i < 5; i++) {
    waterSum += analogRead(waterLevelPin);
  }
  currentWaterVal = waterSum / 5;

  // 3. Update TFT MQ-2
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

  // 4. Update TFT Flame
  if (abs(currentFlameVal - lastFlameValue) > 10) {
    tft.fillRect(25, 106, 120, 34, ILI9341_BLACK);
    tft.setTextSize(1);
    tft.setCursor(25, 108);
    tft.setTextColor(currentFlameVal < THRESHOLD_FLAME ? ILI9341_RED : ILI9341_GREEN);
    tft.print(currentFlameVal < THRESHOLD_FLAME ? "API TERDETEKSI!" : "AMAN (Normal)");
    tft.setCursor(25, 124);
    tft.setTextColor(ILI9341_WHITE);
    tft.print("VAL: " + String(currentFlameVal));
    lastFlameValue = currentFlameVal;
  }

  // 5. Update TFT Water Level
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

  // 6. Evaluasi Status Kondisi Sistem
  String gasStat = "AMAN";
  uint16_t gasColor = ILI9341_GREEN;
  
  bool isGasDanger   = (currentMq2Val >= THRESHOLD_MQ2_TINGGI);
  bool isGasWarning  = (currentMq2Val >= THRESHOLD_MQ2_SEDANG && currentMq2Val < THRESHOLD_MQ2_TINGGI);
  bool isFlameDanger = (currentFlameVal < THRESHOLD_FLAME); 
  bool isWaterDanger = (currentWaterVal >= THRESHOLD_WATER); 

  bool isAnyDanger = (isGasDanger || isFlameDanger || isWaterDanger);

  String triggerReason = "NONE";
  if (isAnyDanger) {
    gasStat = "BAHAYA!";
    gasColor = ILI9341_RED;
    triggerReason = "";
    if (isGasDanger)   triggerReason += "GAS_TINGGI ";
    if (isFlameDanger) triggerReason += "API_TERDETEKSI ";
    if (isWaterDanger) triggerReason += "TERKENA_AIR ";
    triggerReason.trim();
  } else if (isGasWarning) {
    gasStat = "WASPADA";
    gasColor = ILI9341_YELLOW;
    triggerReason = "GAS_SEDANG";
  }
  
  currentStatus = gasStat;

  // 7. Update Status TFT & LED/Buzzer Seketika
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
  } else if (isGasWarning) {
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

  // ==============================================================
  // 8. KIRIM DATA KE MQTT BROKER MOSQUITTO (SETIAP 5 DETIK SEKALI)
  // ==============================================================
  if (mqttConnected) {
    bool isEmergency = (isAnyDanger && !wasInDanger); // Prioritas darurat saat bahaya baru terjadi

    // Kirim hanya jika sudah lewat 5 DETIK (5000ms), ATAU saat ada BAHAYA baru
    if (isEmergency || (now - lastMqttPublishTime >= MQTT_HEARTBEAT_MS)) {
      String payload = buildSensorJson(triggerReason);
      mqttClient.publish(mqtt_topic_sensor, payload.c_str());

      // Jika baru masuk kondisi BAHAYA, kirim juga alert khusus
      if (isAnyDanger && !wasInDanger) {
        mqttClient.publish(mqtt_topic_alert, payload.c_str());
        Serial.println("[MQTT ALERT SENT] " + payload);
      }

      lastMqttPublishTime = now;
      lastMqttMq2         = currentMq2Val;
      lastMqttFlame       = currentFlameVal;
      lastMqttWater       = currentWaterVal;
      lastMqttStatus      = currentStatus;
    }
  }

  wasInDanger = isAnyDanger;
  delay(15);
}
