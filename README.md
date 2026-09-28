# ElectricalBenchAlert

Scientific MATLAB research for electrical disturbance detection. Current audited baseline: **v0.1.0 development**, not the final confirmed-event milestone.

## Baseline requirements and reproduction

Local MATLAB R2026b was used. Wavelet Toolbox and Statistics and Machine Learning Toolbox are required by the existing tests. Signal Processing, Deep Learning and Simulink are installed in the audited environment for the planned reconstruction.

```sh
git clone https://github.com/magicsistem/ElectricalBenchAlert.git
cd ElectricalBenchAlert
matlab -batch "disp(version); ver"
matlab -batch "setenv('PQ_DATASET_ROOT',fullfile(pwd,'fixtures','dataset_fixture')); startup; run_all_tests"
```

The six existing test functions pass against nine clean training fixtures. They do not establish classifier validation, dataset reproducibility or continuous detection. The inherited orchestrator fails in R2026b; see [execution evidence](docs/audit/BASELINE_EXECUTION.md).

## Available evidence

- [Critical legacy audit](docs/audit/LEGACY_AUDIT.md)
- [Source inventory and original digests](docs/audit/legacy_inventory.json)
- [MATLAB environment](docs/audit/baseline_environment.json)
- [MATLAB Code Analyzer output](docs/audit/baseline_checkcode.json)
- [Baseline release notes](releases/v0.1.0.md)
- [Acceptance outcomes](GATES.md)

The temporary Python route and its outputs were removed from publication at the user request; they remain only in the private original audit snapshot. The source hash list describes 630 development records and 90 families; this checkout contains only nine raw MAT fixtures. No unavailable original waveform has been replaced with a synthetic approximation.

## Scientific scope of the reconstruction

The required milestone is **signal → scientific dataset → DSP and classifier comparison → grouped inference → continuous windows → NORMAL → SUSPECTED → CONFIRMED**. A final v1.0.0 release requires executed MATLAB experiments and every acceptance outcome, including independent final stream evaluation. See PLAN.md as the supplied hypothesis under audit. Application and communication development are outside this phase.

Personal contributor identifiers were replaced by neutral baseline names before first publication. The original source bytes are preserved in a private local snapshot. Configured Git commit identity is used without alteration.
