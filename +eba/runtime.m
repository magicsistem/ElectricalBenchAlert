function [report,timings]=runtime(model,signals,Fs,hop_s,cfg)
%RUNTIME Same warmed workload; total decision includes representation and calibrated scores.
assert(iscell(signals) && ~isempty(signals) && all(cellfun(@(x) isnumeric(x)&&isvector(x)&&all(isfinite(x)),signals)), ...
    'eba:RuntimeSignals','Finite waveform cells are required.');
assert(isscalar(Fs)&&Fs>0 && isscalar(hop_s)&&hop_s>0,'eba:RuntimeSampling','Invalid sample/hop duration.');
counts=cellfun(@numel,signals);assert(all(counts==counts(1)),'eba:RuntimeWorkload','Every workload waveform must have identical length.');
assert(cfg.runtime_warmups>=0 && cfg.runtime_warmups==fix(cfg.runtime_warmups) && cfg.runtime_repetitions>=1 && ...
    cfg.runtime_repetitions==fix(cfg.runtime_repetitions),'eba:RuntimePolicy','Invalid warmup/repetition policy.');
raw=any(string(model.kind)==["CNN","TCN"]);before=eba.processMemory();
for r=1:cfg.runtime_warmups,decision(model,signals{1},Fs,raw);end
n=cfg.runtime_repetitions;values=zeros(n,5);
for r=1:n
    idx=mod(r-1,numel(signals))+1;[feature,classify,total,bytes]=decision(model,signals{idx},Fs,raw);
    values(r,:)=[idx,feature,classify,total,bytes];
end
after=eba.processMemory();timings=array2table(values,'VariableNames',{'workload_index','feature_s','classification_s','total_s','representation_bytes'});
report=struct('method',string(model.kind),'n_workload_waveforms',numel(signals),'n_repetitions',n, ...
    'warmups',cfg.runtime_warmups,'waveform_samples',counts(1),'window_duration_s',counts(1)/Fs,'hop_s',hop_s, ...
    'policy','one model per fresh MATLAB batch; two warmups; round-robin matched waveforms; no dataset generation/training inside timed loop', ...
    'startup_and_model_RSS_bytes',before.rss_bytes,'peak_process_RSS_bytes',after.hwm_bytes, ...
    'memory_scope',after.source,'representation_bytes_median',median(values(:,5)), ...
    'workload_sha256',eba.hash(strjoin(cellfun(@(x) eba.hash(x,'numeric'),signals,'UniformOutput',false),'')));
if ~raw,report.representation=string(model.method);else,report.trainable_parameters=model.architecture.learnable_parameters;end
for name=["feature","classification","total"]
    q=quantile(timings.(name+"_s"),[.5 .95 .99]);
    report.(name+"_median_s")=q(1);report.(name+"_p95_s")=q(2);report.(name+"_p99_s")=q(3);
end
report.throughput_windows_per_s=1/report.total_median_s;
report.window_real_time_factor=report.total_p95_s/(counts(1)/Fs);
report.streaming_real_time_factor=report.total_p95_s/hop_s;
report.throughput_input_samples_per_s=hop_s*Fs/report.total_median_s;
assert(all(isfinite(values),'all') && all(values(:,2:4)>=0,'all') && all(values(:,4)>=max(values(:,2:3),[],2)), ...
    'eba:RuntimeTiming','Invalid measured stage timing.');
end
function [feature,classify,total,bytes]=decision(model,x,Fs,raw)
start=tic;feature=0;bytes=0;
if raw
    stage=tic;eba.rawPredict(model,x);classify=toc(stage);
else
    stage=tic;[X,~,bytes]=eba.features(x,Fs,model.method,model.parameters);feature=toc(stage);
    stage=tic;eba.predict(model,X);classify=toc(stage);
end
total=toc(start);
end
