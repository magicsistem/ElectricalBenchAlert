# ElectricalBenchAlert

MATLAB research pipeline for synthetic 60 Hz electrical disturbance classification and continuous event confirmation.

## Selected detector

The corrected validation search selects **FFT + SVM ECOC**, 12-cycle window, 6-cycle hop. The previous DWT selection imposed an undocumented cap of one false alarm per minute, excluding higher-F1 candidates. The corrected code retains false alarms, latency, and RTF as Pareto objectives and uses p95 RTF ≤ 1 as the computational feasibility bound. On 864 full-validation families / 6,048 schedules, FFT measured event F1 **0.491** (95% family/sequence-cluster CI 0.473–0.510), recall **0.564**, missed-event rate **0.436**, and **6.112 unmatched confirmations per normal minute** (5.512–6.789). All 72 pure-normal validation families alarmed at least once. It reaches `CONFIRMED` in the deterministic synthetic demo; the measured alarm burden does not support operational use.

An illustrative validation sag deterministically reaches `NORMAL → SUSPECTED → CONFIRMED`. The output confidence is a calibrated minimum supporting-window score, not an event probability. The demo stops at confirmation, so the event end is right-censored.

## Requirements and checks

MATLAB R2026b with Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox, and Deep Learning Toolbox.

```sh
git clone https://github.com/magicsistem/ElectricalBenchAlert.git
cd ElectricalBenchAlert
matlab -batch "disp(version); ver"
matlab -batch "startup; run_all_tests"
```

The current local MATLAB run passed all nine suites. A clean clone does not contain the ignored dataset/model artifacts required for full-benchmark or confirmed-demo reproduction yet; this release candidate is not tagged `v1.0.0`.

The research artifacts and fitted models are generated under ignored `results/` and `data/generated/` paths and are not bundled in this source checkout. This is a release candidate, not a clean-clone v1.0.0 release: full reproduction currently needs those MATLAB artifacts, and the earlier test split was already inspected. Do not use `FROZEN_EXPERIMENT.json` to authorize confirmatory test access for the corrected FFT selection; it binds the superseded DWT protocol. The local full report records the exact validation manifests and the required conditions for a future independent release.

The local Spanish final report is `local_docs/FINAL_REPORT.md`; raw MATLAB outputs and figures are under `results/v2/`.

## Scientific scope

- Offline DSP comparison: FFT, STFT, DWT, CWT, and band-limited S-Transform with a common feature protocol and controlled SVM; Random Forest is a sensitivity classifier. Separate raw-waveform CNN and TCN baselines are reported.
- Dataset v2: 5,760 independent scenario families, 109,440 clean/noisy derivatives, nine primary disturbance classes and three declared closed-set composites. All derivatives remain in their family split.
- Continuous full validation: 864 independent families and 6,048 single-event schedules for the selected detector; separate close-spacing schedules are also measured. The previously inspected test metrics belong to the superseded DWT candidate.
- Research scope: synthetic event classification and confirmation. The project does not calculate regulatory Pst or claim compliance with Ecuadorian or Peruvian power-quality regulations.

The historical 630-record waveform set was unavailable; its hashes cannot reconstruct its missing samples. Nine MAT reference fixtures are preserved, and the new MATLAB dataset is a separately generated dataset, not a reconstruction of those absent records. No MQTT, broker, ESP32, Wokwi, Flutter, network transport, or mobile notification layer is included.
