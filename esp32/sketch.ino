// ElectricalBenchAlert v1.1.0 - nodo de medicion y alerta (ESP32, Wokwi)
//
// Lee la senal acondicionada del chip grid-signal con el ADC1 a 10 kHz
// (tiempo simulado), la envia por MQTT en bloques de 1,250 muestras y
// muestra en la OLED y en los LEDs los eventos que publica el host MATLAB.
//
// Contrato MQTT (plan v1.1.0):
//   eba/sim01/config   ESP32 -> host, retenido: escala del ADC y del acondicionamiento
//   eba/sim01/samples  ESP32 -> host, QoS 0: seq, t0_sample, n, enc=u16le-b64, data
//   eba/sim01/events   host -> ESP32 y app, QoS 1: type, event_id, class, tiempos
//
// El tiempo de cada muestra es su indice / 10,000 (t0_sample = primer indice
// del bloque). No depende de la hora de llegada ni de la velocidad de Wokwi.

#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>
#include "mbedtls/base64.h"
#include "esp_timer.h"

// ---------------- Red y broker ----------------
// Por defecto: Wokwi-GUEST (sin clave) y el broker publico de pruebas, sin
// usuario. Para un broker privado (hito 5) copiar secrets.example.h a secrets.h
// (ignorado por git) y llenar los valores. En el plan gratuito de Wokwi los
// proyectos son publicos: un secrets.h con claves reales pegado ahi seria visible.
#if __has_include("secrets.h")
#include "secrets.h"
#endif
#ifndef SECRET_WIFI_SSID
#define SECRET_WIFI_SSID "Wokwi-GUEST"
#endif
#ifndef SECRET_WIFI_PASS
#define SECRET_WIFI_PASS ""
#endif
#ifndef SECRET_MQTT_HOST
#define SECRET_MQTT_HOST "broker.hivemq.com"
#endif
#ifndef SECRET_MQTT_PORT
#define SECRET_MQTT_PORT 1883
#endif
#ifndef SECRET_MQTT_USER
#define SECRET_MQTT_USER ""
#endif
#ifndef SECRET_MQTT_PASS
#define SECRET_MQTT_PASS ""
#endif
static const char *WIFI_SSID = SECRET_WIFI_SSID;
static const char *WIFI_PASS = SECRET_WIFI_PASS;
static const char *MQTT_HOST = SECRET_MQTT_HOST;
static const uint16_t MQTT_PORT = SECRET_MQTT_PORT;
static const char *MQTT_USER = SECRET_MQTT_USER;
static const char *MQTT_PASS = SECRET_MQTT_PASS;
static const char *T_CONFIG = "eba/sim01/config";
static const char *T_SAMPLES = "eba/sim01/samples";
static const char *T_EVENTS = "eba/sim01/events";
static const char *DEVICE_ID = "simulated-device";

// ---------------- Adquisicion ----------------
static const uint32_t FS_HZ = 10000;
static const int64_t TS_US = 100;
static const uint16_t BLOCK = 1250;   // un salto de 125 ms
static const uint8_t PIN_SIGNAL = 34; // ADC1_CH6 (ADC2 no se puede usar con WiFi)
static const uint8_t PIN_REF = 35;    // ADC1_CH7, referencia = V_OFFSET
static const uint8_t PIN_RUN = 25;    // flanco de subida = inicio de la secuencia
static const uint8_t PIN_END = 26;    // HIGH = el chip termino su tabla

// Acondicionamiento: debe coincidir con los attrs del chip grid-signal.
static const float V_OFFSET = 1.30f;     // V
static const float GAIN = 0.0029498525f; // 1/339, red de 120 V
static const float V_NOMINAL = 120.0f;   // V RMS

// ---------------- Salidas ----------------
static const uint8_t LED_G = 18; // NORMAL
static const uint8_t LED_Y = 19; // SOSPECHA / hueco en el stream
static const uint8_t LED_R = 23; // CONFIRMADO
Adafruit_SSD1306 display(128, 64, &Wire, -1);

#ifdef SECRET_MQTT_CA_CERT  // broker con TLS (p. ej. puerto 8883): verifica su certificado
#include <WiFiClientSecure.h>
WiFiClientSecure net;
#else
WiFiClient net;
#endif
PubSubClient mqtt(net);

// ---------------- Bloques entre nucleos ----------------
#define NBUF 4
struct BlockMeta {
  uint8_t idx;
  uint32_t seq;
  uint32_t t0;
  uint16_t late;
};
static uint16_t bufs[NBUF][BLOCK];
static uint16_t scratch[BLOCK];
static QueueHandle_t fullQ;
static QueueHandle_t freeQ;
static volatile uint32_t droppedBlocks = 0;
static volatile uint32_t sentBlocks = 0;
static volatile bool streamReady = false;
static volatile bool demoDone = false;   // la secuencia del chip termino

static float vRefEff = 3.3f;
static uint32_t rawRef = 0;
static char payload[3700];

// ---------------- Estado mostrado ----------------
struct Shown {
  char state[12] = "ESPERA";
  char cls[16] = "--";
  char eventId[48] = "";
  float tStart = NAN, tConf = NAN, tEnd = NAN, durMs = NAN;
} shown;

static char seen[8][64];
static uint8_t seenPos = 0;

// ------------------------------------------------------------------
static const char *className(const char *c) {
  if (!strcmp(c, "voltage_sag")) return "Hueco tension";
  if (!strcmp(c, "voltage_swell")) return "Sobretension";
  if (!strcmp(c, "interruption")) return "Interrupcion";
  if (!strcmp(c, "harmonics")) return "Armonicos";
  if (!strcmp(c, "flicker")) return "Flicker";
  if (!strcmp(c, "oscillatory_transient")) return "Trans. oscil.";
  if (!strcmp(c, "impulsive_transient")) return "Trans. impuls.";
  if (!strcmp(c, "notching")) return "Muescas";
  if (!strcmp(c, "voltage_sag_harmonics")) return "Hueco+armon.";
  if (!strcmp(c, "voltage_swell_harmonics")) return "Sobret.+armon.";
  if (!strcmp(c, "harmonics_flicker")) return "Armon.+flicker";
  return "--";
}

static void fmtTime(char *out, size_t n, const char *label, bool approx, float v) {
  if (isnan(v)) snprintf(out, n, "%s --", label);
  else snprintf(out, n, "%s %s%.2f s", label, approx ? "~" : "", v);
}

static void setLeds() {
  bool confirmed = !strcmp(shown.state, "CONFIRMADO");
  bool suspected = !strcmp(shown.state, "SOSPECHA") || !strcmp(shown.state, "HUECO");
  digitalWrite(LED_R, confirmed ? HIGH : LOW);
  digitalWrite(LED_Y, suspected ? HIGH : LOW);
  digitalWrite(LED_G, (!confirmed && !suspected) ? HIGH : LOW);
}

static void render() {
  char line[24];
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("ElectricalBenchAlert");
  snprintf(line, sizeof line, "Estado: %s", shown.state);
  display.println(line);
  snprintf(line, sizeof line, "Tipo: %s", shown.cls);
  display.println(line);
  fmtTime(line, sizeof line, "Inicio", true, shown.tStart);
  display.println(line);
  fmtTime(line, sizeof line, "Confirm.", false, shown.tConf);
  display.println(line);
  fmtTime(line, sizeof line, "Fin", true, shown.tEnd);
  display.println(line);
  if (isnan(shown.durMs)) snprintf(line, sizeof line, "Duracion --");
  else snprintf(line, sizeof line, "Duracion ~%.0f ms", shown.durMs);
  display.println(line);
  snprintf(line, sizeof line, "TX %lu perd %lu%s", (unsigned long)sentBlocks, (unsigned long)droppedBlocks,
           demoDone ? " FIN" : "");
  display.println(line);
  display.display();
  setLeds();
}

static void status(const char *a, const char *b = "") {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("ElectricalBenchAlert");
  display.println(a);
  display.println(b);
  display.display();
  Serial.printf("%s %s\n", a, b);
}

static float numOrNan(JsonVariantConst v) {
  return v.isNull() ? NAN : v.as<float>();
}

// Llega un mensaje de eba/sim01/events (se ejecuta en la tarea de red).
static void onEvent(char *topic, byte *data, unsigned int length) {
  JsonDocument doc;
  if (deserializeJson(doc, data, length)) {
    Serial.println("events: JSON invalido, ignorado");
    return;
  }
  const char *type = doc["type"] | "";
  const char *eventId = doc["event_id"] | "";
  if (!*type) return;

  // QoS 1 puede repetir mensajes: se ignora un (event_id, type) ya mostrado.
  char key[64];
  snprintf(key, sizeof key, "%s|%s", eventId, type);
  for (auto &k : seen)
    if (!strcmp(k, key)) return;
  strncpy(seen[seenPos], key, sizeof seen[0] - 1);
  seenPos = (seenPos + 1) % 8;

  if (!strcmp(type, "SUSPECTED")) {
    strcpy(shown.state, "SOSPECHA");
  } else if (!strcmp(type, "CONFIRMED") || !strcmp(type, "ENDED")) {
    if (strcmp(shown.eventId, eventId)) {  // evento nuevo: se limpian los tiempos
      strncpy(shown.eventId, eventId, sizeof shown.eventId - 1);
      shown.tEnd = shown.durMs = NAN;
    }
    strcpy(shown.state, !strcmp(type, "CONFIRMED") ? "CONFIRMADO" : "FIN");
    strncpy(shown.cls, className(doc["class"] | ""), sizeof shown.cls - 1);
    shown.tStart = numOrNan(doc["estimated_start_s"]);
    shown.tConf = numOrNan(doc["confirmation_time_s"]);
    shown.tEnd = numOrNan(doc["estimated_end_s"]);
    shown.durMs = numOrNan(doc["duration_ms"]);
  } else if (!strcmp(type, "NORMAL")) {
    strcpy(shown.state, "NORMAL");
  } else if (!strcmp(type, "GAP")) {
    strcpy(shown.state, "HUECO");  // hueco en el stream de muestras, no en la red
  } else {
    return;
  }
  Serial.printf("events: %s %s\n", type, eventId);
  render();
}

static void publishConfig() {
  char cfg[400];
  snprintf(cfg, sizeof cfg,
           "{\"fs\":%lu,\"block\":%u,\"adc_bits\":12,\"v_ref\":%.4f,\"raw_ref\":%lu,"
           "\"gain\":%.10f,\"v_offset\":%.3f,\"v_nominal\":%.1f,\"k_v_per_pu\":%.6f,"
           "\"enc\":\"u16le-b64\",\"device_id\":\"%s\","
           "\"source\":\"chip grid-signal, demo11: 11 familias de validacion v1.0.0 a 20 dB\"}",
           (unsigned long)FS_HZ, BLOCK, vRefEff, (unsigned long)rawRef, GAIN, V_OFFSET,
           V_NOMINAL, GAIN * V_NOMINAL, DEVICE_ID);
  mqtt.publish(T_CONFIG, cfg, true);
}

static void ensureConnected() {
  if (WiFi.status() != WL_CONNECTED) {
    status("Conectando WiFi...");
    WiFi.begin(WIFI_SSID, WIFI_PASS, 6);
    while (WiFi.status() != WL_CONNECTED) vTaskDelay(pdMS_TO_TICKS(100));
  }
  while (!mqtt.connected()) {
    status("Conectando MQTT...", MQTT_HOST);
    char clientId[40];
    snprintf(clientId, sizeof clientId, "eba-sim01-%08lx", (unsigned long)esp_random());
    bool ok = strlen(MQTT_USER) > 0 ? mqtt.connect(clientId, MQTT_USER, MQTT_PASS) : mqtt.connect(clientId);
    if (ok) {
      mqtt.subscribe(T_EVENTS, 1);
      publishConfig();
      streamReady = true;
      render();
    } else {
      vTaskDelay(pdMS_TO_TICKS(1000));
    }
  }
}

static void publishBlock(const BlockMeta &m) {
  static unsigned char b64[3400];
  size_t olen = 0;
  mbedtls_base64_encode(b64, sizeof b64, &olen, (const unsigned char *)bufs[m.idx],
                        BLOCK * sizeof(uint16_t));  // ESP32 es little-endian
  b64[olen] = 0;
  snprintf(payload, sizeof payload,
           "{\"seq\":%lu,\"t0_sample\":%lu,\"n\":%u,\"enc\":\"u16le-b64\",\"late\":%u,"
           "\"dropped\":%lu,\"data\":\"%s\"}",
           (unsigned long)m.seq, (unsigned long)m.t0, BLOCK, m.late,
           (unsigned long)droppedBlocks, (const char *)b64);
  bool ok = mqtt.publish(T_SAMPLES, payload);
  if (ok) sentBlocks++;

  // Diagnostico por Serial: RMS del bloque en p.u. (red normal ~1.0, hueco ~0.5).
  const float k = GAIN * V_NOMINAL;
  double acc = 0;
  for (uint16_t i = 0; i < BLOCK; i++) {
    float v = (bufs[m.idx][i] * vRefEff / 4095.0f - V_OFFSET) / k;
    acc += (double)v * v;
  }
  Serial.printf("bloque seq=%lu t=%.3f s Vrms=%.3f p.u. late=%u %s\n", (unsigned long)m.seq,
                m.t0 / (float)FS_HZ, sqrt(acc / BLOCK), m.late, ok ? "enviado" : "FALLO");
}

// Autoprueba de la pantalla sin el host MATLAB: con 1, el propio ESP32 publica
// en eba/sim01/events un CONFIRMED y un ENDED de prueba (event_id "autoprueba")
// y los recibe de vuelta por el broker. NO son salidas del modelo: dejar en 0.
#define SELF_TEST_EVENTS 0

static void selfTest(uint32_t seq) {
#if SELF_TEST_EVENTS
  if (seq == 26)
    mqtt.publish(T_EVENTS, "{\"type\":\"CONFIRMED\",\"event_id\":\"autoprueba:event:000001\","
                           "\"class\":\"voltage_sag\",\"estimated_start_s\":2.25,"
                           "\"confirmation_time_s\":3.0,\"estimated_end_s\":null,\"duration_ms\":null}");
  if (seq == 34)
    mqtt.publish(T_EVENTS, "{\"type\":\"ENDED\",\"event_id\":\"autoprueba:event:000001\","
                           "\"class\":\"voltage_sag\",\"estimated_start_s\":2.25,"
                           "\"confirmation_time_s\":3.0,\"estimated_end_s\":3.5,\"duration_ms\":1250}");
  if (seq == 42) mqtt.publish(T_EVENTS, "{\"type\":\"NORMAL\",\"event_id\":\"autoprueba:event:000001\"}");
#endif
}

// Nucleo 0: WiFi, MQTT, OLED. Nunca toca el ADC.
static void netTask(void *) {
  uint32_t lastRender = 0;
  for (;;) {
    ensureConnected();
    mqtt.loop();
    BlockMeta m;
    if (xQueueReceive(fullQ, &m, pdMS_TO_TICKS(5)) == pdTRUE) {
      publishBlock(m);
      xQueueSend(freeQ, &m.idx, 0);
      selfTest(m.seq);
    }
    if (millis() - lastRender > 1000) {
      lastRender = millis();
      render();
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_G, OUTPUT);
  pinMode(LED_Y, OUTPUT);
  pinMode(LED_R, OUTPUT);
  pinMode(PIN_RUN, OUTPUT);
  digitalWrite(PIN_RUN, LOW);
  pinMode(PIN_END, INPUT);

  Wire.begin(21, 22);
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) Serial.println("OLED no encontrada");

  analogReadResolution(12);
  analogSetPinAttenuation(PIN_SIGNAL, ADC_11db);
  analogSetPinAttenuation(PIN_REF, ADC_11db);

  // Calibracion: REF del chip = V_OFFSET conocido -> escala efectiva del ADC.
  uint32_t acc = 0;
  for (int i = 0; i < 256; i++) acc += analogRead(PIN_REF);
  rawRef = acc / 256;
  if (rawRef > 0) vRefEff = V_OFFSET * 4095.0f / rawRef;
  Serial.printf("ADC: raw_ref=%lu -> v_ref efectiva=%.4f V\n", (unsigned long)rawRef, vRefEff);

  fullQ = xQueueCreate(NBUF, sizeof(BlockMeta));
  freeQ = xQueueCreate(NBUF, sizeof(uint8_t));
  for (uint8_t i = 0; i < NBUF; i++) xQueueSend(freeQ, &i, 0);

#ifdef SECRET_MQTT_CA_CERT
  net.setCACert(SECRET_MQTT_CA_CERT);
#endif
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(4096);
  mqtt.setKeepAlive(30);
  mqtt.setSocketTimeout(10);
  mqtt.setCallback(onEvent);
  xTaskCreatePinnedToCore(netTask, "net", 8192, nullptr, 1, nullptr, 0);

  // El muestreo arranca solo cuando el broker esta listo, para que la muestra
  // 0 del stream sea la muestra 0 de la secuencia del chip.
  while (!streamReady) delay(50);
  digitalWrite(PIN_RUN, HIGH);
}

// Nucleo 1: muestreo a 10 kHz con reloj de tiempo simulado.
// La lectura se hace a mitad de cada periodo para no coincidir con el cambio
// de muestra del chip.
void loop() {
  static uint32_t seq = 0;
  static uint32_t sampleIndex = 0;
  static int64_t nextUs = esp_timer_get_time() + TS_US / 2;

  // Fin de la tabla del chip: no se publican mas bloques. La red sigue activa
  // para mostrar los eventos que el host todavia procesa (va con atraso).
  if (demoDone || digitalRead(PIN_END) == HIGH) {
    if (!demoDone) {
      demoDone = true;
      Serial.printf("demo terminada: %lu bloques (%lu muestras)\n", (unsigned long)seq,
                    (unsigned long)sampleIndex);
    }
    vTaskDelay(pdMS_TO_TICKS(1000));
    return;
  }

  uint8_t idx;
  bool haveBuf = xQueueReceive(freeQ, &idx, 0) == pdTRUE;
  uint16_t *dst = haveBuf ? bufs[idx] : scratch;
  uint16_t late = 0;

  for (uint16_t i = 0; i < BLOCK; i++) {
    int64_t now;
    while ((now = esp_timer_get_time()) < nextUs) {
    }
    if (now - nextUs >= TS_US) late++;
    dst[i] = analogRead(PIN_SIGNAL);
    nextUs += TS_US;
  }

  BlockMeta m{haveBuf ? idx : (uint8_t)0, seq, sampleIndex, late};
  if (haveBuf) xQueueSend(fullQ, &m, 0);
  else droppedBlocks++;  // el host vera el seq faltante y publicara GAP
  seq++;
  sampleIndex += BLOCK;
}
