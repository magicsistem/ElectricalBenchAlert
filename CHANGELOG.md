# Changelog

## [1.1.0] — unreleased

Simulated end-to-end demo on top of the frozen v1.0.0 model. Nothing in `+eba/`, `config/` or `results/` changed and nothing was retrained.

### Added

- `scripts/stream_host.m`: MQTT inference host. Subscribes to `eba/sim01/config` and `eba/sim01/samples`, converts ADC counts to p.u. with the published scale, classifies arrived 0.5 s windows every 125 ms with CWT-RF and the frozen state settings, and publishes SUSPECTED, CONFIRMED, ENDED, NORMAL and GAP to `eba/sim01/events` with QoS 1. Replay mode without an ESP32; optional capture of received blocks (`SaveSamples`).
- `scripts/check_stream_host.m`: milestone H2 check; the host matches `eba.processStream(..., false)` window by window (272 windows, identical states, classes and confidences).
- `scripts/demo_sequence.m`: the demo sequence, one validation family per event class at 20 dB with noise realization 1 (34.375 s, 11 events).
- `scripts/export_stream_signal.m`: milestone H0 exporter; int16 table (1e-4 p.u.), ground truth CSV, manifest with SHA-256, and a single-file Wokwi chip.
- `esp32/`: Wokwi ESP32 sketch, circuit, table-driven grid-signal chip with an END pin, exported table and README.
- Local credential files for a private broker (milestone 5): `broker.local.json` for the host and `esp32/secrets.h` for the ESP32, both ignored by Git, with committed examples.

### Verified

- Live Wokwi run (2026-10-24): 9 of 11 events confirmed with the correct class, no false alarms; same 272 window states and same 18 CONFIRMED/ENDED times as the offline replay. The oscillatory and impulsive transients are not confirmed.
- The exported table reproduces `eba.continuousSignal` within 5e-5 p.u.; the chip compiled with a stub `wokwi-api.h` reproduces the table within the same bound.
- `run_all_tests` passes (`ALL_MATLAB_TESTS_PASSED suites=2`).

### Notes

- A clean demo signal is not used: 12-bit ADC quantization of a clean signal makes the model report `impulsive_transient` on normal voltage (false alarms). At 20 dB, the validation condition, quantization has no effect.
- Not real time (RTF 1.688); timestamps are simulated (sample index / 10,000). The ESP32 reads one sample ahead of the table (0.1 ms).
- The default broker is the public HiveMQ test broker without credentials. The authenticated and TLS paths are not yet tested against a private broker. Free Wokwi projects are public.
- The mobile app and regulatory compliance monitoring are not implemented.

## [1.0.0] — 2026-10-10

First stable release. It freezes the source, the six-model validation run and its results as they stand after the work since v0.1.0. No experiment was rerun for this release.

### Method and evaluation

- Twelve-class family-aware synthetic benchmark: 5,760 independent parameter families (12 classes × 3 severity × 4 duration strata × 40), with clean and paired noisy derivatives; split by family.
- Waveform-only DSP protocol with 24 features (8 time-domain + 16 transform summaries) over FFT, STFT, DWT, CWT and S-transform; SVM and Random Forest classifiers with temperature calibration.
- Causal continuous processing of arrived windows and a persistent NORMAL → SUSPECTED → CONFIRMED → RECOVERY state machine that emits each confirmation once, as a versioned JSON event (`contracts/confirmed_event.schema.json`).
- Six matched pipelines: the three light stream candidates (FFT/STFT/DWT + SVM) and the three best offline RF candidates (FFT/ST/CWT), compared on the same 864 validation families, one paired 20 dB realization per family, with grouped-family uncertainty and matched runtime measurements.
- Selected CWT + RF under the declared rule: maximize the Pareto-eligible candidate's lower 95% grouped-bootstrap Event F1 bound without excluding models by latency or size. CWT-RF Event F1 is 0.8031 [0.7784, 0.8270], false alarms 0.624/min, and p95 compute 211 ms (RTF 1.688) for a 125 ms hop.
- 10,000-replicate paired family bootstrap and permutation analysis for all 15 Event F1 contrasts, with Holm correction. CWT-RF and FFT-RF are statistically unresolved: paired difference +0.0059 [−0.0171, +0.0289], Holm-adjusted p=0.5924.
- Deterministic demo reproduces NORMAL → SUSPECTED → CONFIRMED for a validation sag with CWT-RF; 0.2665 s confirmation latency.
- MATLAB streaming and test-firewall suites (`run_all_tests`) and the six-model verifiers are included.

### Repository

- Flattened `results/v2` into `results/inputs`, `models`, `metrics`, `runtime`, `demo` and `manifests`; caches go to the ignored `results/cache/`. Scripts point to the new locations; no result file changed (all moves are exact renames).
- Manifests, `results/metrics/six_model_selection.json` and the frozen artifacts keep the paths, commits and `method_version` (`0.2.0-development`) recorded when they were produced; they are provenance and were not rewritten.
- The manuscript evidence exporter (`Paper/scripts/extract_evidence.m`) is pinned to snapshot `8eec7c6`, which has the original `results/v2` layout.
- Listed the four project authors in `CITATION.cff`.

### Scope

- Results are validation evidence. The historical test split had been inspected during an earlier development phase, so this release does not report an untouched final-test estimate.
- ESP32 acquisition, MQTT transport, mobile app and regulatory compliance monitoring are not implemented.

## [0.1.0] — 2026-09-28

- Audited MATLAB legacy baseline; six fixture tests pass, complete legacy benchmark not validated.
