# Changelog

## 1.0.0 — Release candidate; STFT selected on validation

- Keep the one-false-alarm/minute rule removed. No application-independent false-alarm cap is used; p95 compute/hop ≤1 remains the compute-feasibility bound, while false-alarm burden stays explicit in the results.
- Fix selection provenance: selection consumes corrected `reselection` artifacts, fails if any refined feasible candidate is missing from full validation, retains all five offline SVM representations, and reports offline and continuous leaders separately.
- Complete corrected full validation and matched-runtime comparison for FFT, STFT, and DWT selects STFT + SVM ECOC in the finite search. Continuous Event F1 is 0.566 [0.542, 0.589], recall 0.515, false alarms 2.561/min [2.288, 2.868], matched latency 0.556 s, and p95 RTF 0.151. All 72 pure-normal validation families alarmed; the candidate is not operationally acceptable.
- The primary offline shared-SVM leader is also STFT: nine-class validation Macro F1 0.591 [0.571, 0.611]. The old DWT-only choice came from an incomplete legacy result file; selection now fails on missing candidate coverage and reports offline and stream tracks separately.
- Re-run the confirmed-event demonstration with selected STFT: a synthetic sag reached `CONFIRMED` in 0.5165 s with three supporting windows and no preceding false alarms. Test remains unavailable for new confirmation because the original split was previously inspected.
- MATLAB regression suite passes 9/9 suites, including candidate-coverage positive and negative controls. Independent test, clean-clone artifact reproduction, and GitHub release remain incomplete.
- The intended phase boundary remains local continuous detection through `CONFIRMED`; regulatory compliance measurement and external communications are not implemented.

## 0.1.0 — Audited legacy baseline

- Preserve the supplied MATLAB baseline, nine MAT fixtures, and development provenance in the tagged baseline tree.
- Record that the legacy MATLAB integration was incomplete and that its benchmark had not been run as an authoritative MATLAB result.
- Document the missing complete 630-record dataset and the known limits of its provisional development outputs.
