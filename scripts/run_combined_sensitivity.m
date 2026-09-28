function summary=run_combined_sensitivity()
%RUN_COMBINED_SENSITIVITY Twelve closed classes under the core selected DSP/hyperparameter protocol.
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);
core=F(F.class_id<=cfg.primary_class_count,:);combined=F(F.class_id>cfg.primary_class_count,:);
S=load(fullfile(cfg.output,'development_transform_selection.mat'),'selected','methods');
D=load(fullfile(cfg.output,'development_classifiers.mat'),'models');[~,cal]=eba.subsetFamilies(F,14,3);
models=cell(5,2);predictions=cell(5,2);validation=[];artifacts=strings(0,1);
for m=1:5
    [Xcore,Pcore]=eba.extract(core,S.methods(m),S.selected{m},cfg,'development');
    [Xcombined,Pcombined]=eba.extract(combined,S.methods(m),S.selected{m},cfg,'development');
    X=[Xcore;Xcombined];P=[Pcore;Pcombined];fit=P.split=="train" & ~ismember(P.family_id,cal);
    calibration=P.split=="train" & ismember(P.family_id,cal);val=P.split=="validation";
    if isempty(validation),validation=P(val,:);else,assert(isequal(validation,P(val,:)),'eba:PairedRecords','Composite sensitivity lost record pairing.');end
    for k=1:2
        model=eba.fit(X(fit,:),P.class_id(fit),cfg,D.models{m,k}.kind,D.models{m,k}.hyperparameters);
        model=eba.calibrate(model,X(calibration,:),P.class_id(calibration),P.family_id(calibration));
        model.method=S.methods(m);model.parameters=S.selected{m};model.training_family_ids=unique(P.family_id(fit));
        model.model_version="combined-development-"+lower(model.method)+"-"+lower(model.kind);
        [before,~,~,scoresBefore]=eba.predict(model,X(val,:));model.fitted=compact(model.fitted);
        [after,~,~,scoresAfter]=eba.predict(model,X(val,:));
        assert(isequal(before,after) && isequal(scoresBefore,scoresAfter),'eba:CompactionPrediction','Composite compaction changed inference.');
        models{m,k}=model;predictions{m,k}=after;
        path=fullfile(cfg.output,"combined_model_"+lower(model.method)+"_"+lower(model.kind)+".mat");save(path,'model','-v7.3');artifacts(end+1)=path; %#ok<AGROW>
        fprintf('COMBINED_SENSITIVITY_TRAINED method=%s classifier=%s classes=12 fit_families=%d\n',model.method,model.kind,numel(model.training_family_ids));
    end
end
for k=1:2
    kinds=["SVM","RF"];kind=kinds(k);statCfg=cfg;statCfg.comparison_family="closed_composite_"+lower(kind)+"_secondary";
    [summary,pairs,noise,details]=eba.familyStats(validation,horzcat(predictions{:,k}),S.methods,statCfg);
    prefix="combined_validation_"+lower(kind);paths=[fullfile(cfg.output,prefix+"_metrics.csv");fullfile(cfg.output,prefix+"_paired.csv");fullfile(cfg.output,prefix+"_snr.csv");fullfile(cfg.output,prefix+"_statistics.mat")];
    writetable(summary,paths(1));writetable(pairs,paths(2));writetable(noise,paths(3));save(paths(4),'summary','pairs','noise','details','-v7.3');artifacts=[artifacts;paths]; %#ok<AGROW>
end
path=fullfile(cfg.output,'combined_classifiers.mat');save(path,'models','predictions','validation','-v7.3');artifacts(end+1)=path;
eba.manifest('combined_development_sensitivity',cfg,struct('scope','closed twelve-class single-label sensitivity; component arrays are descriptive; no test access', ...
    'methods',S.methods,'classifier_tracks',["SVM","RF"],'parameters',{S.selected}, ...
    'hyperparameter_policy','core selected parameters held fixed; no further search', ...
    'dataset_hash',eba.hash(jsonencode(table2struct(F))),'split_hash',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'})))), ...
    'n_families',height(F),'records_per_family',19, ...
    'distribution_limit','Composite component severity ranks and design strata are coupled by the declared generator; crossed component severities are outside this finite distribution.'),artifacts);
fprintf('COMBINED_DEVELOPMENT_SENSITIVITY_COMPLETE models=10 test_accessed=0\n');
end
