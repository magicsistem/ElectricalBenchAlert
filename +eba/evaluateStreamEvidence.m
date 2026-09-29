function [report,details]=evaluateStreamEvidence(schedules,predictions,settings,cfg)
%EVALUATESTREAMEVIDENCE Metrics use truth after replay; paired derivatives stay linked.
assert(iscell(schedules) && iscell(predictions) && numel(schedules)==numel(predictions) && ~isempty(schedules), ...
    'eba:StreamEvaluation','A matched nonempty sequence/prediction workload is required.');
truth=[];estimated=[];times=cell(numel(schedules),1);
exposure=table(strings(numel(schedules),1),zeros(numel(schedules),1),strings(numel(schedules),1), ...
    'VariableNames',{'sequence_id','normal_exposure_s','family_id'});
normalFamilies=strings(0,1);normalAlarm=zeros(0,1);windowCount=0;
for i=1:numel(schedules)
    schedule=schedules{i};P=predictions{i};
    assert(height(P)>0 && P.window_end_s(end)<=schedule.duration_s && ...
        all(P.decision_time_s>=P.window_end_s) && all(diff(P.window_end_s)>0), ...
        'eba:StreamEvaluation','Predictions must represent monotonically arrived complete windows.');
    candidate=settings;candidate.sequence_id=schedule.sequence_id;
    [ed,timing]=eba.replayWindows(P,candidate);gt=schedule.events;
    observed=P.window_end_s(end);gt=gt(gt.start_s<observed,:);
    if isempty(truth),truth=gt;estimated=ed;else,truth=[truth;gt];estimated=[estimated;ed];end %#ok<AGROW>
    normal=observed-sum(max(0,min(gt.end_s,observed)-gt.start_s));
    exposure(i,:)={schedule.sequence_id,normal,schedule.family_ids(1)};
    times{i}=timing;windowCount=windowCount+height(P);
    if isempty(schedule.events)
        assert(numel(schedule.family_ids)==1,'eba:StreamEvaluation','Pure-normal exposure inherits one normal family.');
        normalFamilies(end+1,1)=schedule.family_ids(1);normalAlarm(end+1,1)=height(ed)>0; %#ok<AGROW>
    end
end
[report,matched,clusters]=eba.eventMetrics(truth,estimated,exposure,cfg);
report.n_window_predictions=windowCount;
report.normal_family_alarm_incidence_status='not evaluated: no pure-normal family sequences';
if ~isempty(normalFamilies)
    [ids,~,group]=unique(normalFamilies);alarm=accumarray(group,normalAlarm,[],@max);
    [point,ci]=binofit(sum(alarm),numel(ids),.05);
    report.normal_family_alarm_incidence=point;report.normal_family_alarm_incidence_ci_low=ci(1);
    report.normal_family_alarm_incidence_ci_high=ci(2);report.n_pure_normal_families=numel(ids);
    report.n_pure_normal_families_with_any_alarm=sum(alarm);
    report.normal_family_alarm_incidence_status='Clopper-Pearson family-level any-alarm incidence across the fixed normal exposure/noise suite; assumes independent identically designed normal family trials; not a Poisson rate interval';
end
report.zero_false_alarm_bootstrap_limitation=report.false_alarms==0;
report.runtime_scope='exploratory prediction assembly and state replay times; fresh matched runtime sessions provide final computational comparisons';
details=struct('truth',truth,'estimated',estimated,'exposure',exposure,'matched',matched, ...
    'clusters',clusters,'exploratory_inference_times_s',vertcat(times{:}));
end
