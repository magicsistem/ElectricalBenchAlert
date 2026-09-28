function R = benchmarkComplexity(cfg)
%BENCHMARKCOMPLEXITY M9 same-session runtime, RTF, throughput and representation bytes.
cfg=legacy.loadSelectedConfig(cfg);
T=legacy.loadMetadata(cfg);
% Deterministic balanced subset across classes, preferring clean records.
rng(cfg.seed,'twister');
classes=unique(T.label,'stable');
idx=[];
perClass=max(1,floor(cfg.benchmark.max_records_complexity/numel(classes)));
for k=1:numel(classes)
    cand=find(T.label==classes(k) & isnan(T.SNR_db));
    if isempty(cand), cand=find(T.label==classes(k)); end
    idx=[idx; cand(1:min(perClass,numel(cand)))]; %#ok<AGROW>
end
T=T(idx,:);
rows={}; rr=0;
for m=1:numel(cfg.methods)
    method=string(cfg.methods{m});
    allTimes=[]; bytes=[]; durations=[];
    for i=1:height(T)
        rec=legacy.loadRecord(T(i,:),cfg);
        for w=1:cfg.benchmark.warmup_repeats
            legacy.runMethod(method,rec.samples,rec.Fs,rec,cfg);
        end
        ts=zeros(cfg.benchmark.timing_repeats,1);
        last=[];
        for q=1:cfg.benchmark.timing_repeats
            last=legacy.runMethod(method,rec.samples,rec.Fs,rec,cfg);
            ts(q)=last.processing_time_s;
        end
        allTimes=[allTimes;ts]; %#ok<AGROW>
        bytes(end+1,1)=last.representation_bytes; %#ok<AGROW>
        durations(end+1,1)=rec.duration_s; %#ok<AGROW>
    end
    med=median(allTimes); p95=prctile(allTimes,95);
    dur=median(durations);
    rr=rr+1;
    rows(rr,:)={char(method),med,p95,median(bytes),med/dur,dur/med,1/med,numel(allTimes)}; %#ok<AGROW>
    fprintf('%s complexity: median %.4g s, RTF %.4g\n',method,med,med/dur);
end
R=cell2table(rows,'VariableNames',{'method','median_time_s','p95_time_s', ...
    'median_representation_bytes','RTF','realtime_throughput_x','records_per_s','n_timings'});
writetable(R,fullfile(cfg.output.metrics,'complexity.csv'));
end
