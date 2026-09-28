%% M6: lightweight classifier per DSP representation
clear; clc; startup;
cfg=legacy.defaultConfig(); cfg=legacy.loadSelectedConfig(cfg); rng(cfg.seed,'twister'); legacy.ensureDirs(cfg);
for k=1:numel(cfg.methods)
    method=upper(string(cfg.methods{k})); tag=lower(char(method));
    path=fullfile(cfg.output.features,[tag '_features.mat']);
    assert(isfile(path),'Missing %s. Run M5 first.',path);
    S=load(path,'F'); F=S.F;
    model=legacy.trainClassifier(F,cfg);
    save(fullfile(cfg.output.models,[tag '_classifier.mat']),'model','-v7.3');
    fprintf('M6 trained %s classifier on %d training rows / %d features.\n',method,sum(F.split=="train"),numel(model.feature_names));
end
legacy.makeManifest('06_m6_train_classifier',cfg,{'results/models/*_classifier.mat'},struct('classifier',cfg.classifier.type));
