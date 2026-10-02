# ElectricalBenchAlert

MATLAB research pipeline for synthetic 60 Hz electrical disturbance classification and continuous event confirmation.

## Validation-selected stream model

The six-model comparison retains three light SVM pipelines and adds the three offline-leading RF pipelines. Under the quality-first rule, **CWT + RF** is selected for the simulated detector.

| Model | Event F1 [95% CI] | Recall | False alarms/min | Confirmation latency | p95 compute / hop | Model size |
|---|---:|---:|---:|---:|---:|---:|
| FFT + SVM | 0.7093 [0.6800, 0.7379] | 0.5947 | 0.686 | 0.237 s | 0.116 | 2.66 MB |
| STFT + SVM | 0.6926 [0.6625, 0.7220] | 0.5732 | 0.687 | 0.480 s | 0.131 | 2.67 MB |
| DWT + SVM | 0.6364 [0.6029, 0.6687] | 0.5051 | 0.693 | 0.555 s | 0.068 | 2.67 MB |
| FFT + RF | 0.7972 [0.7727, 0.8216] | 0.7942 | 1.651 | 0.228 s | 3.888 | 72.43 MB |
| ST + RF | 0.7574 [0.7333, 0.7813] | 0.7551 | 1.997 | 0.357 s | 1.789 | 73.61 MB |
| **CWT + RF** | **0.8031 [0.7784, 0.8270]** | 0.7210 | **0.624** | 0.468 s | **1.616** | 72.35 MB |

Five of the six candidates remain on the Pareto front across event quality, false alarms, latency, compute cost, and model size; STFT-SVM is dominated. The selector has no latency or size exclusion: it maximizes the grouped-bootstrap lower Event F1 bound, then point F1, fewer false alarms, and shorter latency. A paired analysis across 864 validation families estimates CWT-RF minus FFT-RF at +0.0059 Event F1 (95% CI −0.0171 to +0.0289; Holm-adjusted p=0.5924). The two heavy leaders are statistically unresolved on Event F1. CWT-RF is selected by the declared rule; it offers higher precision and fewer false alarms, while FFT-RF has higher recall and lower confirmation latency.

CWT-RF is 72.35 MB and its p95 compute time is 202 ms for a 125 ms hop (RTF 1.616). It does not sustain real-time processing on the measured laptop; this cost is accepted for the current simulation milestone and does not make it embedded-ready. The confirmed-event demonstration reaches NORMAL → SUSPECTED → CONFIRMED for a validation sag in 0.2665 s. This single sequence checks integration, not generalization.

Temporal evaluation covers one paired 20 dB noise realization per family (864 validation families, 792 true events). The original test split was inspected during a superseded phase, so these validation results do not constitute an untouched confirmatory test or justify a confirmatory v1.0.0 release. This is synthetic disturbance research, not regulatory compliance measurement.

## Requirements and tests

MATLAB R2026b with Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox, and Deep Learning Toolbox.

    git clone https://github.com/magicsistem/ElectricalBenchAlert.git
    cd ElectricalBenchAlert
    matlab -batch "disp(version); ver"
    matlab -batch "startup; run_all_tests"

The current local MATLAB suite passed 9/9 suites. Research artifacts and fitted models are stored under ignored results/ and data/generated/ paths and are not bundled in this source checkout; complete reproduction from a clean clone therefore requires those artifacts or the full generation workflow.

With the required local dataset and model artifacts available, reproduce the comparison, runtime, statistical analysis, and demo:

    matlab -batch "startup; addpath('scripts'); run_six_model_streambench"
    matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','FFT')"
    matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','ST')"
    matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','CWT')"
    matlab -batch "startup; addpath('scripts'); run_six_model_selection; verify_six_model_streambench; verify_six_model_selection"
    matlab -batch "startup; addpath('scripts'); run_six_model_paired_events"
    matlab -batch "startup; addpath('scripts'); run_selected_six_model_demo"

If the full development artifacts have been regenerated, prepare the reduced 864-family input package with prepare_six_model_streambench_inputs before running the streambench.

## Scientific scope

- Offline DSP comparison: FFT, STFT, DWT, CWT, and band-limited S-Transform with a common feature protocol and controlled SVM; Random Forest is a sensitivity classifier. Separate raw-waveform CNN and TCN baselines are reported.
- Dataset v2: 5,760 independent scenario families, 109,440 clean/noisy derivatives, nine primary disturbance classes and three declared closed-set composites. All derivatives remain within their family split.
- Continuous detection: synthetic signal generation, sliding windows, event matching, latency, false alarms, and the NORMAL → SUSPECTED → CONFIRMED state path.
- The project does not calculate regulatory Pst or claim compliance with Ecuadorian or Peruvian power-quality regulations.
- The earlier 630-record waveform set was unavailable; its hashes cannot reconstruct missing samples. The nine MAT fixtures remain references; dataset v2 is a separate MATLAB generation.
- MQTT, broker, ESP32, Wokwi, Flutter, networking, and mobile notifications are outside this phase.
