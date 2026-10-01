function summary=run_stream_refit(mode)
%RUN_STREAM_REFIT Full accepted training population, held validation and frozen refined settings.
if nargin<1,mode="legacy";end
mode=string(mode);assert(isscalar(mode)&&any(mode==["legacy","reselection"]),'eba:StreamRefitMode','Unknown refit mode.');
cfg=eba.config();acceptance=readtable(fullfile(cfg.output,'development_size_acceptance.csv'));
methods=["FFT","STFT","DWT","CWT","ST"];
assert(height(acceptance)==5 && all(acceptance.accepted),'eba:DatasetAcceptance','All five learning-curve gates must pass before stream refitting.');
pool=gcp('nocreate');
if isempty(pool)
    cluster=parcluster('local');requested=8;
    try,cluster.NumWorkers=requested;pool=parpool(cluster,requested);catch,pool=parpool(cluster,min(4,cluster.NumWorkers));end
end
fprintf('STREAM_REFIT_PARALLEL_POOL workers=%d requested_max=8\n',pool.NumWorkers);
F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);
[~,cal]=eba.subsetFamilies(F,max(cfg.learning_train_families_per_cell),cfg.families_per_cell/20*cfg.split_per_block.validation);
if mode=="reselection",statePath=fullfile(cfg.output,'reselection_state_refinement.mat');prefix="reselection_stream_full";
else,statePath=fullfile(cfg.output,'state_refinement.mat');prefix="stream_full";end
R=load(statePath,'retained');
present=~cellfun(@isempty,R.retained);
assert(numel(R.retained)==numel(methods) && any(present), ...
    'eba:StreamCandidateSet','Refinement artifact has an invalid candidate layout.');
candidateMethods=string(cellfun(@(q) q.model.method,R.retained(present),'UniformOutput',false));
assert(numel(unique(candidateMethods))==numel(candidateMethods) && ...
    all(ismember(candidateMethods,methods)), ...
    'eba:StreamCandidateSet','Refinement contains duplicate or unknown methods.');
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
assert(k==numel(schedules));[~,sha]=system('git rev-parse HEAD');sha=strtrim(sha);
expectedDatasetHash=eba.hash(jsonencode(table2struct(F)));
fitFamilies=unique(F.family_id(F.split=="train" & ~ismember(F.family_id,cal)));
calibrationFamilies=unique(F.family_id(F.split=="train" & ismember(F.family_id,cal)));
for m=1:numel(R.retained)
    if isempty(R.retained{m}),continue;end
    chosen=R.retained{m};parent=chosen.model;
    modelPath=fullfile(folder,prefix+"_"+lower(parent.method)+".mat");
    reportPath=fullfile(cfg.output,prefix+"_validation_"+lower(parent.method)+".json");
    if isfile(modelPath)
        saved=load(modelPath,'model');model=saved.model;
        validateResumeModel(model,parent,fitFamilies,calibrationFamilies,expectedDatasetHash,sha,cfg);
    else
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
        model.training_dataset_hash=info.family_hash;model.training_git_commit=sha;
        eba.saveModel(modelPath,model);
    end
    settings=chosen.settings;settings.model_version=model.model_version;settings.git_commit=strtrim(sha);
    if isfile(reportPath)
        report=jsondecode(fileread(reportPath));detail=[];
        stateInfo=dir(statePath);reportInfo=dir(reportPath);
        assert(report.n_sequences==numel(schedules) && report.n_independent_clusters==height(V) && ...
            report.n_window_predictions>0 && reportInfo.datenum>=stateInfo.datenum, ...
            'eba:ResumeValidation','Existing report does not cover this candidate and complete validation workload.');
        rtf=NaN;
        fprintf('STREAM_REFIT_REUSE method=%s source_commit=%s full_sequences=%d\n',model.method,model.training_git_commit,report.n_sequences);
    else
        predictions=cell(size(schedules));
        parfor i=1:numel(schedules)
            predictions{i}=eba.streamPredictions(schedules{i},model,cfg,modelPath,true);
            if mod(i,500)==0 || i==numel(schedules),fprintf('FULL_STREAM_VALIDATION %s sequence_index=%d/%d\n',model.method,i,numel(schedules));end
        end
        [report,detail]=eba.evaluateStreamEvidence(schedules,predictions,settings,cfg);
        rtf=NaN;eba.json(reportPath,report);
    end
    % Matched fresh-session runtime, not batched validation timing, gates RTF.
    bytes=dir(modelPath);eligible=isfinite(report.mean_latency_s) && report.n_matched_events>0;
    rows{end+1}=table(model.method,model.window_cycles,model.hop_samples,report.f1,report.false_alarms_per_minute, ...
        report.mean_latency_s,rtf,bytes.bytes,eligible,numel(model.training_family_ids),report.n_independent_clusters, ...
        'VariableNames',{'method','window_cycles','hop_samples','event_f1','false_alarms_per_minute', ...
        'matched_latency_s','exploratory_stream_RTF_p95','model_bytes','eligible','n_fit_families','n_validation_clusters'}); %#ok<AGROW>
    models{m}=model;reports{m}=report;details{m}=detail;
    chosen.model=model;chosen.settings=settings;chosen.full_validation_report=report;R.retained{m}=chosen;
    artifacts=[artifacts;string(modelPath);string(reportPath)]; %#ok<AGROW>
    fprintf('STREAM_REFIT_COMPLETE method=%s event_f1=%.6g eligible=%d\n',model.method,report.f1,eligible);
end
summary=vertcat(rows{:});retained=R.retained;
eba.requireCandidateCoverage(candidateMethods,string(summary.method),'Full stream validation');
path=fullfile(cfg.output,prefix+"_development.mat");save(path,'models','reports','details','retained','schedules','summary','-v7.3');
summaryPath=fullfile(cfg.output,prefix+"_validation.csv");writetable(summary,summaryPath);artifacts=[artifacts;string(path);string(summaryPath)];
manifestId=prefix+"_development";
eba.manifest(manifestId,cfg,struct('scope','all accepted train families; held validation only; no test access', ...
    'methods',summary.method,'classifier','SVM', ...
    'parameters',{cellfun(@(q) q.parameters,models(~cellfun(@isempty,models)),'UniformOutput',false)}, ...
    'hyperparameters',{cellfun(@(q) q.hyperparameters,models(~cellfun(@isempty,models)),'UniformOutput',false)}, ...
    'solver_configuration',model.solver_configuration,'validation_snrs',levels,'noise_realizations',cfg.noise_realizations,'n_validation_families',height(V), ...
    'n_validation_derived_sequences',numel(schedules),'n_models',height(summary), ...
    'feasibility_policy','finite event metrics with at least one matched event; measured matched fresh-session runtime p95 compute/hop<=1 is enforced by the final selector; false alarms/minute reported without a fixed cap', ...
    'selection_policy','refined settings held; full validation failure returns to development; no test access'),artifacts);
assert(any(summary.eligible),'eba:StreamFeasibility','No full-data stream pipeline passed computational validation feasibility.');
fprintf('STREAM_FULL_DEVELOPMENT_PASS models=%d eligible=%d test_accessed=0\n',height(summary),sum(summary.eligible));
end

function validateResumeModel(model,parent,fitFamilies,calibrationFamilies,datasetHash,currentCommit,cfg)
trainingCommit=string(model.training_git_commit);
assert(isscalar(trainingCommit) && ~isempty(regexp(trainingCommit,'^[0-9a-f]{40}$','once')), ...
    'eba:ResumeModel','Existing model has no valid source commit.');
scientificFiles=['+eba/config.m +eba/fit.m +eba/calibrate.m +eba/predict.m +eba/features.m ' ...
    '+eba/windowData.m +eba/record.m +eba/waveform.m +eba/noise.m +eba/streamPredictions.m ' ...
    '+eba/continuousSignal.m +eba/continuousSchedule.m +eba/stateStep.m +eba/replayWindows.m ' ...
    '+eba/evaluateStreamEvidence.m +eba/eventMetrics.m +eba/severity.m config/research_v2.json'];
[status,~]=system(sprintf('git diff --quiet %s HEAD -- %s',char(trainingCommit),scientificFiles));
assert(status==0 && string(model.method)==string(parent.method) && isequaln(model.parameters,parent.parameters) && ...
    model.window_samples==parent.window_samples && model.window_cycles==parent.window_cycles && ...
    model.hop_samples==parent.hop_samples && string(model.training_dataset_hash)==string(datasetHash) && ...
    isequal(string(model.training_family_ids(:)),string(fitFamilies(:))) && ...
    isequal(string(model.calibration_family_ids(:)),string(calibrationFamilies(:))), ...
    'eba:ResumeModel','Existing model does not match this dataset, training split, candidate or unchanged scientific source.');
assert(isa(cfg.Fs,'double') && strlength(currentCommit)==40,'eba:ResumeModel','Current source provenance is invalid.');
end
