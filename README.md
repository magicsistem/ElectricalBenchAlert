# ElectricalBenchAlert

Scientific MATLAB research for electrical disturbance detection. Current status: **development toward v1.0.0**. The confirmed-event milestone has not yet been accepted.

## Requirements and verified checks

MATLAB R2026b, Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox and Deep Learning Toolbox. Scientific execution uses local MATLAB; generated data and results are ignored by Git.

```sh
git clone https://github.com/magicsistem/ElectricalBenchAlert.git
cd ElectricalBenchAlert
matlab -batch "disp(version); ver"
matlab -batch "startup; test_signals; test_transforms; test_classifiers; test_statistics; test_pipeline"
```

These five scientific test suites have been executed successfully. They cover deterministic waveforms, exact noise power, grouped splits, five transform controls, controlled classifiers, paired family statistics and pipeline/firewall checks. They do not yet establish final classifier performance or continuous confirmed-event performance. CNN/TCN and stream verification remain in progress.

## Scientific scope

- Track A: FFT, STFT, DWT, CWT and band-limited S-Transform, a common 24-feature schema and ECOC SVM; Random Forest sensitivity.
- Track B: lightweight 1-D CNN and causal TCN on nominal p.u. waveforms, preserving absolute amplitude.
- Independent unit: family_id; every noise/crop derivative stays in its family's split.
- Proposed dataset: nine core classes plus three bounded composite classes, 240 families/class initially. Final size requires development learning curves and confidence intervals.
- Final test predictions remain sealed until source, dataset/split, offline models, streaming windows and temporal settings are hash-bound.
- Endpoint: a phase-continuous simulated signal producing NORMAL → SUSPECTED → CONFIRMED.

Nine original MAT arrays remain as scientific reference fixtures, with [SHA-256 identities](data/manifests/original_fixtures.json). The original complete 630-record dataset is unavailable. Regeneration uses a separately versioned MATLAB generator and does not claim identity with absent historical records. The temporary Python route and active legacy implementation have been removed; the baseline remains in the v0.1.0 Git tag.

## Development commands

```sh
matlab -batch "startup; generate_dataset"
matlab -batch "startup; run_development('representations')"
matlab -batch "startup; run_development('classifiers')"
matlab -batch "startup; run_development('learning')"
```

These experiment drivers are under development; authoritative benchmark results and the final reproduction commands will be added after execution and review. No MQTT, ESP32, Wokwi, Flutter, transport or application persistence is implemented.

## Repository documentation policy

Only root README.md and CHANGELOG.md are versioned Markdown. Audit, plan, decisions, references, gate ledgers and working documentation are local in ignored folders; local_docs/ is explicitly ignored. Public release notes are maintained in GitHub Releases. Historical Git trees have been filtered to the same Markdown allowlist, as requested.

Personal content identifiers and unnecessary private paths are excluded from publication. Existing configured Git author identity and credentials are retained.
