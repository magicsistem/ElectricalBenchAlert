function report=run_window_runtime(method,mode)
%RUN_WINDOW_RUNTIME One window model per fresh batch on matched physical decision times.
if nargin<2,mode="reselection";end
mode=string(mode);assert(isscalar(mode)&&any(mode==["legacy","reselection"]),'eba:RuntimeMode','Unknown stream candidate mode.');
cfg=eba.config();method=upper(string(method));methods=["FFT","STFT","DWT","CWT","ST"];
assert(isscalar(method) && any(method==methods),'eba:RuntimeMethod','One retained DSP method is required.');
if mode=="reselection",prefix="reselection_stream_full";else,prefix="stream_full";end
R=load(fullfile(cfg.output,prefix+"_development.mat"),'retained');m=find(methods==method);chosen=R.retained{m};
assert(~isempty(chosen),'eba:RuntimeMethod','This representation has no retained feasible screening candidate.');
path=fullfile(cfg.output,'stream_models',prefix+"_"+lower(method)+".mat");M=load(path,'model');model=M.model;
settings=chosen.settings;[~,sha]=system('git rev-parse HEAD');settings.git_commit=strtrim(sha);
F=eba.families(cfg.families_per_cell,cfg);V=F(F.split=="validation",:);ids=zeros(11,1);
for c=2:12,ids(c-1)=find(V.class_id==c & V.severity_stratum==3 & V.duration_stratum==4,1);end
assert(all(ids>0));schedule=eba.continuousSchedule(V(ids,:),cfg,20,"runtime_shared_sequence",cfg.stream_seed+90000);
settings.sequence_id=schedule.sequence_id;
[x,~,~]=eba.continuousSignal(schedule,(0:schedule.n_samples-1)',cfg);
% All candidates see the same one-hundred physical end instants; their own trailing length differs.
firstEnd=round(cfg.Fs*max(cfg.stream_window_cycles)/cfg.nominal_frequency_hz);
ends=round(linspace(firstEnd,schedule.n_samples,cfg.runtime_repetitions));
assert(all(diff(ends)>0) && model.window_samples<=firstEnd,'eba:RuntimeWorkload','Matched decision endpoints must be valid and unique.');
for w=1:cfg.runtime_warmups
    idx=ends(1)-model.window_samples+1:ends(1);v=eba.features(x(idx),cfg.Fs,model.method,model.parameters);
    [label,confidence]=eba.predict(model,v);[grade,physical]=eba.severity(x(idx),cfg.classes(label),cfg.Fs);
    pred=struct('window_start_s',(idx(1)-1)/cfg.Fs,'window_end_s',ends(1)/cfg.Fs, ...
        'decision_time_s',ends(1)/cfg.Fs,'class_id',label,'confidence',confidence,'severity',grade, ...
        'voltage_rms_pu_min',physical.voltage_rms_pu_min);
    eba.stateStep([],pred,settings);
end
before=eba.processMemory();state=[];values=zeros(numel(ends),8);phases=strings(numel(ends),1);
for w=1:numel(ends)
    totalTimer=tic;idx=ends(w)-model.window_samples+1:ends(w);signal=x(idx);
    timer=tic;[v,~,bytes]=eba.features(signal,cfg.Fs,model.method,model.parameters);tf=toc(timer);
    timer=tic;[label,confidence]=eba.predict(model,v);tc=toc(timer);
    timer=tic;[grade,physical]=eba.severity(signal,cfg.classes(label),cfg.Fs);ts=toc(timer);
    pred=struct('window_start_s',(idx(1)-1)/cfg.Fs,'window_end_s',ends(w)/cfg.Fs, ...
        'decision_time_s',ends(w)/cfg.Fs,'class_id',label,'confidence',confidence,'severity',grade, ...
        'voltage_rms_pu_min',physical.voltage_rms_pu_min);
    timer=tic;[state,~,~]=eba.stateStep(state,pred,settings);te=toc(timer);total=toc(totalTimer);
    values(w,:)=[w,ends(w),tf,tc,ts,te,total,bytes];phases(w)=state.phase;
end
after=eba.processMemory();timings=array2table(values,'VariableNames',{'workload_index','decision_end_sample', ...
    'feature_s','classification_s','severity_s','state_s','total_s','representation_bytes'});timings.state=phases;
assert(all(isfinite(values),'all') && all(values(:,3:7)>=0,'all') && all(values(:,7)>=max(values(:,3:6),[],2)), ...
    'eba:RuntimeTiming','Invalid measured stage timing.');
bytes=dir(path);report=struct('method',method,'classifier','SVM','model_path',erase(path,[cfg.root filesep]), ...
    'model_sha256',eba.hash(path,'file'),'model_serialized_bytes',bytes.bytes,'window_samples',model.window_samples, ...
    'hop_samples',model.hop_samples,'n_repetitions',numel(ends),'warmups',cfg.runtime_warmups, ...
    'shared_signal_sha256',eba.hash(x,'numeric'),'shared_endpoints_sha256',eba.hash(ends,'numeric'), ...
    'actual_window_workload_sha256',eba.hash(jsonencode(struct('shared_signal_sha256',eba.hash(x,'numeric'), ...
        'end_samples',ends,'window_samples',model.window_samples))), ...
    'startup_and_model_RSS_bytes',before.rss_bytes,'peak_process_RSS_bytes',after.hwm_bytes, ...
    'representation_bytes_median',median(timings.representation_bytes), ...
    'policy','one model per fresh MATLAB batch; two inference warmups; 100 identical physical decision endpoints on one shared validation signal; model-specific arrived trailing windows; data generation, artifact I/O and report construction excluded', ...
    'timing_scope','compute-only matched workloads include feature extraction, calibrated classification, arrived-window severity and state transitions; sparse benchmark endpoints do not estimate functional detection latency', ...
    'memory_scope','whole MATLAB-session Linux high-water RSS upper bound, not isolated model peak', ...
    'n_NORMAL',sum(phases=="NORMAL"),'n_SUSPECTED',sum(phases=="SUSPECTED"), ...
    'n_CONFIRMED',sum(phases=="CONFIRMED"),'n_RECOVERY',sum(phases=="RECOVERY"));
for name=["feature","classification","severity","state","total"]
    q=quantile(timings.(name+"_s"),[.5 .95 .99]);report.(name+"_median_s")=q(1);
    report.(name+"_p95_s")=q(2);report.(name+"_p99_s")=q(3);
end
report.throughput_windows_per_s=height(timings)/sum(timings.total_s);
report.streaming_real_time_factor_p95=report.total_p95_s/(model.hop_samples/cfg.Fs);
report.throughput_input_samples_per_s=model.hop_samples*report.throughput_windows_per_s;
if mode=="reselection",id="runtime_reselection_stream_"+lower(method);else,id="runtime_stream_"+lower(method);end
paths=[fullfile(cfg.output,id+".csv");fullfile(cfg.output,id+".json")];
writetable(timings,paths(1));eba.json(paths(2),report);
eba.manifest(id,cfg,struct('method',method,'classifier','SVM','parameters',model.parameters, ...
    'hyperparameters',model.hyperparameters,'warmups',cfg.runtime_warmups,'repetitions',cfg.runtime_repetitions, ...
    'shared_signal_sha256',report.shared_signal_sha256,'shared_endpoints_sha256',report.shared_endpoints_sha256),[paths;string(path)]);
fprintf('WINDOW_RUNTIME_PASS method=%s p95_s=%.6g compute_hop=%.6g\n',method,report.total_p95_s,report.streaming_real_time_factor_p95);
end
