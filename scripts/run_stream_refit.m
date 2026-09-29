function summary=run_stream_refit()
%RUN_STREAM_REFIT Full accepted training population, held validation and frozen refined settings.
cfg=eba.config();acceptance=readtable(fullfile(cfg.output,'development_size_acceptance.csv'));
assert(height(acceptance)==5 && all(acceptance.accepted),'eba:DatasetAcceptance','All five learning-curve gates must pass before stream refitting.');
F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);
[~,cal]=eba.subsetFamilies(F,max(cfg.learning_train_families_per_cell),cfg.families_per_cell/20*cfg.split_per_block.validation);
R=load(fullfile(cfg.output,'state_refinement.mat'),'retained');
folder=fullfile(cfg.output,'stream_models');rows=cell(0,1);models=cell(size(R.retained));reports=cell(size(models));details=cell(size(models));artifacts=strings(0,1);
V=F(F.split=="validation",:);levels=[Inf 20 5];schedules=cell(height(V)*(1+2*cfg.noise_realizations),1);k=0;
for i=1:height(V)
    for z=1:numel(levels)
        count=cfg.noise_realizations;if z==1,count=1;end
        for realization=1:count
            k=k+1;id="full_validation_"+V.family_id(i)+"_snr"+levels(z)+"_r"+realization;
            schedules{k}=eba.continuousSchedule(V(i,:),cfg,levels(z),id,mod(cfg.stream_seed+double(V.family_seed(i)),2^32),"development",realization);
        end
    end
end
assert(k==numel(schedules));[~,sha]=system('git rev-parse HEAD');
for m=1:numel(R.retained)
    if isempty(R.retained{m}),continue;end
    chosen=R.retained{m};parent=chosen.model;
    [X,P,info]=eba.windowData(F,parent.method,parent.parameters,parent.window_samples,cfg);
    fit=P.split=="train" & ~ismember(P.family_id,cal);calibration=P.split=="train" & ismember(P.family_id,cal);val=P.split=="validation";
    model=eba.fit(X(fit,:),P.class_id(fit),cfg,'SVM',parent.hyperparameters);
    model=eba.calibrate(model,X(calibration,:),P.class_id(calibration),P.family_id(calibration));
    [before,c1,p1,s1]=eba.predict(model,X(val,:));model.fitted=compact(model.fitted);
    [after,c2,p2,s2]=eba.predict(model,X(val,:));
    assert(isequal(before,after) && isequal(c1,c2) && isequal(p1,p2) && isequal(s1,s2), ...
        'eba:CompactionPrediction','Stream compaction changed validation predictions or evidence.');
    model.method=parent.method;model.parameters=parent.parameters;model.window_samples=parent.window_samples;
    model.window_cycles=parent.window_cycles;model.hop_samples=parent.hop_samples;
    model.model_version="stream-full-development-"+lower(parent.method)+"-"+parent.window_cycles;
    model.training_family_ids=unique(P.family_id(fit));model.calibration_family_ids=unique(P.family_id(calibration));
    model.training_dataset_hash=info.family_hash;model.training_git_commit=strtrim(sha);
    modelPath=fullfile(folder,"full_"+lower(model.method)+".mat");eba.saveModel(modelPath,model);
    settings=chosen.settings;settings.model_version=model.model_version;settings.git_commit=strtrim(sha);
    predictions=cell(size(schedules));
    for i=1:numel(schedules)
        predictions{i}=eba.streamPredictions(schedules{i},model,cfg,modelPath,true);
        if mod(i,100)==0 || i==numel(schedules),fprintf('FULL_STREAM_VALIDATION %s sequences=%d/%d\n',model.method,i,numel(schedules));end
    end
    [report,detail]=eba.evaluateStreamEvidence(schedules,predictions,settings,cfg);
    % Full validation is a gate. Failed feasibility returns to development before opening test.
    rtf=quantile(detail.exploratory_inference_times_s,.95)/(model.hop_samples/cfg.Fs);
    bytes=dir(modelPath);eligible=report.false_alarms_per_minute<=1 && rtf<=1 && isfinite(report.mean_latency_s) && report.n_matched_events>0;
    rows{end+1}=table(model.method,model.window_cycles,model.hop_samples,report.f1,report.false_alarms_per_minute, ...
        report.mean_latency_s,rtf,bytes.bytes,eligible,numel(model.training_family_ids),report.n_independent_clusters, ...
        'VariableNames',{'method','window_cycles','hop_samples','event_f1','false_alarms_per_minute', ...
        'matched_latency_s','exploratory_stream_RTF_p95','model_bytes','eligible','n_fit_families','n_validation_clusters'}); %#ok<AGROW>
    models{m}=model;reports{m}=report;details{m}=detail;
    chosen.model=model;chosen.settings=settings;chosen.full_validation_report=report;R.retained{m}=chosen;
    reportPath=fullfile(cfg.output,"stream_full_validation_"+lower(model.method)+".json");eba.json(reportPath,report);
    artifacts=[artifacts;string(modelPath);string(reportPath)]; %#ok<AGROW>
    fprintf('STREAM_REFIT_COMPLETE method=%s event_f1=%.6g eligible=%d\n',model.method,report.f1,eligible);
end
summary=vertcat(rows{:});retained=R.retained;
path=fullfile(cfg.output,'stream_full_development.mat');save(path,'models','reports','details','retained','schedules','summary','-v7.3');
summaryPath=fullfile(cfg.output,'stream_full_validation.csv');writetable(summary,summaryPath);artifacts=[artifacts;string(path);string(summaryPath)];
eba.manifest('stream_full_development',cfg,struct('scope','all accepted train families; held validation only; no test access', ...
    'methods',summary.method,'classifier','SVM', ...
    'parameters',{cellfun(@(q) q.parameters,models(~cellfun(@isempty,models)),'UniformOutput',false)}, ...
    'hyperparameters',{cellfun(@(q) q.hyperparameters,models(~cellfun(@isempty,models)),'UniformOutput',false)}, ...
    'validation_snrs',levels,'noise_realizations',cfg.noise_realizations,'n_validation_families',height(V), ...
    'n_validation_derived_sequences',numel(schedules),'n_models',height(summary), ...
    'feasibility_policy','exploratory p95 compute/hop<=1 and all-unmatched-confirmations/normal-minute<=1; final matched fresh-session runtime also required', ...
    'selection_policy','refined settings held; full validation failure returns to development; no test access'),artifacts);
assert(any(summary.eligible),'eba:StreamFeasibility','No full-data stream pipeline passed validation feasibility.');
fprintf('STREAM_FULL_DEVELOPMENT_PASS models=%d eligible=%d test_accessed=0\n',height(summary),sum(summary.eligible));
end
