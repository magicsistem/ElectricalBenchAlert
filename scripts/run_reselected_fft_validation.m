function report=run_reselected_fft_validation()
%RUN_RESELECTED_FFT_VALIDATION Resume the selected full-train FFT candidate on validation only.
cfg=eba.config();prefix="reselection_stream_full";modelPath=fullfile(cfg.output,'stream_models',prefix+"_fft.mat");
state=load(fullfile(cfg.output,'reselection_state_refinement.mat'),'retained');modelFile=load(modelPath,'model');model=modelFile.model;
ix=find(cellfun(@(q)~isempty(q)&&q.model.method=="FFT",state.retained));
assert(isscalar(ix),'eba:ReselectionModel','One refined FFT candidate is required.');candidate=state.retained{ix};
F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test",:);V=F(F.split=="validation",:);
levels=[Inf 20 5];schedules=cell(height(V)*(1+2*cfg.noise_realizations),1);k=0;
for i=1:height(V)
    for z=1:numel(levels)
        count=cfg.noise_realizations;if z==1,count=1;end
        for realization=1:count
            k=k+1;id="full_validation_"+V.family_id(i)+"_snr"+levels(z)+"_r"+realization;
            schedules{k}=eba.continuousSchedule(V(i,:),cfg,levels(z),id, ...
                mod(cfg.stream_seed+double(V.family_seed(i)),2^32),"development",realization);
        end
    end
end
assert(k==numel(schedules)&&all(V.split=="validation"), ...
    'eba:TestFirewall','Only declared validation schedules are allowed.');
pool=gcp('nocreate');if isempty(pool)
    cluster=parcluster('local');requested=8;try,cluster.NumWorkers=requested;pool=parpool(cluster,requested);
    catch e,fallback=min(4,cluster.NumWorkers);fprintf('VALIDATION_POOL_FALLBACK requested=%d fallback=%d reason=%s\n',requested,fallback,e.message);pool=parpool(cluster,fallback);end
end
fprintf('RESELECTED_VALIDATION_POOL workers=%d sequences=%d\n',pool.NumWorkers,numel(schedules));
predictions=cell(size(schedules));
parfor i=1:numel(schedules)
    predictions{i}=eba.streamPredictions(schedules{i},model,cfg,modelPath,true);
end
settings=candidate.settings;settings.model_version=model.model_version;settings.git_commit=model.training_git_commit;
[metrics,details]=eba.evaluateStreamEvidence(schedules,predictions,settings,cfg);
rtf=quantile(details.exploratory_inference_times_s,.95)/(model.hop_samples/cfg.Fs);
report=metrics;report.method="FFT";report.classifier="SVM";report.window_cycles=model.window_cycles;
report.hop_samples=model.hop_samples;report.stream_RTF_p95=rtf;report.n_validation_families=height(V);
report.n_validation_sequences=numel(schedules);report.model_sha256=eba.hash(modelPath,'file');
report.scope='full validation only; test not loaded; single preselected candidate';
jsonPath=fullfile(cfg.output,'reselection_fft_full_validation.json');csvPath=fullfile(cfg.output,'reselection_fft_full_validation.csv');
eba.json(jsonPath,report);writetable(struct2table(report,'AsArray',true),csvPath);
eba.manifest('reselection_fft_full_validation',cfg,struct('scope',report.scope,'method','FFT','classifier','SVM', ...
    'parameters',model.parameters,'hyperparameters',model.hyperparameters,'n_validation_families',height(V), ...
    'n_validation_sequences',numel(schedules),'model_sha256',report.model_sha256, ...
    'selection_source','finite validation-only screening and state-refinement grids; no test access'),{jsonPath,csvPath});
fprintf('RESELECTED_FFT_VALIDATION_PASS eventF1=%.6f false_alarms_per_min=%.6f RTF_p95=%.6f test_accessed=0\n', ...
    report.f1,report.false_alarms_per_minute,rtf);
end
