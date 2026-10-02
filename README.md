# ElectricalBenchAlert

MATLAB benchmark of six continuous power quality event detection pipelines. This checkout contains the frozen validation run and only the source needed to inspect, verify, and reproduce it.

## Frozen run

The benchmark pairs FFT/STFT/DWT with SVM and FFT/ST/CWT with Random Forest across the same 864 validation families, at 20 dB with one noise realization per family. The original test split was inspected in an earlier superseded phase, so these results are validation evidence, not a confirmatory test.

| Pipeline | Event F1 [95% CI] | Recall | False alarms/min | Detection latency | Compute p95 / hop | Process RSS | Model size |
|---|---:|---:|---:|---:|---:|---:|---:|
| FFT + SVM | 0.7093 [0.6800, 0.7379] | 0.5947 | 0.686 | 0.237 s | 12.8 ms / 100 ms (0.128) | 1.54 GB | 2.66 MB |
| STFT + SVM | 0.6926 [0.6625, 0.7220] | 0.5732 | 0.687 | 0.480 s | 19.1 ms / 125 ms (0.152) | 1.52 GB | 2.67 MB |
| DWT + SVM | 0.6364 [0.6029, 0.6687] | 0.5051 | 0.693 | 0.555 s | 17.3 ms / 250 ms (0.069) | 1.65 GB | 2.67 MB |
| FFT + RF | 0.7972 [0.7727, 0.8216] | 0.7942 | 1.651 | 0.228 s | 195.6 ms / 50 ms (3.912) | 2.09 GB | 72.43 MB |
| ST + RF | 0.7574 [0.7333, 0.7813] | 0.7551 | 1.997 | 0.357 s | 227.7 ms / 125 ms (1.821) | 2.11 GB | 73.61 MB |
| **CWT + RF** | **0.8031 [0.7784, 0.8270]** | 0.7210 | **0.624** | 0.468 s | **211.0 ms / 125 ms (1.688)** | 2.13 GB | 72.35 MB |

CWT-RF is selected by the predeclared rule: maximize the family-grouped bootstrap lower 95% Event F1 bound, then point F1, fewer false alarms, and lower detection latency. Latency and size do not exclude candidates. Paired uncertainty does not establish a significant Event F1 difference from FFT-RF: delta +0.0059 [−0.0171, +0.0289], Holm-adjusted p=0.5924. CWT-RF has higher precision and fewer false alarms; FFT-RF has higher recall and shorter detection latency.

The selected model is 72.35 MB. Its p95 processing time is 211 ms for a 125 ms hop (RTF 1.688), so it does not sustain real-time throughput on the measured laptop. That compute cost is accepted for this simulation benchmark and remains a deployment limitation. The deterministic confirmation example reaches NORMAL → SUSPECTED → CONFIRMED for a validation sag in 0.2665 s, with zero false alarms in that sequence; this checks integration, not generalization.

## Reproduce and verify

Requirements: MATLAB R2026b, Signal Processing Toolbox, Wavelet Toolbox, Statistics and Machine Learning Toolbox, and Parallel Computing Toolbox. The checked-in `results/v2` package contains the exact schedules, models, metrics, manifests, and demo outputs for this run.

From the repository root:

```sh
matlab -batch "disp(version); ver"
matlab -batch "startup; run_all_tests"
matlab -batch "startup; addpath('scripts'); verify_six_model_streambench; verify_six_model_selection"
matlab -batch "startup; addpath('scripts'); run_six_model_paired_events"
matlab -batch "startup; addpath('scripts'); run_selected_six_model_demo"
```

To rerun the six model validation and measurements, use a clean Git checkout with the bundled run inputs and execute:

```sh
matlab -batch "startup; addpath('scripts'); run_six_model_streambench"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('SVM','FFT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('SVM','STFT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('SVM','DWT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','FFT')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','ST')"
matlab -batch "startup; addpath('scripts'); run_six_model_runtime('RF','CWT')"
matlab -batch "startup; addpath('scripts'); run_six_model_selection; run_six_model_paired_events; verify_six_model_streambench; verify_six_model_selection; run_selected_six_model_demo"
```

Runtime results depend on hardware and are measured in fresh MATLAB processes with a shared signal, shared decision endpoints, two warmups, and 100 repetitions. The checked-in manifests retain the original environment and artifact hashes.
