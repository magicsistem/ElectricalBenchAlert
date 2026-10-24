# ElectricalBenchAlert

MATLAB benchmark of six continuous power quality event detection pipelines. Version 1.0.0 (tag `v1.0.0`) freezes the source, the validation run and its results, with only what is needed to inspect, verify and reproduce it. Version 1.1.0 adds a simulated end-to-end demo (ESP32 in Wokwi → MQTT → MATLAB host → ESP32) on top of the frozen model, without retraining or changing any frozen file. See `CHANGELOG.md` for the release contents.

Authors: Miguel Jhosua Benavides Castillo, Jesse Berenice Correa Reyes, Tomas Wesly Ponce Moscoso and Alvaro Dario Mendez Patilla. Citation metadata is in `CITATION.cff`.

## Frozen run

The benchmark pairs FFT/STFT/DWT with SVM and FFT/ST/CWT with Random Forest across the same 864 validation families, at 20 dB with one noise realization per family. The original test split was inspected in an earlier development phase, so these results are validation evidence, not an untouched final-test estimate.

| Pipeline | Event F1 [95% CI] | Recall | False alarms/min | Detection latency | Compute p95 / hop | Process RSS | Model size |
|---|---:|---:|---:|---:|---:|---:|---:|
| FFT + SVM | 0.7093 [0.6800, 0.7379] | 0.5947 | 0.686 | 0.237 s | 12.8 ms / 100 ms (0.128) | 1.54 GB | 2.66 MB |
| STFT + SVM | 0.6926 [0.6625, 0.7220] | 0.5732 | 0.687 | 0.480 s | 19.1 ms / 125 ms (0.152) | 1.52 GB | 2.67 MB |
| DWT + SVM | 0.6364 [0.6029, 0.6687] | 0.5051 | 0.693 | 0.555 s | 17.3 ms / 250 ms (0.069) | 1.65 GB | 2.67 MB |
| FFT + RF | 0.7972 [0.7727, 0.8216] | 0.7942 | 1.651 | 0.228 s | 195.6 ms / 50 ms (3.912) | 2.09 GB | 72.43 MB |
| ST + RF | 0.7574 [0.7333, 0.7813] | 0.7551 | 1.997 | 0.357 s | 227.7 ms / 125 ms (1.821) | 2.11 GB | 73.61 MB |
| **CWT + RF** | **0.8031 [0.7784, 0.8270]** | 0.7210 | **0.624** | 0.468 s | **211.0 ms / 125 ms (1.688)** | 2.13 GB | 72.35 MB |

CWT-RF is selected by the predeclared rule: maximize the family-grouped bootstrap lower 95% Event F1 bound, then point F1, fewer false alarms, and lower detection latency. Latency and size do not exclude candidates. Paired uncertainty does not establish a significant Event F1 difference from FFT-RF: delta +0.0059 [−0.0171, +0.0289], Holm-adjusted p=0.5924. CWT-RF has higher precision and fewer false alarms; FFT-RF has higher recall and shorter detection latency.

The selected model is 72.35 MB. Its p95 processing time is 211 ms for a 125 ms hop (RTF 1.688), so it does not sustain real-time throughput on the measured laptop. That compute cost is accepted for this simulation benchmark and remains a deployment limitation. The deterministic confirmation example reaches NORMAL → SUSPECTED → CONFIRMED for a validation sag in 0.2665 s, with zero false alarms in that sequence; this checks integration, not generalization.

## Repository layout

```text
+eba/        MATLAB package with the method (called as eba.<function>)
scripts/     run_* drivers and verify_* checks; v1.1.0 stream host and demo export
esp32/       v1.1.0 Wokwi project: ESP32 sketch, circuit, grid-signal chip and exported demo table
tests/       MATLAB test suites (run_all_tests)
config/      research_v2.json, the authoritative configuration
contracts/   JSON schema of the confirmed event
results/
  inputs/    frozen validation workload (streambench_inputs.mat)
  models/    serialized SVM and RF models
  metrics/   validation metrics, selection and paired contrasts
  runtime/   matched runtime measurements
  demo/      confirmed-event demonstration with CWT-RF
  manifests/ provenance manifests of each run
```

Manifests and `results/metrics/six_model_selection.json` were written before the results were reorganized, so they record the original `results/v2/...` locations. File contents and SHA-256 values are unchanged.

## Reproduce and verify

Requirements: MATLAB R2026b, Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox, and Parallel Computing Toolbox. The checked-in `results/` package contains the exact schedules, models, metrics, manifests, and demo outputs for this run.

From the repository root:

```sh
matlab -batch "disp(version); ver"
matlab -batch "startup; run_all_tests"
matlab -batch "startup; addpath('scripts'); verify_six_model_streambench; verify_six_model_selection"
matlab -batch "startup; addpath('scripts'); run_six_model_paired_events"
matlab -batch "startup; addpath('scripts'); run_selected_six_model_demo"
```

To rerun the six model validation and measurements, use a clean Git checkout with the bundled run inputs and execute:

```sh
matlab -batch "startup; addpath('scripts'); run_six_model_streambench"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('SVM','FFT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('SVM','STFT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('SVM','DWT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','FFT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','ST')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','CWT')"
matlab -batch "startup; addpath('scripts'); run_six_model_selection; run_six_model_paired_events; verify_six_model_streambench; verify_six_model_selection; run_selected_six_model_demo"
```

Runtime results depend on hardware and are measured in fresh MATLAB processes with a shared signal, shared decision endpoints, two warmups, and 100 repetitions. The checked-in manifests retain the original environment and artifact hashes.

## Simulated end-to-end demo (v1.1.0)

A Wokwi ESP32 samples a simulated, conditioned grid signal with its 12-bit ADC1 at 10 kHz (simulated time), publishes 1,250-sample blocks over MQTT, and `scripts/stream_host.m` classifies 0.5 s windows every 125 ms with the frozen CWT-RF model and state settings (θ_on = 0.5, θ_off = 0.3, K = 3, 2 recovery windows). Each state change (SUSPECTED, CONFIRMED, ENDED, NORMAL, GAP) is published back with QoS 1 and shown on the ESP32 OLED and LEDs. Sample times are sample index / 10,000, so Wokwi and host slowness only add delay.

The signal is `scripts/demo_sequence.m`: one validation family per event class (11 events, medium severity, duration stratum 4) in one continuous sequence at 20 dB with noise realization 1, the same condition as the six-model validation. `scripts/export_stream_signal.m` exports it as an int16 table for the Wokwi chip (`esp32/`, 343,750 samples, maximum error 5e-5 p.u.). A clean signal is not used: 12-bit quantization alone makes the model report `impulsive_transient` on normal voltage, while at 20 dB quantization has no effect.

Observed in Wokwi on 2026-10-24: 9 of 11 events confirmed with the correct class and no false alarms; the oscillatory (47 ms) and impulsive (4 ms) transients are not confirmed. All 272 live windows reached the same state as the offline replay and the 18 CONFIRMED/ENDED messages were published at the same simulated times. This is an integration check, not a new performance estimate.

```sh
matlab -batch "startup; addpath('scripts'); check_stream_host"                      # host == eba.processStream, window by window
matlab -batch "startup; addpath('scripts'); stream_host(Replay=true)"               # publish the demo events without an ESP32
matlab -batch "startup; addpath('scripts'); stream_host(SaveSamples='live.mat')"    # live with Wokwi; start the host first
```

`check_stream_host` must print `CHECK_STREAM_HOST_PASS`. See `esp32/README.md` to set up the Wokwi project and regenerate the chip table.

Broker and credentials: by default the host and the ESP32 use the public test broker `tcp://broker.hivemq.com:1883` without credentials, so anyone can read or publish on `eba/sim01/...`; it must not carry sensitive data. For a private broker, copy `broker.example.json` to `broker.local.json` (host) and `esp32/secrets.example.h` to `esp32/secrets.h` (ESP32); both local files are ignored by Git. Free Wokwi projects are public, so real ESP32 credentials must not be pasted into a free Wokwi project. The authenticated and TLS paths are written but not yet tested against a private broker. MQTT requires the Industrial Communication Toolbox.

## Scope

The benchmark is synthetic and stops at the CONFIRMED event. Version 1.1.0 demonstrates the acquisition and alert chain in simulation only: no real hardware or grid connection, no real-time processing (RTF 1.688), the public test broker, and no mobile app yet. Regulatory compliance monitoring is not implemented.
