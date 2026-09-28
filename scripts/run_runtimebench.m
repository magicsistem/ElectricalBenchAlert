function report=run_runtimebench(method,kind)
%RUN_RUNTIMEBENCH Exactly one classical model per fresh MATLAB batch session.
cfg=eba.config();method=upper(string(method));kind=upper(string(kind));
assert(any(method==["FFT","STFT","DWT","CWT","ST"]) && any(kind==["SVM","RF"]),'eba:RuntimeMethod','Specify one DSP representation and classifier.');
path=fullfile(cfg.output,"model_"+lower(method)+"_"+lower(kind)+".mat");assert(isfile(path),'eba:RuntimeModel','Run classifier development first.');
S=load(path,'model');model=S.model;F=eba.families(cfg.families_per_cell,cfg);signals=cell(18,1);
for c=1:9
    row=find(F.class_id==c & F.split=="validation",1);
    signals{2*c-1}=eba.record(F(row,:),Inf,1,cfg,'development');signals{2*c}=eba.record(F(row,:),20,1,cfg,'development');
end
[report,timings]=eba.runtime(model,signals,cfg.Fs,cfg.clip_duration_s,cfg);
bytes=dir(path);report.model_serialized_bytes=bytes.bytes;report.training_time_s=model.training_time_s;
report.classifier=kind;report.representation=method;report.snr_workload=[Inf 20];report.noise_realization=1;
id="runtime_"+lower(method)+"_"+lower(kind);tablePath=fullfile(cfg.output,id+".csv");reportPath=fullfile(cfg.output,id+".json");
writetable(timings,tablePath);eba.json(reportPath,report);
eba.manifest(id,cfg,struct('workload_hash',report.workload_sha256,'method',method,'classifier',kind, ...
    'parameters',model.parameters,'hyperparameters',model.hyperparameters,'warmups',cfg.runtime_warmups,'repetitions',cfg.runtime_repetitions), ...
    {tablePath,reportPath,path});
fprintf('RUNTIME_BENCHMARK_PASS method=%s classifier=%s p95_s=%.6g peak_process_RSS_bytes=%.0f\n',method,kind,report.total_p95_s,report.peak_process_RSS_bytes);
end
