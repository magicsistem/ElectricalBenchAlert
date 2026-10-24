# ESP32 + Wokwi – ElectricalBenchAlert v1.1.0

Nodo de medición y alerta simulado en Wokwi. El ESP32 muestrea a 10 kHz la señal de un chip de red
simulado, la publica por MQTT, el host MATLAB (`scripts/stream_host.m`) detecta y confirma eventos con
el modelo congelado de v1.0.0, y el ESP32 muestra en la OLED y los LEDs cada SOSPECHA, CONFIRMADO y FIN.

## Demo: 11 clases del dataset congelado (demo11)

El chip reproduce una secuencia continua de 34.375 s con **un evento por cada una de las 11 clases**
(una familia de validación de v1.0.0 por clase, severidad media, estrato de duración 4), separados por
red normal, a **20 dB con la realización de ruido 1**: la misma condición de la validación que
seleccionó CWT–RF. Ningún evento se calcula a mano: todo sale de `scripts/demo_sequence.m` y
`scripts/export_stream_signal.m`.

Por qué a 20 dB: con una señal limpia, la sola cuantización de 12 bits del ADC hace que el modelo vea
`impulsive_transient` en red normal (falsas alarmas). A 20 dB el ruido de cuantización queda unos 40 dB
por debajo y deja de influir.

Resultado (Wokwi, 24/10/2026): 9 de 11 eventos confirmados con su clase y 0 falsas alarmas; no se
confirman los transitorios oscilatorio (47 ms) e impulsivo (4 ms). Las 272 ventanas en vivo tienen el
mismo estado que el procesamiento offline y los 18 mensajes CONFIRMED/ENDED salen en los mismos
instantes. Es una demostración de integración, no una nueva medición del desempeño del modelo.

## Archivos

| Archivo | Qué hace |
| --- | --- |
| `sketch.ino` | ESP32: lee el ADC1 a 10 kHz, publica bloques de 1,250 muestras en `eba/sim01/samples`, publica `eba/sim01/config` y muestra en la OLED y los LEDs lo que llega a `eba/sim01/events`. Cuando el chip levanta END deja de publicar (la OLED muestra `FIN` junto a TX) y sigue mostrando eventos |
| `grid-signal.chip.c` | **Generado, no editar.** Chip en un solo archivo con la tabla incluida (base64 de int16, 1e-4 p.u.). Es el que se pega en Wokwi |
| `grid-signal.chip.base.c` | Plantilla legible del chip (`#include "signal_table.h"`) |
| `signal_table.h` | Tabla exportada (343,750 muestras) |
| `grid-signal.chip.json` | Pines: OUT, REF, RUN, END, GND |
| `diagram.json` | Circuito: chip → GPIO34 (señal), GPIO35 (referencia), GPIO25 → RUN, END → GPIO26, OLED I2C (21/22), LEDs en 18/19/23 con 220 Ω |
| `demo11_ground_truth.csv` | Verdad de cada evento (solo para comparar; el host nunca la usa) |
| `demo11_manifest.json` | Familias, n, escala, error máximo y SHA-256 de la tabla |
| `secrets.example.h` | Plantilla de credenciales; `secrets.h` (ignorado por git) la reemplaza |
| `libraries.txt` | PubSubClient, Adafruit GFX Library, Adafruit SSD1306, ArduinoJson |

## Regenerar la tabla y el chip (MATLAB, desde la raíz del repositorio)

```matlab
startup; addpath('scripts');
export_stream_signal("esp32", ChipTemplate="esp32/grid-signal.chip.base.c")
```

Debe imprimir `EXPORT_STREAM_SIGNAL_PASS n=343750 ... sha256=c3aaa503529feb30fb63ad6d7a17e1fd5830171acb89d67254e957cac93efb4d`.
Compilado con un `wokwi-api.h` de prueba, el chip reproduce la tabla con error máximo 5.0e-5 p.u.
respecto de `eba.continuousSignal` (hito H0).

## Crear o actualizar el proyecto en Wokwi

1. Pegar `sketch.ino` y `diagram.json` en sus pestañas.
2. Pegar `grid-signal.chip.json` y **`grid-signal.chip.c`** (≈ 945 KB) en sus pestañas.
3. Library Manager → las cuatro librerías.
4. Arrancar primero el host en MATLAB y después dar Run en Wokwi.

## Credenciales (hito 5)

- Sin `secrets.h` el sketch usa `Wokwi-GUEST` y el broker público `broker.hivemq.com:1883`, sin usuario.
  Ese broker es de pruebas: cualquiera puede leer o publicar en `eba/sim01/...`; no admite datos sensibles.
- Para un broker privado: copiar `secrets.example.h` a `secrets.h` y llenar host, puerto, usuario y
  clave (y el certificado raíz si usa TLS). `secrets.h` está en `.gitignore`.
- En el plan gratuito de Wokwi los proyectos son **públicos**: un `secrets.h` con claves reales pegado en
  el proyecto quedaría visible. Usar un proyecto unlisted (plan pago) o la extensión de VS Code.
- La ruta con usuario y TLS está escrita pero no se probó contra un broker real: todavía no hay uno.
- El host MATLAB lee sus credenciales de `broker.local.json` (ver `broker.example.json` en la raíz).

## Lo que no se demuestra

- Tiempo real: el host procesa con RTF 1.688; los eventos llegan con atraso, pero sus tiempos son de
  simulación (índice de muestra / 10,000).
- Hardware ni conexión a la red eléctrica: la etapa de acondicionamiento es un modelo en el chip.
- La muestra que lee el ESP32 va 1 muestra (0.1 ms) adelantada respecto de la tabla; las 2 primeras
  muestras del arranque difieren. No afecta ninguna ventana con evento.
