function report=run_selected_six_model_demo()
%RUN_SELECTED_SIX_MODEL_DEMO Reproduce one confirmed validation sag with the six-track winner.
cfg=eba.config();selectionPath=fullfile(cfg.output,'six_model_stream','six_model_selection.json');
selection=jsondecode(fileread(selectionPath));assert(strcmp(selection.status,'PASS')&&~selection.test_accessed, ...
    'eba:SixDemoSelection','A completed validation-only six-model selection is required.');
method=string(selection.selected_method);classifier=string(selection.selected_classifier);
if classifier=="SVM"
    modelPath=fullfile(cfg.output,'stream_models',"reselection_stream_full_"+lower(method)+".mat");
    state=load(fullfile(cfg.output,'reselection_state_refinement.mat'),'retained');
    ix=find(cellfun(@(q)~isempty(q)&&string(q.model.method)==method,state.retained));
    assert(isscalar(ix),'eba:SixDemoSettings','Retained SVM temporal settings are missing.');
    settings=state.retained{ix}.settings;
else
    modelPath=fullfile(cfg.output,'six_model_stream',"model_rf_"+lower(method)+".mat");
    state=load(fullfile(cfg.output,'rf_stream_development.mat'),'candidateSets');
    ix=find(cellfun(@(q)string(q.model.method)==method,state.candidateSets));
    assert(isscalar(ix),'eba:SixDemoSettings','Selected RF temporal settings are missing.');
    settings=state.candidateSets{ix}.settings;
end
stored=load(modelPath,'model');model=stored.model;
settings.model_version=model.model_version;settings.git_commit=model.training_git_commit;
settings.method_version=cfg.method_version;settings.dataset_version=cfg.dataset_version;
settings.confidence_calibrated=model.calibrated;
F=eba.families(cfg.families_per_cell,cfg);V=F(F.split=="validation"&F.class_name=="voltage_sag"& ...
    F.severity_stratum>=2&F.duration_stratum==4,:);V=sortrows(V,'family_id');found=false;
for i=1:height(V)
    schedule=eba.continuousSchedule(V(i,:),cfg,Inf,"six_model_confirmed_"+lower(method)+"_"+lower(classifier), ...
        cfg.stream_seed+200000,"development",1);
    result=eba.processStream(schedule,model,settings,cfg,true);
    if result.stopped_at_confirmation&&result.metrics.false_alarms==0&&result.metrics.n_matched_events==1&& ...
            result.truth.class_id==result.confirmed_events(1).class_id&&any(result.phases=="SUSPECTED")
        found=true;break;
    end
end
assert(found,'eba:SixDemoConfirmation','The selected six-track model did not confirm a matching validation sag.');
event=result.confirmed_events(1);truth=result.truth;latency=event.confirmation_time_s-truth.start_s;
folder=fullfile(cfg.output,'six_model_stream',"confirmed_demo_"+lower(method)+"_"+lower(classifier));
if ~isfolder(folder),mkdir(folder);end
paths=[string(fullfile(folder,'confirmed_event.json'));string(fullfile(folder,'ground_truth.csv')); ...
    string(fullfile(folder,'window_predictions.csv'));string(fullfile(folder,'results.mat')); ...
    string(fullfile(folder,'summary.csv'))];
eba.json(paths(1),event);writetable(truth,paths(2));writetable(result.window_predictions,paths(3));
save(paths(4),'schedule','result','settings','-v7.3');
summary=table(string(event.class),truth.start_s,event.estimated_start_s,event.confirmation_time_s,latency, ...
    event.confidence,numel(event.supporting_windows),result.metrics.false_alarms, ...
    'VariableNames',{'class','physical_start_s','estimated_start_s','confirmation_time_s','detection_latency_s', ...
    'minimum_supporting_window_score','supporting_windows','false_alarms'});writetable(summary,paths(5));
report=struct('status','PASS','scope','single deterministic clean validation illustration; no generalization claim', ...
    'method',method,'classifier',classifier,'selection_sha256',eba.hash(selectionPath,'file'), ...
    'summary',table2struct(summary),'processed_windows',height(result.window_predictions), ...
    'transitions',unique(result.phases,'stable'),'stopped_at_confirmation',result.stopped_at_confirmation, ...
    'model_sha256',eba.hash(modelPath,'file'));
json=fullfile(folder,'demo_report.json');eba.json(json,report);
eba.manifest("six_model_confirmed_demo_"+lower(method)+"_"+lower(classifier),cfg, ...
    struct('scope',report.scope,'method',method,'classifier',classifier,'state_settings',settings, ...
    'selection_sha256',report.selection_sha256,'report',report),[paths;string(json)]);
fprintf('SIX_MODEL_CONFIRMED_DEMO_PASS class=%s classifier=%s method=%s latency_s=%.6f alarms=%d\n', ...
    event.class,classifier,method,latency,result.metrics.false_alarms);
end
