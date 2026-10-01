function summary=run_state_refinement()
%RUN_STATE_REFINEMENT Validation-only hysteresis/recovery/refractory and spacing design.
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);
[small,~]=eba.subsetFamilies(F,3,1);V=small(small.split=="validation",:);
S=load(fullfile(cfg.output,'stream_screening_development.mat'),'candidates');
statCfg=cfg;statCfg.temporal_bootstrap_replicates=0;rows=cell(0,1);retained=cell(size(S.candidates));
% Each four-event group shares one baseline. Derivatives and spacing trials retain its families.
events=sortrows(V(V.class_id~=1,:),{'duration_stratum','severity_stratum','class_id','family_id'});
normal=V(V.class_id==1,:);groups=cell(ceil(height(events)/4),1);
for g=1:numel(groups),groups{g}=events((g-1)*4+1:min(g*4,height(events)),:);end
levels=[Inf 20];gaps=[1 3 12]/cfg.nominal_frequency_hz;gaps(end+1)=2;
schedules=cell((numel(groups)*numel(gaps)+height(normal))*numel(levels),1);k=0;
for g=1:numel(groups)
    for spacing=1:numel(gaps)
        sc=cfg;sc.stream_gap_s=gaps(spacing);sc.stream_context_s=2;
        for z=1:numel(levels)
            k=k+1;id="refine_group"+g+"_gap"+spacing+"_snr"+levels(z);
            schedules{k}=eba.continuousSchedule(groups{g},sc,levels(z),id,cfg.stream_seed+50000+g);
        end
    end
end
for i=1:height(normal)
    for z=1:numel(levels)
        k=k+1;schedules{k}=eba.continuousSchedule(normal(i,:),cfg,levels(z), ...
            "refine_normal"+normal.family_id(i)+"_snr"+levels(z),cfg.stream_seed+60000+i);
    end
end
assert(k==numel(schedules));
for m=1:numel(S.candidates)
    if isempty(S.candidates{m}),continue;end
    parent=S.candidates{m};model=parent.model;
    modelPath=fullfile(cfg.output,'stream_models',"candidate_"+lower(model.method)+"_"+model.window_cycles+".mat");
    predictions=cell(size(schedules));
    for i=1:numel(schedules),predictions{i}=eba.streamPredictions(schedules{i},model,statCfg,modelPath,true);end
    first=numel(rows)+1;
    for offGap=[.1 .3]
        for recovery=[1 2 4]
            for refractoryCycles=[0 1 3]
                settings=parent.settings;settings.threshold_off=max(.05,settings.threshold_on-offGap);
                settings.recovery_windows=recovery;settings.refractory_s=refractoryCycles/cfg.nominal_frequency_hz;
                values=zeros(numel(levels),4);
                for z=1:numel(levels)
                    take=cellfun(@(s)isequal(s.snr_db,levels(z)),schedules);
                    [met,detail]=eba.evaluateStreamEvidence(schedules(take),predictions(take),settings,statCfg);
                    values(z,:)=[met.f1,met.false_alarms_per_minute,met.mean_latency_s, ...
                        quantile(detail.exploratory_inference_times_s,.95)/(model.hop_samples/cfg.Fs)];
                end
                rows{end+1}=table(model.method,offGap,settings.threshold_off,recovery,refractoryCycles, ...
                    mean(values(:,1)),max(values(:,2)),max(values(:,3)),max(values(:,4)), ...
                    'VariableNames',{'method','off_threshold_gap','threshold_off','recovery_windows', ...
                    'refractory_cycles','event_f1','false_alarms_per_minute','matched_latency_s','stream_RTF_p95'}); %#ok<AGROW>
            end
        end
    end
    local=vertcat(rows{first:end});objective=[local.event_f1,-local.false_alarms_per_minute,-local.matched_latency_s,-local.stream_RTF_p95];
    eligible=all(isfinite(objective),2) & local.false_alarms_per_minute<=1 & local.stream_RTF_p95<=1;
    ids=find(eligible);
    if isempty(ids)
        fprintf('STATE_REFINEMENT_REJECTED method=%s reason=no_candidate_meets_validation_bounds\n',model.method);continue;
    end
    ids=ids(eba.pareto(objective(ids,:),ones(1,4)));[~,order]=sortrows([-local.event_f1(ids),local.matched_latency_s(ids),ids],[1 2 3]);
    index=ids(order(1));choice=local(index,:);settings=parent.settings;
    settings.threshold_off=choice.threshold_off;settings.recovery_windows=choice.recovery_windows;
    settings.refractory_s=choice.refractory_cycles/cfg.nominal_frequency_hz;
    retained{m}=parent;retained{m}.settings=settings;retained{m}.refinement_row=first+index-1;
    fprintf('STATE_REFINEMENT_COMPLETE method=%s recovery=%d refractory_cycles=%g validation_event_f1=%.6g\n', ...
        model.method,choice.recovery_windows,choice.refractory_cycles,choice.event_f1);
end
assert(any(~cellfun(@isempty,retained)),'eba:StreamFeasibility','No representation passed hierarchical validation refinement.');
summary=vertcat(rows{:});paths=[string(fullfile(cfg.output,'state_refinement.csv'));string(fullfile(cfg.output,'state_refinement.mat'))];
writetable(summary,paths(1));save(paths(2),'summary','retained','schedules','-v7.3');
eba.manifest('state_refinement',cfg,struct('scope','validation only; hierarchical fixed-budget engineering search', ...
    'methods',string(cellfun(@(q) q.model.method,S.candidates(~cellfun(@isempty,S.candidates)),'UniformOutput',false)), ...
    'classifier','SVM','parameters',{cellfun(@(q) q.model.parameters,S.candidates(~cellfun(@isempty,S.candidates)),'UniformOutput',false)}, ...
    'hyperparameters',{cellfun(@(q) q.model.hyperparameters,S.candidates(~cellfun(@isempty,S.candidates)),'UniformOutput',false)}, ...
    'n_schedules',numel(schedules),'spacing_s',gaps,'pre_post_context_s',2,'snrs',levels,'realization',1, ...
    'off_threshold_gaps',[.1 .3],'recovery_counts',[1 2 4],'refractory_nominal_cycles',[0 1 3], ...
    'selection_rule','eligible nondominated candidates; maximum mean clean/20dB event F1 then minimum worst matched latency then grid order', ...
    'limitations','one screening candidate per representation; finite hierarchical search, no global optimum or hard-real-time claim'),paths);
fprintf('STATE_REFINEMENT_PASS candidates=%d test_accessed=0\n',height(summary));
end
