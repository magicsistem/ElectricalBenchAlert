%% M9: same-session computational benchmark
clear; clc; startup;
cfg=legacy.defaultConfig(); cfg=legacy.loadSelectedConfig(cfg); rng(cfg.seed,'twister'); legacy.ensureDirs(cfg);
R=legacy.benchmarkComplexity(cfg);
legacy.makeManifest('09_m9_complexity',cfg,{'results/metrics/complexity.csv'},struct('n_methods',height(R)));
disp(R);
