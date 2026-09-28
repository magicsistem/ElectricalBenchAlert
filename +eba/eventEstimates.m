function estimated=eventEstimates(confirmed,completed,observed_until_s)
%EVENTESTIMATES Count every emitted confirmation; mark unfinished intervals right censored.
assert(isnumeric(observed_until_s) && isscalar(observed_until_s) && isfinite(observed_until_s) && observed_until_s>0, ...
    'eba:EventBoundary','An actual finite observation boundary is required.');
estimated=table('Size',[0 7],'VariableTypes',{'string','double','double','double','double','double','double'}, ...
    'VariableNames',{'sequence_id','class_id','estimated_start_s','estimated_end_s','confirmation_time_s','observed_until_s','confirmation_support_end_s'});
if isempty(confirmed),assert(isempty(completed),'eba:EventIdentity','Completed event has no confirmation.');return;end
ids=string({confirmed.event_id});assert(numel(unique(ids))==numel(ids),'eba:EventIdentity','Duplicate confirmations.');
ended=strings(0,1);if ~isempty(completed),ended=string({completed.event_id});end
assert(numel(unique(ended))==numel(ended) && all(ismember(ended,ids)), ...
    'eba:EventIdentity','Completed events must correspond to unique emitted confirmations.');
for i=1:numel(confirmed)
    e=confirmed(i);k=find(ended==ids(i));finish=NaN;
    if ~isempty(k)
        c=completed(k);assert(c.confirmation_time_s==e.confirmation_time_s && c.class_id==e.class_id && ...
            c.estimated_start_s==e.estimated_start_s && string(c.sequence_id)==string(e.sequence_id), ...
            'eba:EventIdentity','Completion changed immutable confirmation evidence.');
        finish=c.estimated_end_s;
    end
    estimated(end+1,:)={e.sequence_id,e.class_id,e.estimated_start_s,finish,e.confirmation_time_s,observed_until_s,e.last_supporting_window_end_s}; %#ok<AGROW>
end
end
