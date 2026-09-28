%% M3: CWT implementation verification + representative scalograms
clear; clc; startup;
cfg=legacy.defaultConfig(); rng(cfg.seed,'twister'); legacy.ensureDirs(cfg);
T=legacy.loadMetadata(cfg);
classes=["normal","oscillatory_transient","impulsive_transient","notching"];
rows={}; rr=0;
for c=1:numel(classes)
    idx=find(T.label==classes(c) & isnan(T.SNR_db),1,'first');
    assert(~isempty(idx),'Missing clean representative for %s',classes(c));
    rec=legacy.loadRecord(T(idx,:),cfg);
    t0=tic; out=legacy.cwtFeatures(rec.samples,rec.Fs,cfg); elapsed=toc(t0);
    rr=rr+1; rows(rr,:)={char(rec.signal_id),char(rec.label),elapsed,out.representation_bytes,numel(out.frequencies_hz)}; %#ok<SAGROW>

    fb=cwtfilterbank('SignalLength',numel(rec.samples),'SamplingFrequency',rec.Fs, ...
        'VoicesPerOctave',cfg.cwt.voices_per_octave, ...
        'FrequencyLimits',[cfg.cwt.min_frequency_hz min(cfg.cwt.max_frequency_hz,0.45*rec.Fs)]);
    [coef,f]=wt(fb,rec.samples);
    fig=figure('Visible','off','Color','w');
    imagesc((0:numel(rec.samples)-1)/rec.Fs,f,abs(coef)); axis xy; set(gca,'YScale','log');
    xlabel('Time (s)'); ylabel('Frequency (Hz)'); title("CWT — "+rec.signal_id,'Interpreter','none'); colorbar;
    exportgraphics(fig,fullfile(cfg.output.figures,"cwt_"+rec.signal_id+".png"),'Resolution',180); close(fig);
end
R=cell2table(rows,'VariableNames',{'signal_id','label','runtime_s','representation_bytes','n_frequencies'});
writetable(R,fullfile(cfg.output.metrics,'cwt_smoke.csv'));
legacy.makeManifest('03_m3_cwt_smoke',cfg,{'results/metrics/cwt_smoke.csv','results/figures/cwt_*.png'},struct('records',height(R)));
fprintf('M3_CWT_SMOKE_OK: %d representatives\n',height(R));
