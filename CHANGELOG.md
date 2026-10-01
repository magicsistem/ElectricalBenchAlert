# Changelog

## 1.0.0 — Release candidate; selection audit in progress

- Keep the one-false-alarm/minute rule removed. No application-independent false-alarm cap is used; p95 compute/hop ≤1 remains the compute-feasibility bound, while false-alarm burden stays explicit in the results.
- Fix selection provenance: the freeze now consumes corrected `reselection` artifacts, fails if any refined feasible candidate is missing from full validation, retains all five offline SVM representations, and reports offline and continuous leaders separately.
- Current refinement retained FFT, DWT, and CWT as compute-feasible; ST and STFT did not meet p95 compute/hop ≤1. Complete corrected full-refit and matched-runtime results are not yet available, so no final streaming winner is declared.
- Observed offline SVM leader: FFT, nine-class validation Macro F1 0.579 (95% family interval 0.560–0.597). Older FFT/DWT event scores are superseded stream runs and do not select the current detector.
- MATLAB regression suite passes 9/9 suites, including candidate-coverage positive and negative controls. Independent test, clean-clone artifact reproduction, and GitHub release remain incomplete.
- The intended phase boundary remains local continuous detection through `CONFIRMED`; regulatory compliance measurement and external communications are not implemented.

## 0.1.0 — Audited legacy baseline

- Preserve the supplied MATLAB baseline, nine MAT fixtures, and development provenance in the tagged baseline tree.
- Record that the legacy MATLAB integration was incomplete and that its benchmark had not been run as an authoritative MATLAB result.
- Document the missing complete 630-record dataset and the known limits of its provisional development outputs.
