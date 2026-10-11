# Changelog

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
