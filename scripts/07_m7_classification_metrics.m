%% M7: validation/test classification metrics
clear; clc; startup;
cfg=legacy.defaultConfig(); cfg=legacy.loadSelectedConfig(cfg); rng(cfg.seed,'twister'); legacy.ensureDirs(cfg);
summaryRows={}; rr=0;
for k=1:numel(cfg.methods)
    method=upper(string(cfg.methods{k})); tag=lower(char(method));
    S=load(fullfile(cfg.output.features,[tag '_features.mat']),'F'); F=S.F;
    Mdl=load(fullfile(cfg.output.models,[tag '_classifier.mat']),'model'); model=Mdl.model;
    F.prediction=legacy.predictClassifier(model,F);
    writetable(F,fullfile(cfg.output.metrics,[tag '_predictions.csv']));
    for split=["validation","test"]
        P=F(F.split==split,:);
        met=legacy.classificationMetrics(P.label,P.prediction,model.classes);
        rr=rr+1; summaryRows(rr,:)={char(method),char(split),height(P),met.accuracy,met.macro_f1,met.weighted_f1,met.macro_precision,met.macro_recall,met.macro_specificity}; %#ok<SAGROW>
        writetable(met.per_class,fullfile(cfg.output.metrics,sprintf('%s_%s_per_class.csv',tag,split)));
        cm=array2table(met.confusion_matrix,'VariableNames',matlab.lang.makeValidName(cellstr(string(model.classes))));
        cm.actual_class=string(model.classes(:)); cm=movevars(cm,'actual_class','Before',1);
        writetable(cm,fullfile(cfg.output.metrics,sprintf('%s_%s_confusion.csv',tag,split)));
    end
end
R=cell2table(summaryRows,'VariableNames',{'method','split','n','accuracy','macro_f1','weighted_f1','macro_precision','macro_recall','macro_specificity'});
writetable(R,fullfile(cfg.output.metrics,'classification_summary.csv'));
legacy.makeManifest('07_m7_classification_metrics',cfg,{'results/metrics/classification_summary.csv','results/metrics/*_predictions.csv'},struct('status','provisional_current_dataset'));
disp(R);
