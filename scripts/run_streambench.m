function report=run_streambench()
%RUN_STREAMBENCH Frozen held-out continuous detection; no fitting or setting changes.
cfg=eba.config();freeze=eba.requireFrozen(cfg,'begin');cleanup=onCleanup(@() eba.requireFrozen(cfg,'reset'));
assert(isfield(freeze,'selected_stream') && isfield(freeze,'stream_protocol'),'eba:TestFirewall','Frozen stream model, settings and schedule recipes are required.');
entry=freeze.selected_stream;M=load(fullfile(cfg.root,entry.path),'model');model=M.model;settings=entry.settings;
protocol=freeze.stream_protocol;assert(protocol.mode=="single_and_grouped" && protocol.group_size==4);
F=eba.families(cfg.families_per_cell,cfg);T=F(F.split=="test",:);
stamp=string(datetime('now','TimeZone','UTC','Format',"yyyyMMdd'T'HHmmssSSS"));
folder=fullfile(cfg.output,"final_streambench_"+stamp);assert(~isfolder(folder));mkdir(folder);
levels=[Inf double(protocol.noisy_snr_db(:)')];schedules=cell(0,1);predictions=cell(0,1);artifacts=strings(0,1);
% The first recipe gives paired one-event sequences and pure-normal trials for every test family.
for i=1:height(T)
    for z=1:numel(levels)
        count=cfg.noise_realizations;if z==1,count=1;end
        for r=1:count
            id="test_single_"+T.family_id(i)+"_snr"+levels(z)+"_r"+r;
            schedule=eba.continuousSchedule(T(i,:),cfg,levels(z),id, ...
                mod(cfg.stream_seed+double(T.family_seed(i)),2^32),"final",r,protocol.schedule_options(1));
            schedules{end+1,1}=schedule;predictions{end+1,1}=eba.streamPredictions(schedule,model,cfg,fullfile(cfg.root,entry.path),true); %#ok<AGROW>
        end
    end
    if mod(i,50)==0 || i==height(T),fprintf('FROZEN_STREAM_SINGLE families=%d/%d sequences=%d\n',i,height(T),numel(schedules));end
end
[report,details]=eba.evaluateStreamEvidence(schedules,predictions,settings,cfg);
path=fullfile(folder,'single_stream_report.json');eba.json(path,report);artifacts(end+1)=path;
path=fullfile(folder,'single_stream_results.mat');save(path,'report','details','schedules','predictions','-v7.3');artifacts(end+1)=path;
% Conditional noise reports retain whole families across their realization derivatives.
conditions=cellfun(@(q) q.snr_db,schedules);
for level=levels
    take=conditions==level;conditional=eba.evaluateStreamEvidence(schedules(take),predictions(take),settings,cfg);
    path=fullfile(folder,"single_snr_"+level+".json");eba.json(path,conditional);artifacts(end+1)=path; %#ok<AGROW>
end
% Per-class event predictions include false predictions on every other true class.
for c=2:numel(cfg.classes)
    gt=details.truth(details.truth.class_id==c,:);ed=details.estimated(details.estimated.class_id==c,:);
    conditional=eba.eventMetrics(gt,ed,details.exposure,cfg);
    conditional.n_true_event_families=numel(unique(gt.family_id));conditional.class_name=cfg.classes(c);
    path=fullfile(folder,"single_class_"+cfg.classes(c)+".json");eba.json(path,conditional);artifacts(end+1)=path; %#ok<AGROW>
end
for threshold=double(protocol.sensitivity_iou_thresholds(:)')
    sc=cfg;sc.event_iou_threshold=threshold;
    sensitivity=eba.eventMetrics(details.truth,details.estimated,details.exposure,sc);
    path=fullfile(folder,"single_iou_"+threshold+".json");eba.json(path,sensitivity);artifacts(end+1)=path; %#ok<AGROW>
end
% Close spacing is a separate estimand. Shared baseline groups merge families into clusters.
events=sortrows(T(T.class_id~=1,:),{'duration_stratum','severity_stratum','class_id','family_id'});
groups=cell(ceil(height(events)/protocol.group_size),1);
for g=1:numel(groups),groups{g}=events((g-1)*protocol.group_size+1:min(g*protocol.group_size,height(events)),:);end
for a=2:numel(protocol.schedule_options)
    groupedSchedules=cell(numel(groups)*2,1);groupedPredictions=cell(size(groupedSchedules));k=0;
    for g=1:numel(groups)
        for z=1:2
            pairedLevels=[Inf double(protocol.group_noisy_snr_db)];k=k+1;id="test_group_"+g+"_spacing"+a+"_snr"+pairedLevels(z);
            schedule=eba.continuousSchedule(groups{g},cfg,pairedLevels(z),id,cfg.stream_seed+100000+g, ...
                "final",1,protocol.schedule_options(a));
            groupedSchedules{k}=schedule;groupedPredictions{k}=eba.streamPredictions(schedule,model,cfg,fullfile(cfg.root,entry.path),true);
        end
        if mod(g,30)==0 || g==numel(groups),fprintf('FROZEN_STREAM_GROUP spacing=%d groups=%d/%d\n',a,g,numel(groups));end
    end
    [groupedReport,groupedDetails]=eba.evaluateStreamEvidence(groupedSchedules,groupedPredictions,settings,cfg);
    path=fullfile(folder,"group_spacing_"+a+".json");eba.json(path,groupedReport);artifacts(end+1)=path; %#ok<AGROW>
    path=fullfile(folder,"group_spacing_"+a+".mat");save(path,'groupedReport','groupedDetails','groupedSchedules','groupedPredictions','-v7.3');artifacts(end+1)=path; %#ok<AGROW>
end
path=fullfile(folder,'matched_events.csv');writetable(details.matched,path);artifacts(end+1)=path;
path=fullfile(folder,'estimated_events.csv');writetable(details.estimated,path);artifacts(end+1)=path;
path=fullfile(folder,'ground_truth.csv');writetable(details.truth,path);artifacts(end+1)=path;
eba.requireFrozen(cfg,'end');eba.manifest('final_streambench',cfg,struct('scope','frozen test only; single-family suite and separate close-spacing connected clusters', ...
    'method',model.method,'classifier','SVM','parameters',model.parameters,'hyperparameters',model.hyperparameters, ...
    'model_path',entry.path,'state_settings',settings,'stream_protocol',protocol, ...
    'freeze_sha256',eba.hash(fullfile(cfg.root,'FROZEN_EXPERIMENT.json'),'file')),artifacts);
fprintf('FROZEN_STREAMBENCH_PASS families=%d single_sequences=%d false_alarms=%d fitting_calls=0\n',height(T),report.n_sequences,report.false_alarms);
end
