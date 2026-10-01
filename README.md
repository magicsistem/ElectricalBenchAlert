# ElectricalBenchAlert

MATLAB research pipeline for synthetic 60 Hz electrical disturbance classification and continuous event confirmation.

## Validation-selected models

The corrected, validation-only comparison selects **STFT + SVM ECOC** for both the primary offline DSP track and the continuous stream track. Selection covered all five offline representations and all three refined RTF-feasible continuous candidates; test was not accessed.

| Track | Method | Primary metric | Other validation result |
|---|---|---:|---|
| Offline DSP, shared SVM | **STFT** | Macro-F1 0.5915 [0.5710, 0.6114] | Nine primary classes; family-cluster 95% CI |
| Continuous events | **STFT**, 30-cycle window, 7.5-cycle hop | Event F1 0.5656 [0.5421, 0.5891] | Recall 0.5150; false alarms 2.5605/min [2.2884, 2.8678]; matched latency 0.5560 s |
| Matched runtime | STFT | p95 RTF 0.1509 | 100 decisions, two warmups, fresh MATLAB session |

FFT has lower event F1 (0.4913) and higher false-alarm rate (6.1118/min); DWT has lower event F1 (0.5236), lower false alarms (2.0526/min), and faster RTF (0.0946). All three are Pareto candidates, so the stated rule selects the highest Event F1 and reports the tradeoffs. The old DWT-only choice came from a legacy full-stream artifact that omitted the other methods; the selector now fails on incomplete candidate coverage and reports offline and stream leaders separately.

STFT is the best candidate in this finite validation search, **not an operationally acceptable detector**: all 72 pure-normal validation families had at least one alarm. A deterministic sag demo reaches `NORMAL → SUSPECTED → CONFIRMED` in 0.5165 s with three supporting windows and no preceding false alarms; the demo illustrates the transition and does not estimate generalization. The earlier test split was already inspected under the superseded protocol; a new untouched test is required before confirmatory claims or v1.0.0.

An illustrative validation sag deterministically reaches `NORMAL → SUSPECTED → CONFIRMED`. The output confidence is a calibrated minimum supporting-window score, not an event probability. The demo stops at confirmation, so the event end is right-censored.

## Requirements and checks

MATLAB R2026b with Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox, and Deep Learning Toolbox.

```sh
git clone https://github.com/magicsistem/ElectricalBenchAlert.git
cd ElectricalBenchAlert
matlab -batch "disp(version); ver"
matlab -batch "startup; run_all_tests"
```

The current local MATLAB run passed all nine suites, including positive/negative candidate-selection controls. A clean clone does not contain the ignored dataset/model artifacts required for full reproduction; this release candidate is not tagged `v1.0.0`.

The research artifacts and fitted models are generated under ignored `results/` and `data/generated/` paths and are not bundled in this source checkout. This is a release candidate, not a clean-clone v1.0.0 release: full reproduction currently needs those MATLAB artifacts, and the earlier test split was already inspected. Do not use `FROZEN_EXPERIMENT.json` to authorize confirmatory test access for the corrected STFT selection; it binds the superseded DWT protocol. The local full report records the exact validation manifests and the required conditions for a future independent release.

The local Spanish final report is `local_docs/FINAL_REPORT.md`; raw MATLAB outputs and figures are under `results/v2/`.

## Scientific scope

- Offline DSP comparison: FFT, STFT, DWT, CWT, and band-limited S-Transform with a common feature protocol and controlled SVM; Random Forest is a sensitivity classifier. Separate raw-waveform CNN and TCN baselines are reported.
- Dataset v2: 5,760 independent scenario families, 109,440 clean/noisy derivatives, nine primary disturbance classes and three declared closed-set composites. All derivatives remain in their family split.
- Continuous full validation: 864 independent families and 6,048 single-event schedules for the selected detector; separate close-spacing schedules are also measured. The previously inspected test metrics belong to the superseded DWT candidate.
- Research scope: synthetic event classification and confirmation. The project does not calculate regulatory Pst or claim compliance with Ecuadorian or Peruvian power-quality regulations.

The historical 630-record waveform set was unavailable; its hashes cannot reconstruct its missing samples. Nine MAT reference fixtures are preserved, and the new MATLAB dataset is a separately generated dataset, not a reconstruction of those absent records. No MQTT, broker, ESP32, Wokwi, Flutter, network transport, or mobile notification layer is included.
