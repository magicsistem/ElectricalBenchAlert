function report=run_stream_development(stage)
%RUN_STREAM_DEVELOPMENT Family-held-out window and state selection, twelve closed classes.
if nargin<1,stage="all";end
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);
S=load(fullfile(cfg.output,'development_transform_selection.mat'),'selected','methods');
C=load(fullfile(cfg.output,'development_classifiers.mat'),'models');methods=S.methods;
[small,cal]=eba.subsetFamilies(F,3,1);validation=small(small.split=="validation",:);
% One independent event or 30-second normal exposure per family; paired clean/20dB sequences.
schedules=cell(height(validation),2);
for i=1:height(validation)
    for z=1:2
        levels=[Inf 20];id="validation_"+validation.family_id(i)+"_snr"+levels(z);
        schedules{i,z}=eba.continuousSchedule(validation(i,:),cfg,levels(z),id,mod(cfg.stream_seed+double(validation.family_seed(i)),2^32));
    end
end
modelFolder=fullfile(cfg.output,'stream_models');if ~isfolder(modelFolder),mkdir(modelFolder);end
sources={'+eba/windowData.m','+eba/fit.m','+eba/predict.m','+eba/calibrate.m','+eba/features.m', ...
    '+eba/windowParameters.m','+eba/record.m','+eba/waveform.m','+eba/noise.m','+eba/subsetFamilies.m'};
sourceHashes=cellfun(@(x) eba.hash(fullfile(cfg.root,x),'file'),sources,'UniformOutput',false);
windowSource=eba.hash(strjoin(sourceHashes,''));
familyHash=eba.hash(jsonencode(table2struct(small)));
if any(string(stage)==["all","windows"])
    rows=cell(5,numel(cfg.stream_window_cycles));models=cell(size(rows));
    for m=1:5
        for w=1:numel(cfg.stream_window_cycles)
            cycles=cfg.stream_window_cycles(w);N=round(cfg.Fs*cycles/cfg.nominal_frequency_hz);
            p=eba.windowParameters(methods(m),S.selected{m},N);
            modelPath=fullfile(modelFolder,"candidate_"+lower(methods(m))+"_"+cycles+".mat");
            signature=eba.hash(jsonencode(struct('families',familyHash,'parameters',p,'source',windowSource, ...
                'config',eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file'),'hyperparameters',C.models{m,1}.hyperparameters)));
            if isfile(modelPath)
                previous=load(modelPath,'model','candidate_row','candidate_signature');
                if isfield(previous,'candidate_signature') && strcmp(previous.candidate_signature,signature)
                    models{m,w}=previous.model;rows{m,w}=previous.candidate_row;
                    fprintf('STREAM_WINDOW_CHECKPOINT_REUSED %s cycles=%d\n',methods(m),cycles);continue;
                end
            end
            [X,P,info]=eba.windowData(small,methods(m),p,N,cfg);
            fit=P.split=="train" & ~ismember(P.family_id,cal);calmask=P.split=="train" & ismember(P.family_id,cal);val=P.split=="validation";
            model=eba.fit(X(fit,:),P.class_id(fit),cfg,'SVM',C.models{m,1}.hyperparameters);
            model=eba.calibrate(model,X(calmask,:),P.class_id(calmask),P.family_id(calmask));
            model.method=methods(m);model.parameters=p;model.window_samples=N;model.window_cycles=cycles;model.model_version="stream-development-"+lower(methods(m))+"-"+cycles;
            model.training_family_ids=unique(P.family_id(fit));model.calibration_family_ids=unique(P.family_id(calmask));
            prediction=eba.predict(model,X(val,:));metrics=eba.metrics(P.class_id(val),prediction,numel(cfg.classes));
            rows{m,w}=table(methods(m),cycles,N,metrics.macro_f1,median(info.feature_time_s),height(small),sum(fit), ...
                'VariableNames',{'method','window_cycles','window_samples','validation_window_macro_f1','feature_median_s','n_families','n_fit_windows'});
            models{m,w}=model;candidate_row=rows{m,w};candidate_signature=signature;
            save(modelPath,'model','candidate_row','candidate_signature','-v7.3');
            fprintf('STREAM_WINDOW_TRAIN %s cycles=%d validation_window_MacroF1=%.6f\n',methods(m),cycles,metrics.macro_f1);
        end
    end
    windowSummary=vertcat(rows{:});save(fullfile(cfg.output,'stream_window_development.mat'),'models','windowSummary','-v7.3');
    writetable(windowSummary,fullfile(cfg.output,'stream_window_development.csv'));
end
if any(string(stage)==["all","state"])
    W=load(fullfile(cfg.output,'stream_window_development.mat'),'models');
    % Prospective engineering grid: confidence x consecutive count; one-cycle union-support floor.
    [~,sha]=system('git rev-parse HEAD');settings=struct('threshold_on',.7,'threshold_off',.5,'min_windows',2, ...
        'min_evidence_s',1/60,'recovery_windows',2,'refractory_s',0,'classes',cfg.classes, ...
        'method_version',cfg.method_version,'model_version','development','dataset_version',cfg.dataset_version, ...
        'git_commit',strtrim(sha),'sequence_id','candidate','confidence_calibrated',true);
    statCfg=cfg;statCfg.temporal_bootstrap_replicates=0;records=cell(0,1);best=-Inf;chosen=[];
    for m=1:5
        for w=1:numel(cfg.stream_window_cycles)
            base=W.models{m,w};
            minimumHop=max(1,round(base.window_samples*min(cfg.stream_hop_fractions)));
            fineModel=base;fineModel.hop_samples=minimumHop;
            finePredictions=cell(size(schedules));
            for i=1:height(validation)
                for z=1:2,finePredictions{i,z}=predictSequence(schedules{i,z},fineModel,statCfg,true);end
            end
            for hopFraction=cfg.stream_hop_fractions(:).'
                model=base;model.hop_samples=max(1,round(model.window_samples*hopFraction));
                predictions=cell(size(schedules));
                for i=1:height(validation)
                    for z=1:2
                        fine=finePredictions{i,z};ends=model.window_samples:model.hop_samples:schedules{i,z}.n_samples;
                        [present,index]=ismember(ends,round(fine.window_end_s*cfg.Fs));
                        assert(all(present),'eba:StreamHop','Coarse hop does not share the fine-grid endpoints.');
                        predictions{i,z}=fine(index,:);
                    end
                end
                for threshold=[.5 .7 .9]
                    for persistence=[2 3 5]
                        for evidenceCycles=1
                            candidate=settings;candidate.threshold_on=threshold;candidate.threshold_off=max(.1,threshold-.2);
                            candidate.min_windows=persistence;candidate.min_evidence_s=evidenceCycles/60;
                            candidate.model_version=model.model_version;candidate.method_version=cfg.method_version;
                            values=zeros(2,5);
                            for z=1:2
                                gt=[];ed=[];exposure=table(strings(height(validation),1),zeros(height(validation),1), ...
                                    'VariableNames',{'sequence_id','normal_exposure_s'});exposure.family_id=validation.family_id;runtimes=[];
                                for i=1:height(validation)
                                    schedule=schedules{i,z};candidate.sequence_id=schedule.sequence_id;
                                    [estimated,timing]=replay(predictions{i,z},candidate);truth=schedule.events;
                                    if isempty(gt),gt=truth;ed=estimated;else,gt=[gt;truth];ed=[ed;estimated];end %#ok<AGROW>
                                    observedUntil=predictions{i,z}.window_end_s(end);
                                    normalExposure=observedUntil-sum(max(0,min(truth.end_s,observedUntil)-truth.start_s));
                                    exposure(i,:)={schedule.sequence_id,normalExposure,validation.family_id(i)};runtimes=[runtimes;timing]; %#ok<AGROW>
                                end
                                metrics=eba.eventMetrics(gt,ed,exposure,statCfg);
                                values(z,:)=[metrics.f1,metrics.false_alarms_per_minute,metrics.mean_latency_s, ...
                                    quantile(runtimes,.95)/(model.hop_samples/cfg.Fs),metrics.recall];
                            end
                            f1=mean(values(:,1));falseRate=max(values(:,2));latency=max(values(:,3));rtf=max(values(:,4));
                            records{end+1}=table(methods(m),model.window_cycles,hopFraction,threshold,persistence,evidenceCycles,f1,falseRate,latency,rtf, ...
                                'VariableNames',{'method','window_cycles','hop_fraction','threshold_on','min_windows','evidence_cycles', ...
                                'event_f1','false_alarms_per_minute','matched_latency_s','stream_RTF_p95'}); %#ok<AGROW>
                            % Hard feasibility bounds were declared before final test. Equal F1 breaks by latency then grid order.
                            eligible=falseRate<=1 && rtf<=1 && isfinite(latency);
                            if eligible && (f1>best+1e-12 || (abs(f1-best)<=1e-12 && latency<chosen.latency-1e-12))
                                best=f1;chosen=struct('method_index',m,'window_index',w,'hop_fraction',hopFraction, ...
                                    'settings',candidate,'model',model,'event_f1',f1,'latency',latency,'false_alarms_per_minute',falseRate,'rtf',rtf);
                            end
                        end
                    end
                end
            end
        end
    end
    selection=vertcat(records{:});writetable(selection,fullfile(cfg.output,'stream_state_selection.csv'));
    assert(~isempty(chosen),'eba:StreamFeasibility','No validation pipeline meets the frozen false-alarm/runtime feasibility bounds.');
    objectives=[selection.event_f1,-selection.false_alarms_per_minute,-selection.matched_latency_s,-selection.stream_RTF_p95];
    finite=all(isfinite(objectives),2);selection.pareto=false(height(selection),1);selection.pareto(finite)=eba.pareto(objectives(finite,:),ones(1,4));
    writetable(selection,fullfile(cfg.output,'stream_state_selection.csv'));save(fullfile(cfg.output,'stream_selected_development.mat'),'chosen','selection','-v7.3');
    eba.manifest('stream_validation_selection',cfg,struct('scope','validation only; clean and 20dB paired schedules', ...
        'selection_rule','false_alarms/min<=1 and p95 RTF<=1; maximum mean event F1; exact ties minimum matched latency then grid order', ...
        'n_pure_normal_families',sum(validation.class_id==1),'n_event_families',sum(validation.class_id~=1), ...
        'normal_duration_s',30,'normal_gap_s',2,'n_independent_families',height(validation),'n_noise_derivative_sequences',numel(schedules)), ...
        {fullfile(cfg.output,'stream_state_selection.csv'),fullfile(cfg.output,'stream_selected_development.mat')});
end
report=struct('stage',stage,'test_accessed',false);fprintf('STREAM_DEVELOPMENT_PASS stage=%s\n',stage);
end
function result=predictSequence(schedule,model,cfg,useCache)
if nargin<4,useCache=false;end
sources={'+eba/features.m','+eba/predict.m','+eba/severity.m','+eba/continuousSignal.m','+eba/waveform.m'};
digests=cellfun(@(x) eba.hash(fullfile(cfg.root,x),'file'),sources,'UniformOutput',false);
key=eba.hash(jsonencode(struct('schedule',schedule,'window',model.window_samples,'hop',model.hop_samples, ...
    'source_sha256',{digests},'model_sha256',eba.hash(fullfile(cfg.output,'stream_models', ...
    "candidate_"+lower(model.method)+"_"+model.window_cycles+".mat"),'file'))));
folder=fullfile(cfg.output,'stream_prediction_cache');if ~isfolder(folder),mkdir(folder);end
path=fullfile(folder,key+".mat");
if useCache && isfile(path),saved=load(path,'result','signature');assert(strcmp(saved.signature,key));result=saved.result;return;end
N=model.window_samples;ends=N:model.hop_samples:schedule.n_samples;
result=table('Size',[numel(ends) 9],'VariableTypes',repmat({'double'},1,9), ...
    'VariableNames',{'window_start_s','window_end_s','decision_time_s','class_id','confidence','feature_time_s','classification_time_s','voltage_rms_pu_min','severity_time_s'});
for w=1:numel(ends)
    idx=(ends(w)-N:ends(w)-1)';x=eba.continuousSignal(schedule,idx,cfg);
    timer=tic;v=eba.features(x,cfg.Fs,model.method,model.parameters);tf=toc(timer);
    timer=tic;[label,confidence]=eba.predict(model,v);tc=toc(timer);
    timer=tic;[~,physical]=eba.severity(x,cfg.classes(label),cfg.Fs);ts=toc(timer);
    result(w,:)={idx(1)/cfg.Fs,ends(w)/cfg.Fs,ends(w)/cfg.Fs,label,confidence,tf,tc,physical.voltage_rms_pu_min,ts};
end
if useCache,signature=key;save(path,'result','signature','-v7');end
end
function [estimated,timing]=replay(P,settings)
state=[];timing=zeros(height(P),1);confirmed=struct([]);completed=struct([]);
for w=1:height(P)
    pred=struct('window_start_s',P.window_start_s(w),'window_end_s',P.window_end_s(w),'decision_time_s',P.decision_time_s(w), ...
        'class_id',P.class_id(w),'confidence',P.confidence(w),'severity','unknown','voltage_rms_pu_min',P.voltage_rms_pu_min(w));
    timer=tic;[state,event,t]=eba.stateStep(state,pred,settings);timing(w)=P.feature_time_s(w)+P.classification_time_s(w)+P.severity_time_s(w)+toc(timer);
    if ~isempty(event),if isempty(confirmed),confirmed=event;else,confirmed(end+1)=event;end;end %#ok<AGROW>
    if ~isempty(t.completed_event),if isempty(completed),completed=t.completed_event;else,completed(end+1)=t.completed_event;end;end %#ok<AGROW>
end
estimated=eba.eventEstimates(confirmed,completed,P.window_end_s(end));
end
