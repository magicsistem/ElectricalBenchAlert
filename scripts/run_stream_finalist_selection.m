function report=run_stream_finalist_selection()
%RUN_STREAM_FINALIST_SELECTION Choose from full-grid-refined validation candidates.
cfg=eba.config();path=fullfile(cfg.output,'reselection_state_refinement.csv');
assert(isfile(path),'eba:FinalistInputs','Run the corrected validation state refinement first.');
T=readtable(path,'TextType','string');methods=["FFT","STFT","DWT","CWT","ST"];
rows=cell(numel(methods),1);
for m=1:numel(methods)
    local=T(T.method==methods(m),:);assert(~isempty(local),'eba:FinalistInputs','Missing method rows.');
    finite=isfinite(local.event_f1)&isfinite(local.false_alarms_per_minute)& ...
        isfinite(local.matched_latency_s)&isfinite(local.stream_RTF_p95);
    eligible=find(finite&local.stream_RTF_p95<=1);
    if isempty(eligible)
        ix=find(finite);[~,ord]=sortrows([local.stream_RTF_p95(ix),-local.event_f1(ix)],[1 2]);ix=ix(ord(1));r=local(ix,:);
        feasible=false;front=false;
    else
        objective=[local.event_f1(eligible),-local.false_alarms_per_minute(eligible), ...
            -local.matched_latency_s(eligible),-local.stream_RTF_p95(eligible)];
        keep=eba.pareto(objective,ones(1,4));frontRows=eligible(keep);
        [~,ord]=sortrows([-local.event_f1(frontRows),local.matched_latency_s(frontRows),frontRows],[1 2 3]);
        ix=frontRows(ord(1));r=local(ix,:);feasible=true;front=true;
    end
    rows{m}=table(methods(m),r.event_f1,r.false_alarms_per_minute,r.matched_latency_s, ...
        r.stream_RTF_p95,r.threshold_off,r.recovery_windows,r.refractory_cycles,feasible,front, ...
        'VariableNames',{'method','event_f1','false_alarms_per_minute','matched_latency_s','stream_RTF_p95', ...
        'threshold_off','recovery_windows','refractory_cycles','rtf_feasible','pareto'});
end
summary=vertcat(rows{:});eligible=find(summary.rtf_feasible);assert(~isempty(eligible),'eba:FinalistFeasibility','No RTF-feasible candidate.');
obj=[summary.event_f1,-summary.false_alarms_per_minute,-summary.matched_latency_s,-summary.stream_RTF_p95];
summary.pareto(eligible)=eba.pareto(obj(eligible,:),ones(1,4));
front=find(summary.rtf_feasible&summary.pareto);[~,ord]=sortrows([-summary.event_f1(front),summary.matched_latency_s(front),front],[1 2 3]);
winner=front(ord(1));summary.selected=false(height(summary),1);summary.selected(winner)=true;
out=fullfile(cfg.output,'stream_reselection_finalists.csv');json=fullfile(cfg.output,'stream_reselection_finalists.json');
writetable(summary,out);report=struct('scope','finite validation screening and state-refinement grids; test not accessed', ...
    'criterion','highest event F1 among RTF p95 <= 1 Pareto candidates; false alarms, latency and RTF reported as objectives', ...
    'selected_method',summary.method(winner),'selected_event_f1',summary.event_f1(winner), ...
    'selected_false_alarms_per_minute',summary.false_alarms_per_minute(winner), ...
    'selected_matched_latency_s',summary.matched_latency_s(winner),'selected_stream_RTF_p95',summary.stream_RTF_p95(winner), ...
    'rows',table2struct(summary),'source_sha256',eba.hash(path,'file'));
eba.json(json,report);eba.manifest('stream_reselection_finalists',cfg,struct('scope',report.scope, ...
    'selection_rule',report.criterion,'selected_method',report.selected_method, ...
    'source_sha256',report.source_sha256),{out,json});
fprintf('STREAM_FINALIST_SELECTION_PASS selected=%s eventF1=%.6f false_alarms_per_min=%.6f RTF_p95=%.6f test_accessed=0\n', ...
    report.selected_method,report.selected_event_f1,report.selected_false_alarms_per_minute,report.selected_stream_RTF_p95);
end
