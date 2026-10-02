function report=run_rf_stream_development()
%RUN_RF_STREAM_DEVELOPMENT Tune RF windows and temporal state on validation only.
cfg=eba.config();pool=gcp('nocreate');if isempty(pool)
    c=parcluster('local');c.NumWorkers=8;pool=parpool(c,8);
end
fprintf('RF_STREAM_WORKERS workers=%d\n',pool.NumWorkers);
F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);
[small,cal]=eba.subsetFamilies(F,3,1);Vall=small(small.split=="validation",:);V=Vall([],:);
% Balanced incomplete block: each event class x severity appears once;
% duration strata rotate across cells. Final comparison keeps all 864 clusters.
for cls=2:numel(cfg.classes)
    for severity=1:3
        duration=mod(cls+severity-2,4)+1;
        ix=find(Vall.class_id==cls & Vall.severity_stratum==severity & ...
            Vall.duration_stratum==duration,1);
        assert(~isempty(ix),'eba:RFStreamScreen','The stratified temporal screen cell is missing.');
        V=[V;Vall(ix,:)]; %#ok<AGROW>
    end
end
assert(height(V)==3*(numel(cfg.classes)-1) && numel(unique(V.family_id))==height(V), ...
    'eba:RFStreamScreen','The temporal screen must retain independent class/severity families.');
% Heavy track is fixed from the 12-class RF offline ranking before stream validation.
offline=readtable(fullfile(cfg.output,'combined_validation_rf_metrics.csv'),'TextType','string');
allMethods=["FFT","STFT","DWT","CWT","ST"];
% The common RF runtime manifests provide matched p95 values and are used as descriptive cost.
cost=zeros(5,1);for i=1:5
    j=jsondecode(fileread(fullfile(cfg.output,"runtime_"+lower(allMethods(i))+"_rf.json")));
    cost(i)=j.total_p95_s;
end
score=zeros(5,1);for i=1:5,score(i)=offline.macro_f1(offline.method==allMethods(i));end
[~,ord]=sortrows([-score,cost,(1:5)'],[1 2 3]);heavyMethods=allMethods(ord(1:3));
assert(isequal(heavyMethods,["FFT","ST","CWT"]),'eba:HeavyTrackDefinition', ...
    'The fixed top-three RF track must match the declared 12-class offline Macro-F1 ranking.');
T=load(fullfile(cfg.output,'development_transform_selection.mat'),'methods','selected');
hpTable=readtable(fullfile(cfg.output,'shared_hyperparameters_rf.csv'),'TextType','string');
hp=jsondecode(hpTable.hyperparameters_json(hpTable.selected==1));
cyclesGrid=cfg.stream_window_cycles(:).';
windowRows=cell(0,1);screenModels=cell(numel(heavyMethods),numel(cyclesGrid));
for m=1:numel(heavyMethods)
    mi=find(T.methods==heavyMethods(m));base=T.selected{mi};
    for w=1:numel(cyclesGrid)
        cycles=cyclesGrid(w);N=round(cfg.Fs*cycles/cfg.nominal_frequency_hz);
        parameters=eba.windowParameters(heavyMethods(m),base,N);
        [X,P,info]=eba.windowData(small,heavyMethods(m),parameters,N,cfg);
        fit=P.split=="train" & ~ismember(P.family_id,cal);
        cm=P.split=="train" & ismember(P.family_id,cal);vm=P.split=="validation";
        model=eba.fit(X(fit,:),P.class_id(fit),cfg,'RF',hp);
        model=eba.calibrate(model,X(cm,:),P.class_id(cm),P.family_id(cm));
        model.method=heavyMethods(m);model.parameters=parameters;model.window_samples=N;
        model.window_cycles=cycles;model.hop_samples=max(1,round(N*.25));
        model.model_version="rf-screen-"+lower(heavyMethods(m))+"-"+cycles;
        model.training_family_ids=unique(P.family_id(fit));model.calibration_family_ids=unique(P.family_id(cm));
        model.training_dataset_hash=info.family_hash;
        prediction=eba.predict(model,X(vm,:));metric=eba.metrics(P.class_id(vm),prediction,numel(cfg.classes));
        screenModels{m,w}=model;
        windowRows{end+1}=table(heavyMethods(m),cycles,N,metric.macro_f1, ...
            'VariableNames',{'method','window_cycles','window_samples','validation_window_macro_f1'}); %#ok<AGROW>
        fprintf('RF_STREAM_WINDOW method=%s cycles=%d macroF1=%.6f\n',heavyMethods(m),cycles,metric.macro_f1);
    end
end
windowSummary=vertcat(windowRows{:});
% Keep the best window per representation; full six-model selection is separate.
top=cell(numel(heavyMethods),1);for m=1:numel(heavyMethods)
    q=windowSummary(windowSummary.method==heavyMethods(m),:);
    [~,ix]=sortrows([-q.validation_window_macro_f1,q.window_cycles],[1 2]);top{m}=q.window_cycles(ix(1));
end
levels=[Inf 20];schedules=cell(height(V),2);
for i=1:height(V),for z=1:2
    schedules{i,z}=eba.continuousSchedule(V(i,:),cfg,levels(z), ...
        "rf_screen_"+V.family_id(i)+"_snr"+levels(z),mod(cfg.stream_seed+double(V.family_seed(i)),2^32));
end,end
statCfg=cfg;statCfg.temporal_bootstrap_replicates=0;
settings=struct('threshold_on',.7,'threshold_off',.5,'min_windows',2,'min_evidence_s',1/60, ...
    'recovery_windows',2,'refractory_s',0,'classes',cfg.classes,'method_version',cfg.method_version, ...
    'dataset_version',cfg.dataset_version,'confidence_calibrated',true,'sequence_id','rf-screen');
rows=cell(0,1);candidateSets=cell(numel(heavyMethods),1);folder=fullfile(cfg.output,'rf_stream_candidates');
if ~isfolder(folder),mkdir(folder);end
for m=1:numel(heavyMethods)
    q=windowSummary(windowSummary.method==heavyMethods(m),:);take=find(ismember(q.window_cycles,top{m}));
    localRows=cell(0,1);localCandidates=cell(0,1);
    for a=take(:).'
        cycles=q.window_cycles(a);w=find(cyclesGrid==cycles);model=screenModels{m,w};
        modelPath=fullfile(folder,"screen_"+lower(model.method)+"_"+cycles+".mat");eba.saveModel(modelPath,model);
        minHop=max(1,round(model.window_samples*.25));model.hop_samples=minHop;
        fine=cell(size(schedules));
        parfor i=1:numel(schedules)
            fine{i}=eba.streamPredictions(schedules{i},model,statCfg,modelPath,true);
        end
        for hopFraction=[.25 .5]
            hop=max(1,round(model.window_samples*hopFraction));
            predictions=cell(size(schedules));
            for i=1:numel(schedules)
                for z=1:2
                    wanted=model.window_samples:hop:schedules{i,z}.n_samples;
                    [ok,ix]=ismember(wanted,round(fine{i,z}.window_end_s*cfg.Fs));
                    assert(all(ok),'eba:RFStreamHop','Selected hop is absent from the dense causal prediction grid.');
                    predictions{i,z}=fine{i,z}(ix,:);
                end
            end
            for threshold=[.5 .7 .9]
                for persistence=[2 3 5]
                    candidate=settings;candidate.threshold_on=threshold;
                    candidate.threshold_off=max(.1,threshold-.2);candidate.min_windows=persistence;
                    candidate.sequence_id="rf-screen";f1=zeros(2,1);fa=f1;lat=f1;rtf=f1;
                    for z=1:2
                        candidate.model_version=model.model_version;
                        [ev,details]=eba.evaluateStreamEvidence(schedules(:,z),predictions(:,z),candidate,statCfg);
                        f1(z)=ev.f1;fa(z)=ev.false_alarms_per_minute;lat(z)=ev.mean_latency_s;
                        rtf(z)=quantile(details.exploratory_inference_times_s,.95)/(hop/cfg.Fs);
                    end
                    row=table(model.method,model.kind,cycles,hopFraction,threshold,persistence,mean(f1), ...
                        max(fa),max(lat),max(rtf),mean(f1),true, ...
                        'VariableNames',{'method','classifier','window_cycles','hop_fraction','threshold_on', ...
                        'min_windows','event_f1','false_alarms_per_minute','matched_latency_s','screen_RTF_p95', ...
                        'selection_score','complete'});
                    localRows{end+1}=row; %#ok<AGROW>
                    localCandidates{end+1}=struct('model',model,'settings',candidate,'row',row, ...
                        'model_path',string(modelPath)); %#ok<AGROW>
                end
            end
        end
    end
    local=vertcat(localRows{:});objective=[local.event_f1,-local.false_alarms_per_minute, ...
        -local.matched_latency_s,-local.screen_RTF_p95];ok=all(isfinite(objective),2);
    front=false(height(local),1);front(ok)=eba.pareto(objective(ok,:),ones(1,4));ids=find(front);
    [~,rank]=sortrows([-local.event_f1(ids),local.false_alarms_per_minute(ids), ...
        local.matched_latency_s(ids),local.window_cycles(ids),ids],[1 2 3 4 5]);chosen=ids(rank(1));
    candidates=localCandidates{chosen};candidate=candidates;candidate.selected_window_f1= ...
        windowSummary.validation_window_macro_f1(windowSummary.method==heavyMethods(m) & ...
        windowSummary.window_cycles==candidate.model.window_cycles);
    candidateSets{m}=candidate;summaryRow=local(chosen,:);summaryRow.selected=true;rows{m}=summaryRow;
    fprintf('RF_STREAM_SELECTED method=%s cycles=%d eventF1=%.6f RTF_screen=%.4f\n', ...
        heavyMethods(m),candidate.model.window_cycles,summaryRow.event_f1,summaryRow.screen_RTF_p95);
end
summary=vertcat(rows{:});
save(fullfile(cfg.output,'rf_stream_development.mat'),'candidateSets','summary','windowSummary','-v7.3');
writetable(summary,fullfile(cfg.output,'rf_stream_development.csv'));
report=struct('status','PASS','heavy_methods',heavyMethods,'classifier','RF','hyperparameters',hp, ...
    'window_candidates',table2struct(windowSummary),'selected_candidates',table2struct(summary), ...
    'scope','12-class RF ranking fixed from offline validation; five windows screened on all small validation cells; one best window per method and temporal state refined on 33 independent class-severity families with duration strata rotated and paired clean/20 dB schedules; full comparison uses 6,048 schedules and 864 clusters; test not loaded', ...
    'temporal_screen_families',height(V),'temporal_screen_schedules',numel(schedules), ...
    'cost_policy','RTF remains a Pareto/reporting outcome and is not a feasibility exclusion');
eba.json(fullfile(cfg.output,'rf_stream_development.json'),report);
eba.manifest('rf_stream_development',cfg,struct('scope',report.scope,'methods',heavyMethods, ...
    'classifier','RF','hyperparameters',hp,'cost_policy',report.cost_policy, ...
    'validation_families',height(V),'validation_schedules',numel(schedules), ...
    'workers',pool.NumWorkers,'test_accessed',false), ...
    {fullfile(cfg.output,'rf_stream_development.csv'),fullfile(cfg.output,'rf_stream_development.json'), ...
    fullfile(cfg.output,'rf_stream_development.mat')});
fprintf('RF_STREAM_DEVELOPMENT_PASS methods=%s test_accessed=0\n',strjoin(heavyMethods,','));
end
