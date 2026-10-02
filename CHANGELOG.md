# Changelog

## Unreleased — Six-model validation update

- Retained the three light stream candidates (FFT/STFT/DWT + SVM) and added the three best offline RF candidates (FFT/ST/CWT).
- Compared all six on the same 864 validation families, one paired 20 dB realization per family, with grouped-family uncertainty and matched runtime measurements.
- Selected CWT + RF under the declared rule: maximize the Pareto-eligible candidate's lower 95% grouped-bootstrap Event F1 bound without excluding models by latency or size. CWT-RF Event F1 is 0.8031 [0.7784, 0.8270], false alarms 0.624/min, and p95 compute 211 ms (RTF 1.688) for a 125 ms hop.
- Added 10,000-replicate paired family bootstrap and permutation analysis for all 15 Event F1 contrasts, with Holm correction. CWT-RF and FFT-RF are statistically unresolved: paired difference +0.0059 [−0.0171, +0.0289], Holm-adjusted p=0.5924.
- Reproduced NORMAL → SUSPECTED → CONFIRMED for a validation sag using CWT-RF; 0.2665 s confirmation latency in the deterministic demo.
- The focused MATLAB streaming and test-firewall checks pass. The frozen six-model run package is included for clean-checkout verification and reproduction.
- The historical test split had been inspected during a superseded phase. Current results are validation-only and do not support a confirmatory v1.0.0 release.
