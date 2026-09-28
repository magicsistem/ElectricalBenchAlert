%% M11: grouped bootstrap, descriptive statistics and Pareto trade-off
clear; clc; startup;
cfg=legacy.defaultConfig(); cfg=legacy.loadSelectedConfig(cfg); rng(cfg.seed,'twister'); legacy.ensureDirs(cfg);
C=readtable(fullfile(cfg.output.metrics,'complexity.csv'),'TextType','string');
rows={}; rr=0;
for k=1:numel(cfg.methods)
    method=upper(string(cfg.methods{k})); tag=lower(char(method));
    P=readtable(fullfile(cfg.output.metrics,[tag '_predictions.csv']),'TextType','string');
    P=P(P.split=="test",:);
    ci=legacy.bootstrapMacroF1ByFamily(P,cfg.statistics.bootstrap_reps,cfg.statistics.alpha,cfg.seed+k);
    met=legacy.classificationMetrics(P.label,P.prediction,unique(P.label,'stable'));
    rob=legacy.robustnessBySNR(P);
    noisy=rob(isfinite(rob.SNR_db),:);
    % Simple reproducible robustness scalar: mean macro-F1 across the six noisy SNR levels.
    robustnessMean=mean(noisy.macro_f1,'omitnan');
    cx=C(C.method==method,:); assert(height(cx)==1,'Missing complexity row for %s.',method);
    rr=rr+1; rows(rr,:)={char(method),met.macro_f1,ci.lower,ci.upper,met.weighted_f1,robustnessMean,cx.median_time_s,cx.median_representation_bytes,cx.RTF}; %#ok<SAGROW>
end
R=cell2table(rows,'VariableNames',{'method','macro_f1','macro_f1_ci_low','macro_f1_ci_high','weighted_f1','mean_noisy_macro_f1','median_time_s','representation_bytes','RTF'});
R.pareto=legacy.paretoFront([R.macro_f1 R.mean_noisy_macro_f1 R.median_time_s R.representation_bytes],[1 1 -1 -1]);
writetable(R,fullfile(cfg.output.metrics,'final_tradeoff_provisional.csv'));
fig=figure('Visible','off','Color','w'); scatter(R.median_time_s,R.macro_f1,70,'filled'); text(R.median_time_s,R.macro_f1,"  "+R.method); xlabel('Median processing time (s)'); ylabel('Macro-F1'); grid on;
exportgraphics(fig,fullfile(cfg.output.figures,'pareto_f1_vs_runtime.png'),'Resolution',180); close(fig);
legacy.writeJson(fullfile(cfg.output.root,'M11_NOTICE.json'),struct( ...
    'status','PROVISIONAL','reason','Current frozen dataset is intentionally used unchanged; final publication claims require dataset revision/expansion.'));
legacy.makeManifest('11_m11_statistics_pareto',cfg,{'results/metrics/final_tradeoff_provisional.csv','results/figures/pareto_f1_vs_runtime.png'},struct('status','provisional_current_dataset'));
disp(R);
