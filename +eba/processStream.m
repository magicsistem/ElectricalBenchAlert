function result=processStream(schedule,model,settings,cfg,stopAtConfirmed)
%PROCESSSTREAM Arrived trailing windows -> calibrated model -> persistent state; no truth state input.
if nargin<5,stopAtConfirmed=false;end
assert(islogical(stopAtConfirmed) && isscalar(stopAtConfirmed),'eba:StreamStop','The confirmation stop control must be logical.');
N=model.window_samples;hop=model.hop_samples;
assert(N>=4 && hop>=1 && hop<=N && N==fix(N) && hop==fix(hop),'eba:StreamWindow','Invalid window/hop.');
settings.sequence_id=schedule.sequence_id;settings.classes=cfg.classes;settings.confidence_calibrated=model.calibrated;
ends=N:hop:schedule.n_samples;n=numel(ends);state=[];events=struct([]);completed=struct([]);phases=strings(n,1);
windows=table('Size',[n 8],'VariableTypes',{'double','double','double','double','double','double','double','string'}, ...
    'VariableNames',{'window_start_s','window_end_s','decision_time_s','class_id','confidence','feature_time_s','classification_time_s','state'});
feature_times=zeros(n,1);class_times=zeros(n,1);total_times=zeros(n,1);
for w=1:n
    idx=(ends(w)-N:ends(w)-1)';signal=eba.continuousSignal(schedule,idx,cfg);
    totalTimer=tic;timer=tic;v=eba.features(signal,cfg.Fs,model.method,model.parameters);feature_times(w)=toc(timer);
    timer=tic;[label,confidence]=eba.predict(model,v);class_times(w)=toc(timer);
    [grade,physical]=eba.severity(signal,cfg.classes(label),cfg.Fs);
    pred=struct('window_start_s',idx(1)/cfg.Fs,'window_end_s',ends(w)/cfg.Fs, ...
        'decision_time_s',ends(w)/cfg.Fs,'class_id',label,'confidence',confidence,'severity',grade, ...
        'voltage_rms_pu_min',physical.voltage_rms_pu_min);
    [state,event,transition]=eba.stateStep(state,pred,settings);phases(w)=state.phase;
    total_times(w)=toc(totalTimer);
    if ~isempty(event)
        if isempty(events),events=event;else,events(end+1)=event;end
    end %#ok<AGROW>
    if ~isempty(transition.completed_event)
        if isempty(completed),completed=transition.completed_event;else,completed(end+1)=transition.completed_event;end
    end %#ok<AGROW>
    windows(w,:)={pred.window_start_s,pred.window_end_s,pred.decision_time_s,label,confidence,feature_times(w),class_times(w),state.phase};
    if stopAtConfirmed && ~isempty(event),break;end
end
windows=windows(1:w,:);phases=phases(1:w);feature_times=feature_times(1:w);class_times=class_times(1:w);total_times=total_times(1:w);
observedUntil=windows.window_end_s(end);truth=schedule.events(schedule.events.start_s<observedUntil,:);
estimated=eba.eventEstimates(events,completed,observedUntil);
normalExposure=observedUntil-sum(max(0,min(truth.end_s,observedUntil)-truth.start_s));
exposure=table(schedule.sequence_id,normalExposure,'VariableNames',{'sequence_id','normal_exposure_s'});
if numel(schedule.family_ids)==1,exposure.family_id=schedule.family_ids;end
[metrics,matched,clusters]=eba.eventMetrics(truth,estimated,exposure,cfg);
result=struct('sequence_id',schedule.sequence_id,'split',schedule.split,'window_predictions',windows,'confirmed_events',events, ...
    'completed_events',completed,'truth',truth,'estimated_events',estimated,'metrics',metrics,'matched',matched, ...
    'clusters',clusters,'final_state',state,'phases',phases,'window_samples',N,'hop_samples',hop, ...
    'feature_median_s',median(feature_times),'total_p95_s',quantile(total_times,.95),'total_inference_times_s',total_times, ...
    'streaming_real_time_factor_p95',quantile(total_times,.95)/(hop/cfg.Fs), ...
    'confirmation_scope','sample availability timestamp; compute time reported separately; no wall-clock pacing', ...
    'observed_until_s',observedUntil,'scheduled_truth',schedule.events,'stopped_at_confirmation',stopAtConfirmed && state.phase=="CONFIRMED", ...
    'censored_confirmations',numel(events)-numel(completed));
end
