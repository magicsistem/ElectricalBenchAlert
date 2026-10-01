function [winner,front]=selectStreamCandidate(T)
%SELECTSTREAMCANDIDATE Pareto-report complete pipelines, then maximize event F1.
required={'event_f1','false_alarms_per_minute','matched_latency_s','stream_RTF_p95','eligible'};
assert(istable(T) && all(ismember(required,T.Properties.VariableNames)), ...
    'eba:CandidateTable','Candidate table lacks required validation/runtime outcomes.');
finite=all(isfinite(T{:,1:4}),2);eligible=logical(T.eligible(:))&finite;
assert(any(eligible),'eba:CandidateFeasibility','No complete continuous candidate.');
objective=[T.event_f1,-T.false_alarms_per_minute,-T.matched_latency_s,-T.stream_RTF_p95];
if ismember('model_bytes',T.Properties.VariableNames),objective(:,end+1)=-T.model_bytes;end
front=false(height(T),1);front(eligible)=eba.pareto(objective(eligible,:),ones(1,size(objective,2)));
% Prefer evidence robust to validation sampling noise; retain point score for ties.
if ismember('event_f1_ci_low',T.Properties.VariableNames),primary=T.event_f1_ci_low;
else,primary=T.event_f1;end
ids=find(front);[~,order]=sortrows([-primary(ids),-T.event_f1(ids), ...
    T.false_alarms_per_minute(ids),T.matched_latency_s(ids),ids],[1 2 3 4 5]);
winner=ids(order(1));
end
