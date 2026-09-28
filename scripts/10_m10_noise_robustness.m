%% M10: classification robustness versus SNR on test split
clear; clc; startup;
cfg=legacy.defaultConfig(); cfg=legacy.loadSelectedConfig(cfg); legacy.ensureDirs(cfg);
allR=table();
for k=1:numel(cfg.methods)
    method=upper(string(cfg.methods{k})); tag=lower(char(method));
    P=readtable(fullfile(cfg.output.metrics,[tag '_predictions.csv']),'TextType','string');
    P=P(P.split=="test",:);
    R=legacy.robustnessBySNR(P); R.method=repmat(method,height(R),1); R=movevars(R,'method','Before',1);
    writetable(R,fullfile(cfg.output.metrics,[tag '_robustness_snr.csv']));
    allR=[allR;R]; %#ok<AGROW>
end
writetable(allR,fullfile(cfg.output.metrics,'robustness_snr_all.csv'));
fig=figure('Visible','off','Color','w'); hold on;
for k=1:numel(cfg.methods)
    method=upper(string(cfg.methods{k})); q=allR.method==method & isfinite(allR.SNR_db);
    [x,ord]=sort(allR.SNR_db(q)); y=allR.macro_f1(q); y=y(ord);
    plot(x,y,'-o','DisplayName',method);
end
xlabel('SNR (dB)'); ylabel('Macro-F1'); grid on; legend('Location','best');
exportgraphics(fig,fullfile(cfg.output.figures,'macro_f1_vs_snr.png'),'Resolution',180); close(fig);
legacy.makeManifest('10_m10_noise_robustness',cfg,{'results/metrics/robustness_snr_all.csv','results/figures/macro_f1_vs_snr.png'},struct('split','test','status','provisional_current_dataset'));
