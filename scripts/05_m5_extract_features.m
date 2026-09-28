%% M5: common benchmark interface; extract identical-record feature tables
clear; clc; startup;
cfg=legacy.defaultConfig(); cfg=legacy.loadSelectedConfig(cfg); rng(cfg.seed,'twister');
for k=1:numel(cfg.methods)
    method=string(cfg.methods{k});
    fprintf('\n=== M5 %s ===\n',method);
    F=legacy.buildFeatureTable(method,cfg); %#ok<NASGU>
end
outs=cellfun(@(m) ['results/features/' lower(m) '_features.csv'],cfg.methods,'UniformOutput',false);
legacy.makeManifest('05_m5_extract_features',cfg,outs,struct('methods',{cfg.methods}));
fprintf('M5_COMPLETE: common feature tables written.\n');
