%% M8: detection latency and event-boundary errors when ground truth is finite
clear; clc; startup;
cfg=legacy.defaultConfig(); cfg=legacy.loadSelectedConfig(cfg); legacy.ensureDirs(cfg);
rows={}; rr=0;
for k=1:numel(cfg.methods)
    method=upper(string(cfg.methods{k})); tag=lower(char(method));
    S=load(fullfile(cfg.output.features,[tag '_features.mat']),'F'); F=S.F;
    for split=["validation","test"]
        X=F(F.split==split,:);
        tm=legacy.temporalMetrics(X);
        rr=rr+1; rows(rr,:)={char(method),char(split),tm.n_applicable,tm.n_detected,tm.detection_rate,tm.mean_latency_s,tm.median_latency_s,tm.mae_start_s,tm.mae_end_s,tm.p95_abs_start_s,tm.p95_abs_end_s}; %#ok<SAGROW>
        writetable(tm.rows,fullfile(cfg.output.metrics,sprintf('%s_%s_temporal_rows.csv',tag,split)));
    end
end
R=cell2table(rows,'VariableNames',{'method','split','n_applicable','n_detected','detection_rate','mean_latency_s','median_latency_s','mae_start_s','mae_end_s','p95_abs_start_s','p95_abs_end_s'});
writetable(R,fullfile(cfg.output.metrics,'temporal_summary.csv'));
legacy.makeManifest('08_m8_temporal_metrics',cfg,{'results/metrics/temporal_summary.csv'},struct('note','Only finite event_start_s/event_end_s rows are applicable.'));
disp(R);
