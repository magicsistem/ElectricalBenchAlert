// Plantilla de credenciales del ESP32 (hito 5). Copiar a secrets.h, que git ignora,
// y reemplazar los valores. Sin secrets.h el sketch usa Wokwi-GUEST y el broker
// publico de pruebas, sin usuario.
//
// Atencion: en el plan gratuito de Wokwi los proyectos son publicos. Un secrets.h
// con claves reales dentro de un proyecto de Wokwi gratuito seria visible para
// cualquiera; usar un proyecto unlisted (plan pago) o la extension de VS Code.
#pragma once

#define SECRET_WIFI_SSID "Wokwi-GUEST"
#define SECRET_WIFI_PASS ""

#define SECRET_MQTT_HOST "mi-broker.example.com"
#define SECRET_MQTT_PORT 1883
#define SECRET_MQTT_USER "usuario-del-dispositivo"
#define SECRET_MQTT_PASS "cambiar-esta-clave"

// Solo si el broker usa TLS (normalmente puerto 8883): certificado raiz en PEM.
// #define SECRET_MQTT_CA_CERT "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
