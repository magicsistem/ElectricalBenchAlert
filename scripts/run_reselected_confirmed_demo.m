function report=run_reselected_confirmed_demo()
%RUN_RESELECTED_CONFIRMED_DEMO Confirm a deterministic validation sag with selected full-train FFT.
cfg=eba.config();prefix="reselection_stream_full";
stored=load(fullfile(cfg.output,'stream_models',prefix+"_fft.mat"),'model');model=stored.model;
state=load(fullfile(cfg.output,'reselection_state_refinement.mat'),'retained');
ix=find(cellfun(@(q)~isempty(q)&&q.model.method=="FFT",state.retained));assert(isscalar(ix),'eba:ReselectionDemo','Refined FFT settings are required.');
settings=state.retained{ix}.settings;settings.model_version=model.model_version;settings.git_commit=model.training_git_commit;
F=eba.families(cfg.families_per_cell,cfg);V=F(F.split=="validation"&F.class_name=="voltage_sag"& ...
    F.severity_stratum>=2&F.duration_stratum==4,:);V=sortrows(V,'family_id');found=false;
for i=1:height(V)
    schedule=eba.continuousSchedule(V(i,:),cfg,Inf,"reselected_fft_confirmed_demo",cfg.stream_seed+200000,"development",1);
    result=eba.processStream(schedule,model,settings,cfg,true);
    if result.stopped_at_confirmation&&result.metrics.false_alarms==0&&result.metrics.n_matched_events==1&& ...
            result.truth.class_id==result.confirmed_events(1).class_id&&any(result.phases=="SUSPECTED")
        found=true;break;
    end
end
assert(found,'eba:ReselectionDemo','Selected FFT model did not confirm a matching validation sag.');
event=result.confirmed_events(1);truth=result.truth;latency=event.confirmation_time_s-truth.start_s;
folder=fullfile(cfg.output,'reselection_confirmed_demo');if ~isfolder(folder),mkdir(folder);end
paths=[string(fullfile(folder,'confirmed_event.json'));string(fullfile(folder,'ground_truth.csv')); ...
    fullfile(folder,'window_predictions.csv');fullfile(folder,'results.mat');fullfile(folder,'summary.csv')];
eba.json(paths(1),event);writetable(truth,paths(2));writetable(result.window_predictions,paths(3));
save(paths(4),'schedule','result','settings','-v7.3');
summary=table(string(event.class),truth.start_s,event.estimated_start_s,event.confirmation_time_s,latency, ...
    event.confidence,numel(event.supporting_windows),result.metrics.false_alarms, ...
    'VariableNames',{'class','physical_start_s','estimated_start_s','confirmation_time_s','detection_latency_s', ...
    'minimum_supporting_window_score','supporting_windows','false_alarms'});writetable(summary,paths(5));
report=struct('status','PASS','scope','deterministic clean validation illustration; not independent performance estimate', ...
    'method','FFT','classifier','SVM','summary',table2struct(summary),'processed_windows',height(result.window_predictions), ...
    'transitions',unique(result.phases,'stable'),'stopped_at_confirmation',result.stopped_at_confirmation, ...
    'model_sha256',eba.hash(fullfile(cfg.output,'stream_models',prefix+"_fft.mat"),'file'));
eba.manifest('reselection_confirmed_demo',cfg,struct('scope',report.scope,'method','FFT','classifier','SVM', ...
    'state_settings',settings,'report',report),paths);
fprintf('RESELECTED_CONFIRMED_DEMO_PASS class=%s latency_s=%.6f false_alarms=0 model=FFT_SVM\n',event.class,latency);
end
