function summary=run_six_model_streambench()
%RUN_SIX_MODEL_STREAMBENCH Refit heavy RF finalists; reuse frozen light SVM finalists.
cfg=eba.config();pool=gcp('nocreate');if isempty(pool)
    cluster=parcluster('local');cluster.NumWorkers=8;pool=parpool(cluster,4);
end
assert(pool.NumWorkers==4,'eba:SixModelWorkers','Heavy transforms use the empirically faster four-worker pool.');
fprintf('SIX_MODEL_WORKERS workers=%d policy=4 physical cores; 8-worker A/B was slower\n',pool.NumWorkers);
[status,sha]=system('git rev-parse HEAD');assert(status==0);sha=strtrim(sha);
[~,dirty]=system('git status --porcelain --untracked-files=normal');
assert(isempty(strtrim(dirty)),'eba:SixModelSource','A clean committed source tree is required.');
heavy=load(fullfile(cfg.output,'rf_stream_development.mat'),'candidateSets','summary');
assert(isequal(string(heavy.summary.method(:)),["FFT";"ST";"CWT"]), ...
    'eba:SixModelHeavy','The RF track must contain the three fixed 12-class offline leaders.');
light=load(fullfile(cfg.output,'reselection_stream_full_development.mat'),'models','reports','retained','summary','schedules');
lightMethods=["FFT","STFT","DWT"];
eba.requireCandidateCoverage(lightMethods,string(light.summary.method),'Retained light stream candidates');
assert(numel(light.schedules)==6048 && height(light.summary)==3,'eba:SixModelValidation', ...
    'The source validation package must contain 6,048 schedules and three light models.');
% One paired 20 dB realization per independent validation family bounds heavy DSP cost.
scheduleIds=2:7:numel(light.schedules);schedules=light.schedules(scheduleIds);
familyIds=string(cellfun(@(s) s.family_ids(1),schedules,'UniformOutput',false));
assert(numel(schedules)==864 && all(cellfun(@(s) s.snr_db==20 && s.noise_realization==1,schedules)) && ...
    numel(unique(familyIds))==864,'eba:SixModelValidation', ...
    'The common temporal workload must have one 20 dB schedule per independent family.');
F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);
[~,cal]=eba.subsetFamilies(F,max(cfg.learning_train_families_per_cell), ...
    cfg.families_per_cell/20*cfg.split_per_block.validation);
fitFamilies=unique(F.family_id(F.split=="train" & ~ismember(F.family_id,cal)));
calFamilies=unique(F.family_id(F.split=="train" & ismember(F.family_id,cal)));
assert(isempty(intersect(fitFamilies,calFamilies)) && ~any(F.split=="test"), ...
    'eba:SixModelLeakage','RF fit/calibration families overlap or use test.');
fullHash=eba.hash(jsonencode(table2struct(F)));
fitFamilies=unique(F.family_id(F.split=="train" & ~ismember(F.family_id,cal)));
calFamilies=unique(F.family_id(F.split=="train" & ismember(F.family_id,cal)));
folder=fullfile(cfg.output,'six_model_stream');if ~isfolder(folder),mkdir(folder);end
rows=cell(6,1);artifacts=strings(0,1);outIndex=0;
% Re-evaluate light finalists on the same 20 dB schedule for every family.
for method=lightMethods
    m=find(string(light.summary.method)==method);outIndex=outIndex+1;
    model=light.models{m};retained=light.retained{m};settings=retained.settings;
    settings.model_version=model.model_version;settings.git_commit=model.training_git_commit;
    modelPath=fullfile(cfg.output,'stream_models',"reselection_stream_full_"+lower(method)+".mat");
    saved=load(modelPath,'model');assert(string(model.kind)=="SVM" && isequaln(model.fitted,saved.model.fitted));
    predictions=cell(size(schedules));
    fprintf('SIX_MODEL_SVM_VALIDATION_START method=%s sequences=%d workers=%d\n',method,numel(schedules),pool.NumWorkers);
    parfor i=1:numel(schedules)
        predictions{i}=eba.streamPredictions(schedules{i},model,cfg,modelPath,true);
    end
    [report,details]=eba.evaluateStreamEvidence(schedules,predictions,settings,cfg);
    report.method=method;report.classifier="SVM";report.window_cycles=model.window_cycles;
    report.hop_samples=model.hop_samples;report.n_validation_families=864;
    report.dataset_hash=fullHash;report.noise_snr_db=20;report.noise_realization=1;report.evaluation_commit=sha;
    report.evaluation_workers=pool.NumWorkers;
    reportPath=fullfile(folder,"validation_svm_"+lower(method)+".json");
    detailsPath=fullfile(folder,"details_svm_"+lower(method)+".mat");
    eba.json(reportPath,report);save(detailsPath,'details','-v7.3');
    row=makeRow(model,report,modelPath,"SVM",cfg);row.offline_macro_f1=offlineScore("SVM",method,cfg);
    row.training_commit=string(model.training_git_commit);rows{outIndex}=row;
    artifacts=[artifacts;string(modelPath);string(reportPath);string(detailsPath)]; %#ok<AGROW>
end
% Refit the RF candidates on every accepted training family, reserving calibration families.
for m=1:numel(heavy.candidateSets)
    parent=heavy.candidateSets{m};old=parent.model;N=old.window_samples;
    modelPath=fullfile(folder,"model_rf_"+lower(old.method)+".mat");
    validationPath=fullfile(folder,"validation_rf_"+lower(old.method)+".json");
    detailsPath=fullfile(folder,"details_rf_"+lower(old.method)+".mat");
    [model,report,resumed]=resumeRF(modelPath,validationPath,detailsPath,old,fullHash,fitFamilies,calFamilies);
    if resumed
        outIndex=outIndex+1;row=makeRow(model,report,modelPath,"RF",cfg);
        row.offline_macro_f1=offlineScore("RF",model.method,cfg);row.training_commit=string(model.training_git_commit);
        rows{outIndex}=row;artifacts=[artifacts;string(modelPath);string(validationPath);string(detailsPath)]; %#ok<AGROW>
        fprintf('SIX_MODEL_RF_VALIDATION_REUSED method=%s eventF1=%.6f source_commit=%s\n', ...
            model.method,report.f1,model.training_git_commit);continue;
    end
    [X,P,info]=eba.windowData(F,old.method,old.parameters,N,cfg);
    fitRows=P.split=="train" & ~ismember(P.family_id,cal);
    calRows=P.split=="train" & ismember(P.family_id,cal);
    model=eba.fit(X(fitRows,:),P.class_id(fitRows),cfg,'RF',old.hyperparameters);
    model=eba.calibrate(model,X(calRows,:),P.class_id(calRows),P.family_id(calRows));
    model.method=old.method;model.parameters=old.parameters;model.window_samples=N;
    model.window_cycles=old.window_cycles;model.hop_samples=old.hop_samples;
    model.model_version="stream-full-rf-"+lower(old.method)+"-"+model.window_cycles;
    model.training_family_ids=unique(P.family_id(fitRows));model.calibration_family_ids=unique(P.family_id(calRows));
    model.training_dataset_hash=info.family_hash;model.training_git_commit=sha;
    eba.saveModel(modelPath,model);
    settings=parent.settings;settings.model_version=model.model_version;settings.git_commit=sha;
    settings.method_version=cfg.method_version;settings.dataset_version=cfg.dataset_version;
    settings.sequence_id="six_model_"+lower(model.method);
    predictions=cell(size(schedules));
    fprintf('SIX_MODEL_RF_VALIDATION_START method=%s sequences=%d workers=%d windows=%d hop=%d\n', ...
        model.method,numel(schedules),pool.NumWorkers,N,model.hop_samples);
    parfor i=1:numel(schedules)
        predictions{i}=eba.streamPredictions(schedules{i},model,cfg,modelPath,true);
        if mod(i,100)==0 || i==numel(schedules)
            fprintf('SIX_MODEL_RF_VALIDATION method=%s sequence_index=%d/%d\n',model.method,i,numel(schedules));
        end
    end
    [report,details]=eba.evaluateStreamEvidence(schedules,predictions,settings,cfg);
    report.method=model.method;report.classifier="RF";report.window_cycles=model.window_cycles;
    report.hop_samples=model.hop_samples;report.n_validation_families=numel(unique(F.family_id(F.split=="validation")));
    report.dataset_hash=fullHash;report.fit_family_count=numel(model.training_family_ids);
    report.calibration_family_count=numel(model.calibration_family_ids);
    report.noise_snr_db=20;report.noise_realization=1;report.evaluation_commit=sha;
    report.evaluation_workers=pool.NumWorkers;
    eba.json(validationPath,report);save(detailsPath,'details','-v7.3');
    outIndex=outIndex+1;row=makeRow(model,report,modelPath,"RF",cfg);
    row.offline_macro_f1=offlineScore("RF",model.method,cfg);row.training_commit=sha;rows{outIndex}=row;
    artifacts=[artifacts;string(modelPath);string(validationPath);string(detailsPath)]; %#ok<AGROW>
    fprintf('SIX_MODEL_RF_VALIDATION_DONE method=%s eventF1=%.6f falsePerMin=%.4f matched=%d of %d\n', ...
        model.method,report.f1,report.false_alarms_per_minute,report.n_matched_events,report.n_true_events);
end
summary=vertcat(rows{:});
assert(height(summary)==6 && isequal(sort(summary.classifier),["RF";"RF";"RF";"SVM";"SVM";"SVM"]), ...
    'eba:SixModelCoverage','The combined benchmark must retain three SVM and three RF candidates.');
summary.complete=isfinite(summary.event_f1)&isfinite(summary.event_f1_ci_low)& ...
    isfinite(summary.false_alarms_per_minute)&isfinite(summary.matched_latency_s);
assert(all(summary.complete),'eba:SixModelCoverage','Every candidate must have complete family-level validation.');
csv=fullfile(folder,'six_model_stream_validation.csv');writetable(summary,csv);
manifest=eba.manifest('six_model_stream_validation',cfg,struct('scope','six matched validation pipelines; one paired 20 dB realization per each of 864 independent families; test not accessed', ...
    'candidates',summary(:,{'method','classifier','window_cycles','hop_samples'}), ...
    'heavy_track_rule','Top three RF by 12-class validation Macro F1; offline p95 latency measured and reported but not an exclusion gate', ...
    'light_track','Previously retained FFT/STFT/DWT SVM candidates', ...
    'cost_policy','All six candidates retained irrespective of RTF; latency, p95, p99, memory and size are reported as Pareto outcomes', ...
    'validation_sequences',numel(schedules),'validation_families',864,'noise_snr_db',20, ...
    'noise_realization',1,'validation_workers',pool.NumWorkers, ...
    'worker_policy','Four process workers beat eight on matched ST and CWT stream microbenchmarks', ...
    'test_accessed',false),[artifacts;string(csv)]);
fprintf('SIX_MODEL_STREAMBENCH_PASS candidates=%d test_accessed=0 dataset_hash=%s\n',height(summary),fullHash);
end

function row=makeRow(model,R,path,classifier,cfg)
D=dir(path);row=table(string(model.method),string(classifier),model.window_cycles,model.hop_samples, ...
    R.precision,R.precision_ci_low,R.precision_ci_high,R.recall,R.recall_ci_low,R.recall_ci_high, ...
    R.f1,R.f1_ci_low,R.f1_ci_high,R.missed_event_rate,R.missed_event_rate_ci_low, ...
    R.missed_event_rate_ci_high,R.false_alarms_per_minute,R.false_alarms_per_minute_ci_low, ...
    R.false_alarms_per_minute_ci_high,R.mean_iou,R.mean_iou_ci_low,R.mean_iou_ci_high, ...
    R.mean_latency_s,R.mean_latency_s_ci_low,R.mean_latency_s_ci_high, ...
    R.mean_absolute_start_error_s,R.mean_absolute_start_error_s_ci_low,R.mean_absolute_start_error_s_ci_high, ...
    R.mean_absolute_end_error_s,R.mean_absolute_end_error_s_ci_low,R.mean_absolute_end_error_s_ci_high, ...
    NaN,NaN,NaN,D.bytes,model.training_time_s,numel(model.training_family_ids), ...
    'VariableNames',{'method','classifier','window_cycles','hop_samples','event_precision','precision_ci_low', ...
    'precision_ci_high','event_recall','recall_ci_low','recall_ci_high','event_f1','event_f1_ci_low','event_f1_ci_high', ...
    'missed_event_rate','missed_ci_low','missed_ci_high','false_alarms_per_minute','false_alarms_ci_low', ...
    'false_alarms_ci_high','mean_iou','iou_ci_low','iou_ci_high','matched_latency_s','latency_ci_low','latency_ci_high', ...
    'start_error_s','start_error_ci_low','start_error_ci_high','end_error_s','end_error_ci_low','end_error_ci_high', ...
    'runtime_p95_s','stream_RTF_p95','peak_process_RSS_bytes','model_bytes','fit_time_s','fit_families'});
if classifier=="SVM",runtimePath=fullfile(cfg.output,"runtime_reselection_stream_"+lower(string(model.method))+".json");
else,runtimePath=fullfile(cfg.output,'six_model_stream',"runtime_rf_"+lower(string(model.method))+".json");end
if isfile(runtimePath)
    run=jsondecode(fileread(runtimePath));row.runtime_p95_s=run.total_p95_s;
    row.stream_RTF_p95=run.streaming_real_time_factor_p95;row.peak_process_RSS_bytes=run.peak_process_RSS_bytes;
end
end

function value=offlineScore(classifier,method,cfg)
if classifier=="SVM",name='combined_validation_svm_metrics.csv';else,name='combined_validation_rf_metrics.csv';end
T=readtable(fullfile(cfg.output,name),'TextType','string');ix=T.method==string(method);
assert(nnz(ix)==1,'eba:SixModelOffline','Offline score missing or duplicated.');value=T.macro_f1(ix);
end
function [model,report,ok]=resumeRF(modelPath,reportPath,detailsPath,parent,datasetHash,fitFamilies,calFamilies)
model=[];report=[];ok=false;
if ~isfile(modelPath)||~isfile(reportPath)||~isfile(detailsPath),return;end
saved=load(modelPath,'model');model=saved.model;report=jsondecode(fileread(reportPath));
commit=string(model.training_git_commit);
if isempty(regexp(char(commit),'^[0-9a-f]{40}$','once')),return;end
files={'+eba/config.m','+eba/fit.m','+eba/calibrate.m','+eba/predict.m','+eba/features.m', ...
    '+eba/windowData.m','+eba/record.m','+eba/waveform.m','+eba/noise.m','+eba/streamPredictions.m', ...
    '+eba/continuousSignal.m','+eba/continuousSchedule.m','+eba/stateStep.m','+eba/replayWindows.m', ...
    '+eba/evaluateStreamEvidence.m','+eba/eventMetrics.m','+eba/severity.m','config/research_v2.json'};
[status,~]=system(sprintf('git diff --quiet %s HEAD -- %s',char(commit),strjoin(files,' ')));
ok=status==0 && string(model.kind)=="RF" && string(model.method)==string(parent.method) && ...
    isequaln(model.parameters,parent.parameters) && model.window_samples==parent.window_samples && ...
    model.window_cycles==parent.window_cycles && model.hop_samples==parent.hop_samples && ...
    string(model.training_dataset_hash)==string(datasetHash) && ...
    isequal(string(model.training_family_ids(:)),string(fitFamilies(:))) && ...
    isequal(string(model.calibration_family_ids(:)),string(calFamilies(:))) && ...
    string(report.method)==string(parent.method) && string(report.classifier)=="RF" && ...
    string(report.dataset_hash)==string(datasetHash) && report.n_sequences==864 && ...
    report.n_independent_clusters==864 && isfinite(report.f1) && isfinite(report.f1_ci_low);
end
