# ElectricalBenchAlert

Scientific MATLAB research for electrical disturbance detection. Current status: **development toward v1.0.0**. The confirmed-event milestone has not yet been accepted.

## Requirements and verified checks

MATLAB R2026b, Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox and Deep Learning Toolbox. Scientific execution uses local MATLAB; generated data and results are ignored by Git.

```sh
git clone https://github.com/magicsistem/ElectricalBenchAlert.git
cd ElectricalBenchAlert
matlab -batch "disp(version); ver"
matlab -batch "startup; run_all_tests"
```

Nine MATLAB test suites have passed locally. They cover deterministic waveforms, exact noise power, grouped splits, five transform controls, controlled classifiers, paired family statistics, one-epoch CNN/TCN structural training, runtime controls, continuous processing through confirmation and typed freeze/mutation checks. The integration classifier is a control fixture. Final model selection and independent test evaluation remain pending.

## Scientific scope

- Track A: FFT, STFT, DWT, CWT and band-limited S-Transform, a common 24-feature schema and ECOC SVM; Random Forest sensitivity.
- Track B: lightweight 1-D CNN and causal TCN on nominal p.u. waveforms, preserving absolute amplitude.
- Independent unit: family_id; every noise/crop derivative stays in its family's split.
- Proposed dataset: nine core classes plus three bounded composite classes, 240 families/class initially; the next provisional candidate has 480 families/class. Final size requires development learning curves and confidence intervals.
- Final test predictions remain sealed until source, dataset/split, offline models, streaming windows and temporal settings are hash-bound.
- Endpoint: a phase-continuous simulated signal producing NORMAL → SUSPECTED → CONFIRMED.

Nine original MAT arrays remain as scientific reference fixtures, with [SHA-256 identities](data/manifests/original_fixtures.json). The original complete 630-record dataset is unavailable. Regeneration uses a separately versioned MATLAB generator and does not claim identity with absent historical records. The temporary Python route and active legacy implementation have been removed; the baseline remains in the v0.1.0 Git tag.

## Development commands

```sh
matlab -batch "startup; generate_dataset"
matlab -batch "startup; verify_dataset_records; verify_dataset_records"
matlab -batch "startup; run_development('representations')"
matlab -batch "startup; run_development('classifiers')"
matlab -batch "startup; run_development('learning')"
```

Development representation selection and ten DSP/classifier fits have executed in MATLAB. Initial learning curves have executed and rejected the current dataset size for FFT, STFT and DWT under the declared stability and confidence-interval criteria. The expanded candidate has 5,760 independent families and 109,440 derived records; two complete MATLAB regenerations produced an identical binary catalog, with maximum SNR deviation 1.78e-14 dB. Its size is still provisional. Expansion, full raw baselines and final streaming evaluation remain pending; development results do not establish final performance. No MQTT, ESP32, Wokwi, Flutter, transport or application persistence is implemented.
