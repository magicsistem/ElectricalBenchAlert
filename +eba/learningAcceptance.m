function acceptance=learningAcceptance(learning,methods,cfg)
%LEARNINGACCEPTANCE Stable recent absolute changes and final family CI width.
methods=string(methods(:));required={'method','train_per_cell','macro_f1','ci_low','ci_high'};
assert(istable(learning) && all(ismember(required,learning.Properties.VariableNames)) && ...
    numel(unique(methods))==numel(methods) && isequal(sort(unique(string(learning.method))),sort(methods)), ...
    'eba:LearningCurve','Each declared method needs its full learning curve.');
acceptance=table(methods,false(numel(methods),1),zeros(numel(methods),1),zeros(numel(methods),1),zeros(numel(methods),1), ...
    'VariableNames',{'method','accepted','largest_recent_gain','largest_recent_absolute_change','final_ci_half_width'});
for m=1:numel(methods)
    t=sortrows(learning(string(learning.method)==methods(m),:),'train_per_cell');
    assert(height(t)>=3 && all(diff(t.train_per_cell)>0) && ...
        all(isfinite(t{:,{'macro_f1','ci_low','ci_high'}}),'all') && ...
        all(t.ci_low>=0 & t.ci_high<=1 & t.ci_low<=t.ci_high & t.macro_f1>=0 & t.macro_f1<=1), ...
        'eba:LearningCurve','Curves need three increasing sample sizes and finite bounded metrics.');
    gain=diff(t.macro_f1);recent=gain(end-1:end);width=(t.ci_high(end)-t.ci_low(end))/2;
    acceptance.largest_recent_gain(m)=max(recent);acceptance.largest_recent_absolute_change(m)=max(abs(recent));
    acceptance.final_ci_half_width(m)=width;
    acceptance.accepted(m)=all(abs(recent)<=cfg.learning_max_f1_gain) && width<=cfg.learning_ci_half_width;
end
end
