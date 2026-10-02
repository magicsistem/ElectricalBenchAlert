function path=prepare_six_model_streambench_inputs()
%PREPARE_SIX_MODEL_STREAMBENCH_INPUTS Retain only the paired 864-family workload.
cfg=eba.config();folder=fullfile(cfg.output,'six_model_stream');if ~isfolder(folder),mkdir(folder);end
lightSource=fullfile(cfg.output,'reselection_stream_full_development.mat');
heavySource=fullfile(cfg.output,'rf_stream_development.mat');
L=load(lightSource,'models','retained','summary','schedules');
assert(height(L.summary)==3 && numel(L.schedules)==6048 && ...
    isequal(string(L.summary.method(:)),["FFT";"STFT";"DWT"]), ...
    'eba:CompactInputsLight','Expected the three frozen SVM finalists and full 6,048-schedule validation pool.');
ids=2:7:numel(L.schedules);schedules=L.schedules(ids);
assert(numel(schedules)==864 && all(cellfun(@(s)s.snr_db==20 && s.noise_realization==1,schedules)), ...
    'eba:CompactInputsSchedule','Expected one paired 20 dB realization per validation family.');
retained=cell(3,1);for i=1:3,retained{i}=struct('settings',L.retained{i}.settings);end
light=struct('models',{L.models(1:3)},'retained',{retained},'summary',L.summary,'schedules',{schedules});
H=load(heavySource,'candidateSets','summary');
assert(height(H.summary)==3 && isequal(string(H.summary.method(:)),["FFT";"ST";"CWT"]), ...
    'eba:CompactInputsHeavy','Expected the three validation-selected RF representations.');
candidateSets=cell(3,1);
for i=1:3
    p=H.candidateSets{i};m=p.model;
    metadata=struct('method',m.method,'parameters',m.parameters,'window_samples',m.window_samples, ...
        'window_cycles',m.window_cycles,'hop_samples',m.hop_samples,'hyperparameters',m.hyperparameters);
    candidateSets{i}=struct('model',metadata,'settings',p.settings);
end
heavy=struct('candidateSets',{candidateSets},'summary',H.summary(:,{'method'}));
path=fullfile(folder,'streambench_inputs.mat');
save(path,'light','heavy','-v7.3');
eba.manifest('six_model_streambench_inputs',cfg,struct('scope','minimum paired validation inputs for six model streambench; one 20 dB sequence per each of 864 validation families', ...
    'light_source_sha256',eba.hash(lightSource,'file'),'heavy_source_sha256',eba.hash(heavySource,'file'), ...
    'full_schedule_count',numel(L.schedules),'retained_schedule_count',numel(schedules), ...
    'test_accessed',false),{path,lightSource,heavySource});
fprintf('SIX_MODEL_INPUTS_PREPARED schedules=%d bytes=%d\n',numel(schedules),dir(path).bytes);
end
