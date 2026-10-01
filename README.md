# ElectricalBenchAlert

MATLAB research pipeline for synthetic 60 Hz electrical disturbance classification and continuous event confirmation.

## Model selection status

There is not yet a defensible final continuous-detector winner. The offline DSP SVM comparison and the continuous event detector answer different questions, so the repository now records their leaders separately. The observed offline SVM leader is FFT (nine-class validation Macro F1 **0.579**, 95% family interval **0.560–0.597**). The continuous selection must use complete validation and matched-runtime results from every feasible refined candidate.

The previous freeze path read a legacy full-stream file that contained only DWT and could therefore treat “only result present” as “best.” It also omitted offline-only methods from the comparison table. The corrected path reads the newer `reselection` artifacts, checks candidate coverage, preserves all five offline SVM rows, and marks offline and stream selections separately. Current refinement retained FFT, STFT, and DWT as compute-feasible; ST and CWT did not meet the p95 compute/hop bound. Full refit and matched-runtime evaluation of all three candidates must finish before a continuous winner is frozen. Older 0.491 FFT and 0.428 DWT event-F1 summaries use superseded streaming runs and are not current model-selection results.

The detector must report event F1, recall/miss rate, false alarms per normal minute and normal-family alarm incidence with uncertainty. A single deterministic `NORMAL → SUSPECTED → CONFIRMED` demo proves state transitions only; it does not establish model quality or operational suitability.

An illustrative validation sag deterministically reaches `NORMAL → SUSPECTED → CONFIRMED`. The output confidence is a calibrated minimum supporting-window score, not an event probability. The demo stops at confirmation, so the event end is right-censored.

## Requirements and checks

MATLAB R2026b with Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox, and Deep Learning Toolbox.

```sh
git clone https://github.com/magicsistem/ElectricalBenchAlert.git
cd ElectricalBenchAlert
matlab -batch "disp(version); ver"
matlab -batch "startup; run_all_tests"
```

The current local MATLAB run passed all nine suites, including a positive control and a negative control for incomplete candidate coverage. A clean clone does not contain the ignored dataset/model artifacts required for full-benchmark or confirmed-demo reproduction; this release candidate is not tagged `v1.0.0`.

The research artifacts and fitted models are generated under ignored `results/` and `data/generated/` paths and are not bundled in this source checkout. This is a release candidate, not a clean-clone v1.0.0 release: full reproduction currently needs those MATLAB artifacts, and the earlier test split was already inspected. Do not use `FROZEN_EXPERIMENT.json` to authorize confirmatory test access for the corrected FFT selection; it binds the superseded DWT protocol. The local full report records the exact validation manifests and the required conditions for a future independent release.

The local Spanish final report is `local_docs/FINAL_REPORT.md`; raw MATLAB outputs and figures are under `results/v2/`.

## Scientific scope

- Offline DSP comparison: FFT, STFT, DWT, CWT, and band-limited S-Transform with a common feature protocol and controlled SVM; Random Forest is a sensitivity classifier. Separate raw-waveform CNN and TCN baselines are reported.
- Dataset v2: 5,760 independent scenario families, 109,440 clean/noisy derivatives, nine primary disturbance classes and three declared closed-set composites. All derivatives remain in their family split.
- Continuous full validation: 864 independent families and 6,048 single-event schedules for the selected detector; separate close-spacing schedules are also measured. The previously inspected test metrics belong to the superseded DWT candidate.
- Research scope: synthetic event classification and confirmation. The project does not calculate regulatory Pst or claim compliance with Ecuadorian or Peruvian power-quality regulations.

The historical 630-record waveform set was unavailable; its hashes cannot reconstruct its missing samples. Nine MAT reference fixtures are preserved, and the new MATLAB dataset is a separately generated dataset, not a reconstruction of those absent records. No MQTT, broker, ESP32, Wokwi, Flutter, network transport, or mobile notification layer is included.
