// grid-signal: red electrica simulada + etapa de acondicionamiento (v1.1.0, demo11).
//
// Reproduce, muestra a muestra a 10 kHz (tiempo simulado), la secuencia que
// exporta scripts/export_stream_signal.m: once familias de validacion de
// ElectricalBenchAlert v1.0.0 (una por clase de evento) unidas en una senal
// continua a 20 dB, la misma condicion de la validacion de CWT-RF.
// No calcula ningun evento: solo lee la tabla.
//   x[n]  = SIGNAL_TABLE[n] * SIGNAL_SCALE_PU                         [p.u.]
//   V_pin = v_offset + gain * v_nominal * x[n]                        [V]
//
// Pines:
//   OUT  salida analogica hacia el ADC del ESP32 (GPIO34)
//   REF  tension constante = v_offset, para que el ESP32 calibre su ADC
//   RUN  flanco de subida desde el ESP32 = inicio de la secuencia (n = 0)
//   END  pasa a HIGH cuando la tabla se termino (el ESP32 deja de publicar)
//   GND  tierra comun
//
// Este archivo es la plantilla. grid-signal.chip.c (el que se pega en Wokwi)
// lo genera export_stream_signal(..., ChipTemplate=...) con la tabla incluida.

#include "wokwi-api.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "signal_table.h"

#define TS_US 100

typedef struct {
  pin_t out, ref, run, end;
  timer_t timer;
  double v_offset, k;  // k = V por p.u.
  int16_t *x;          // tabla decodificada (SIGNAL_N muestras)
  uint32_t n;          // indice de la muestra que esta en OUT
  bool running;
} chip_state_t;

static int b64_value(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;  // '=' y cualquier otro caracter
}

// Decodifica SIGNAL_B64 (int16 little-endian) a un arreglo de SIGNAL_N muestras.
static int16_t *decode_table(void) {
  uint8_t *bytes = malloc(2u * SIGNAL_N);
  if (!bytes) return NULL;
  uint32_t nbytes = 0, acc = 0;
  int bits = 0;
  for (const char *p = SIGNAL_B64; *p; p++) {
    int v = b64_value(*p);
    if (v < 0) continue;
    acc = (acc << 6) | (uint32_t)v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      if (nbytes < 2u * SIGNAL_N) bytes[nbytes] = (uint8_t)(acc >> bits);
      nbytes++;
    }
  }
  if (nbytes != 2u * SIGNAL_N) {
    printf("grid-signal: tabla invalida (%u bytes, se esperaban %u)\n", nbytes, 2u * SIGNAL_N);
    free(bytes);
    return NULL;
  }
  int16_t *x = malloc(sizeof(int16_t) * SIGNAL_N);
  for (uint32_t i = 0; i < SIGNAL_N; i++)
    x[i] = (int16_t)((uint16_t)bytes[2 * i] | ((uint16_t)bytes[2 * i + 1] << 8));
  free(bytes);
  return x;
}

static void write_sample(chip_state_t *s) {
  uint32_t i = s->n < SIGNAL_N ? s->n : SIGNAL_N - 1;  // al final se mantiene la ultima
  double v = s->v_offset + s->k * (double)s->x[i] * SIGNAL_SCALE_PU;
  pin_dac_write(s->out, (float)v);
}

static void on_timer(void *user_data) {
  chip_state_t *s = (chip_state_t *)user_data;
  if (s->running && s->n < SIGNAL_N) {
    s->n++;
    if (s->n >= SIGNAL_N) {
      pin_write(s->end, HIGH);
      printf("grid-signal: fin de la secuencia (%u muestras)\n", (unsigned)SIGNAL_N);
    }
  }
  write_sample(s);
}

static void on_run(void *user_data, pin_t pin, uint32_t value) {
  chip_state_t *s = (chip_state_t *)user_data;
  if (value == HIGH && !s->running) {
    s->running = true;
    s->n = 0;
    pin_write(s->end, LOW);
    write_sample(s);
    timer_stop(s->timer);
    timer_start(s->timer, TS_US, true);
    printf("grid-signal: secuencia iniciada (n = 0), %u muestras\n", (unsigned)SIGNAL_N);
  } else if (value == LOW) {
    s->running = false;
  }
}

void chip_init(void) {
  chip_state_t *s = calloc(1, sizeof(chip_state_t));

  uint32_t a_off = attr_init_float("vOffset", 1.30f);
  uint32_t a_gain = attr_init_float("gain", 0.0029498525f);  // 1/339
  uint32_t a_vnom = attr_init_float("vNominal", 120.0f);    // RMS nominal
  s->v_offset = attr_read_float(a_off);
  s->k = (double)attr_read_float(a_gain) * (double)attr_read_float(a_vnom);

  s->out = pin_init("OUT", ANALOG);
  s->ref = pin_init("REF", ANALOG);
  s->run = pin_init("RUN", INPUT);
  s->end = pin_init("END", OUTPUT_LOW);
  pin_dac_write(s->ref, (float)s->v_offset);

  s->x = decode_table();
  if (!s->x) {
    printf("grid-signal: ERROR, no se pudo decodificar la tabla\n");
    return;
  }

  const timer_config_t timer_cfg = {.callback = on_timer, .user_data = s};
  s->timer = timer_init(&timer_cfg);
  const pin_watch_config_t run_cfg = {.edge = BOTH, .pin_change = on_run, .user_data = s};
  pin_watch(s->run, &run_cfg);

  // Hasta que el ESP32 levante RUN se mantiene la primera muestra.
  write_sample(s);
  timer_start(s->timer, TS_US, true);
  printf("grid-signal: listo, %u muestras (%.3f s), k = %.5f V/p.u., offset = %.2f V\n",
         (unsigned)SIGNAL_N, SIGNAL_N / 10000.0, s->k, s->v_offset);
}
