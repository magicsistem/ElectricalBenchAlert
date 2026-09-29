function report=run_runtimebench(method,kind,relativeModelPath)
%RUN_RUNTIMEBENCH Exactly one declared model per fresh MATLAB batch session.
cfg=eba.config();method=upper(string(method));kind=upper(string(kind));
raw=any(method==["CNN","TCN"]);
assert((~raw && any(method==["FFT","STFT","DWT","CWT","ST"]) && any(kind==["SVM","RF"])) || ...
    (raw && kind=="RAW"),'eba:RuntimeMethod','Specify one DSP representation/classifier or CNN/TCN RAW.');
if nargin<3
    assert(~raw,'eba:RuntimeModel','Raw timing requires its explicit model path from the training manifest.');
    relativeModelPath=fullfile('results','v2','deployment_models',"model_"+lower(method)+"_"+lower(kind)+".mat");
end
relativeModelPath=string(relativeModelPath);
assert(isscalar(relativeModelPath) && ~startsWith(relativeModelPath,'/') && ...
    ~any(ismember(split(relativeModelPath,filesep),["..",".",""])), ...
    'eba:RuntimeModel','Runtime model paths must be relative repository artifacts.');
path=fullfile(cfg.root,relativeModelPath);assert(isfile(path),'eba:RuntimeModel','Run training/native deployment compaction first.');
S=load(path,'model');model=S.model;assert(string(model.kind)==kind || (raw && string(model.kind)==method));
if raw,assert(~model.structural_test_only && model.sequence_samples==cfg.Fs*cfg.clip_duration_s);end
F=eba.families(cfg.families_per_cell,cfg);signals=cell(18,1);
for c=1:9
    row=find(F.class_id==c & F.split=="validation",1);
    signals{2*c-1}=eba.record(F(row,:),Inf,1,cfg,'development');signals{2*c}=eba.record(F(row,:),20,1,cfg,'development');
end
[report,timings]=eba.runtime(model,signals,cfg.Fs,cfg.clip_duration_s,cfg);
bytes=dir(path);report.model_serialized_bytes=bytes.bytes;report.training_time_s=model.training_time_s;
report.classifier=kind;report.representation=method;report.model_path=relativeModelPath;report.snr_workload=[Inf 20];report.noise_realization=1;
id="runtime_"+lower(method)+"_"+lower(kind);if raw,id=id+"_seed"+model.seed;end
tablePath=fullfile(cfg.output,id+".csv");reportPath=fullfile(cfg.output,id+".json");
writetable(timings,tablePath);eba.json(reportPath,report);
extra=struct('workload_hash',report.workload_sha256,'method',method,'classifier',kind, ...
    'warmups',cfg.runtime_warmups,'repetitions',cfg.runtime_repetitions,'model_path',relativeModelPath);
if raw,extra.parameters=model.architecture;extra.hyperparameters=struct('model_seed',model.seed); ...
else,extra.parameters=model.parameters;extra.hyperparameters=model.hyperparameters;end
if isfield(model,'training_git_commit'),extra.training_git_commit=model.training_git_commit;end
if isfield(model,'solver_configuration'),extra.solver_configuration=model.solver_configuration;end
eba.manifest(id,cfg,extra,{tablePath,reportPath,path});
fprintf('RUNTIME_BENCHMARK_PASS method=%s classifier=%s p95_s=%.6g peak_process_RSS_bytes=%.0f\n',method,kind,report.total_p95_s,report.peak_process_RSS_bytes);
end
