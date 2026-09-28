%% M2: DWT candidate selection (train+validation only; test excluded)
clear; clc; startup;
cfg=legacy.defaultConfig(); rng(cfg.seed,'twister');
[selected,results]=legacy.selectDWT(cfg);
fprintf('\nM2_DWT_SELECTED: %s level %d | Fisher=%.6g | median=%.6g s\n', ...
    selected.wavelet,selected.level,selected.fisher_score,selected.median_runtime_s);
legacy.makeManifest('02_m2_dwt_select',cfg, ...
    {'results/dwt_selection.csv','results/dwt_selected.json','results/dwt_selection.mat'},selected);
