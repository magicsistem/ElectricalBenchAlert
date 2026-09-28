%% M0/M1 preflight: dataset contract and environment
clear; clc;
startup;
cfg = legacy.defaultConfig();
rng(cfg.seed,'twister');
report = legacy.validateDataset(cfg,true);
legacy.ensureDirs(cfg);
legacy.writeJson(fullfile(cfg.output.root,'preflight_dataset.json'),report);
legacy.writeJson(fullfile(cfg.output.root,'config_effective.json'),cfg);
manifest = legacy.makeManifest('00_preflight',cfg, ...
    {'results/preflight_dataset.json','results/config_effective.json'},report);
assert(report.ok,'Dataset preflight failed. Inspect results/preflight_dataset.json');
assert(exist('wavedec','file')==2,'Wavelet Toolbox is required for DWT.');
assert(exist('cwtfilterbank','file')==2,'Wavelet Toolbox is required for CWT.');
assert(exist('fitcecoc','file')==2,'Statistics and Machine Learning Toolbox is required for M6.');
fprintf('PREFLIGHT_OK: records=%d families=%d classes=%d\n', ...
    report.n_records,report.n_families,report.n_classes);
