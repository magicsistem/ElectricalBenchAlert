%% M4: band-limited S-Transform verification + representative maps
clear; clc; startup;
cfg=legacy.defaultConfig(); rng(cfg.seed,'twister'); legacy.ensureDirs(cfg);
T=legacy.loadMetadata(cfg);
classes=["normal","oscillatory_transient","impulsive_transient","notching"];
rows={}; rr=0;
for c=1:numel(classes)
    idx=find(T.label==classes(c) & isnan(T.SNR_db),1,'first');
    assert(~isempty(idx),'Missing clean representative for %s',classes(c));
    rec=legacy.loadRecord(T(idx,:),cfg);
    t0=tic; [S,f]=legacy.sTransform(rec.samples,rec.Fs,cfg); elapsed=toc(t0);
    out=legacy.sTransformFeatures(rec.samples,rec.Fs,cfg);
    rr=rr+1; rows(rr,:)={char(rec.signal_id),char(rec.label),elapsed,out.representation_bytes,numel(f)}; %#ok<SAGROW>
    fig=figure('Visible','off','Color','w');
    imagesc((0:numel(rec.samples)-1)/rec.Fs,f,abs(S)); axis xy; set(gca,'YScale','log');
    xlabel('Time (s)'); ylabel('Frequency (Hz)'); title("S-Transform — "+rec.signal_id,'Interpreter','none'); colorbar;
    exportgraphics(fig,fullfile(cfg.output.figures,"st_"+rec.signal_id+".png"),'Resolution',180); close(fig);
end
R=cell2table(rows,'VariableNames',{'signal_id','label','runtime_s','representation_bytes','n_frequencies'});
writetable(R,fullfile(cfg.output.metrics,'st_smoke.csv'));
legacy.makeManifest('04_m4_st_smoke',cfg,{'results/metrics/st_smoke.csv','results/figures/st_*.png'},struct('records',height(R)));
fprintf('M4_ST_SMOKE_OK: %d representatives\n',height(R));
