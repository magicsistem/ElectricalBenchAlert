function [estimated,timing,emissions]=replayWindows(P,settings)
%REPLAYWINDOWS Replay arrived prediction evidence without reusing ground truth.
assert(istable(P) && height(P)>0,'eba:StreamReplay','Nonempty window predictions are required.');
state=[];timing=zeros(height(P),1);confirmed=struct([]);completed=struct([]);
for w=1:height(P)
    timer=tic;grade="unknown";if ismember('severity',P.Properties.VariableNames),grade=P.severity(w);end
    pred=struct('window_start_s',P.window_start_s(w),'window_end_s',P.window_end_s(w), ...
        'decision_time_s',P.decision_time_s(w),'class_id',P.class_id(w),'confidence',P.confidence(w), ...
        'severity',grade,'voltage_rms_pu_min',P.voltage_rms_pu_min(w));
    [state,event,transition]=eba.stateStep(state,pred,settings);
    timing(w)=P.feature_time_s(w)+P.classification_time_s(w)+P.severity_time_s(w)+toc(timer);
    if ~isempty(event),if isempty(confirmed),confirmed=event;else,confirmed(end+1)=event;end;end %#ok<AGROW>
    if ~isempty(transition.completed_event)
        if isempty(completed),completed=transition.completed_event;else,completed(end+1)=transition.completed_event;end
    end %#ok<AGROW>
end
estimated=eba.eventEstimates(confirmed,completed,P.window_end_s(end));
emissions=struct('confirmed',confirmed,'completed',completed,'final_state',state);
end
