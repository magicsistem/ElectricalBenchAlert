# Changelog

## 1.0.0 — Release candidate; streaming selection corrected

- Remove the undocumented one-false-alarm/minute hard gate from streaming selection; retain event F1, false alarms, latency, and RTF in the Pareto comparison, with p95 RTF ≤1 as the computational bound.
- Select FFT + SVM ECOC (12-cycle window, 6-cycle hop) as the highest-event-F1 RTF-feasible candidate in the finite validation search. Full-validation event F1 is 0.491 (95% family/sequence-cluster interval 0.473–0.510), recall 0.564, missed-event rate 0.436, and unmatched confirmations 6.112 per normal minute (5.512–6.789). All 72 pure-normal validation families alarmed at least once; no operational claim is supported.
- Add a phase-continuous 60 Hz signal generator, sliding-window inference, hysteretic persistence state machine, and a deterministic `NORMAL → SUSPECTED → CONFIRMED` demonstration.
- Regenerate the MATLAB dataset v2 with 5,760 independent families, nine primary classes, three closed-set composites, and 109,440 derived records; verify repeated generation and family-isolated splits.
- Execute the frozen offline comparison of FFT, STFT, DWT, CWT, and S-Transform with SVM and Random Forest, plus two-seed raw CNN/TCN sensitivity baselines.
- Add family-cluster uncertainty, paired comparisons with Holm adjustment, noise-robustness summaries, temporal event metrics, runtime measurements, and Pareto-based validation selection.
- The previous DWT stream benchmark over 864 test families and 6,048 single-event schedules is historical/descriptive only. Its test event F1 was 0.420 (95% cluster interval 0.388–0.450); missed-event rate was 0.721 and unmatched confirmations were 0.438 per normal minute. That test split had already been inspected and cannot confirm the corrected selection.
- Reach `CONFIRMED` with the re-selected FFT model in a deterministic synthetic validation demo. This single demo is not an independent performance estimate.
- MATLAB regression suite passes 9/9 suites in the current local artifact workspace. Clean-clone full reproduction, a newly reserved test cohort, and GitHub release remain incomplete.
- Keep the original full 630-record waveform dataset limitation explicit; preserve nine available MAT reference fixtures and do not claim to reconstruct unavailable records.
- Scope stops at the local confirmed-event contract. Regulatory compliance measurement and external communications are not implemented.

## 0.1.0 — Audited legacy baseline

- Preserve the supplied MATLAB baseline, nine MAT fixtures, and development provenance in the tagged baseline tree.
- Record that the legacy MATLAB integration was incomplete and that its benchmark had not been run as an authoritative MATLAB result.
- Document the missing complete 630-record dataset and the known limits of its provisional development outputs.
