function result=streamPredictions(schedule,model,cfg,modelPath,useCache)
%STREAMPREDICTIONS Arrived windows only; reusable development prediction workload.
if nargin<5,useCache=false;end
assert(islogical(useCache) && isscalar(useCache),'eba:StreamCache','Cache control must be logical.');
N=model.window_samples;hop=model.hop_samples;
assert(N>=4 && N==fix(N) && hop>=1 && hop==fix(hop) && hop<=N && schedule.n_samples>=N, ...
    'eba:StreamWindow','A nonempty valid arrived-window workload is required.');
% Validate schedule/SNR/access before lookup; JSON alone cannot distinguish Inf and NaN.
eba.continuousSignal(schedule,0,cfg);
assert(isfile(modelPath),'eba:StreamModel','A serialized source model is required.');
persistent validatedPath validatedBytes validatedDatenum validatedModel validatedModelHash
fileInfo=dir(modelPath);assert(isscalar(fileInfo)&&fileInfo.bytes>0,'eba:StreamModel','Serialized model file is empty.');
if isempty(validatedPath) || ~strcmp(validatedPath,modelPath) || ...
        validatedBytes~=fileInfo.bytes || validatedDatenum~=fileInfo.datenum
    stored=load(modelPath,'model');
    assert(isfield(stored,'model'),'eba:StreamModel','Serialized model payload is missing.');
    validatedPath=modelPath;validatedBytes=fileInfo.bytes;validatedDatenum=fileInfo.datenum;
    validatedModel=stored.model;validatedModelHash=eba.hash(modelPath,'file');
end
assert(isequaln(model.fitted,validatedModel.fitted), ...
    'eba:StreamModelMutation','In-memory fitted weights differ from the serialized cache authority.');
fields={'kind','classes','mean','scale','keep','temperature','calibrated','hyperparameters','seed','window_samples','parameters'};
for name=fields
    assert(isfield(validatedModel,name{1}) && isequaln(model.(name{1}),validatedModel.(name{1})), ...
        'eba:StreamModelMutation','In-memory preprocessing or window representation differs from the serialized model: %s',name{1});
end
sources={'+eba/streamPredictions.m','+eba/features.m','+eba/predict.m','+eba/severity.m', ...
    '+eba/continuousSignal.m','+eba/waveform.m','+eba/hash.m'};
digests=cellfun(@(p) eba.hash(fullfile(cfg.root,p),'file'),sources,'UniformOutput',false);
actualConfig=rmfield(cfg,{'root','output'});
predictionContract=struct('kind',model.kind,'classes',model.classes,'mean',model.mean, ...
    'scale',model.scale,'keep',model.keep,'temperature',model.temperature,'calibrated',model.calibrated, ...
    'hyperparameters',model.hyperparameters,'seed',model.seed);
key=eba.hash(jsonencode(struct('schedule',schedule,'window_samples',N,'hop_samples',hop, ...
    'parameters',model.parameters,'prediction_contract',predictionContract,'model_sha256',validatedModelHash,'source_sha256',{digests}, ...
    'config_sha256',eba.hash(jsonencode(actualConfig)),'MATLAB_version',version, ...
    'toolbox_versions_sha256',eba.hash(jsonencode(ver)))));
folder=fullfile(cfg.output,'stream_prediction_cache');if ~isfolder(folder),mkdir(folder);end
path=fullfile(folder,key+".mat");ends=N:hop:schedule.n_samples;
if useCache && isfile(path)
    saved=load(path,'result','signature','numeric_sha256','metadata_sha256');result=saved.result;
    assert(strcmp(saved.signature,key) && height(result)==numel(ends) && ...
        strcmp(saved.numeric_sha256,eba.hash(result{:,vartype('numeric')},'numeric')) && ...
        strcmp(saved.metadata_sha256,eba.hash(jsonencode(table2struct(result)))), ...
        'eba:StreamCacheMutation','Cached window predictions differ from stored content hashes.');
    return;
end
result=table('Size',[numel(ends) 10],'VariableTypes',[repmat({'double'},1,9),{'string'}], ...
    'VariableNames',{'window_start_s','window_end_s','decision_time_s','class_id','confidence', ...
    'feature_time_s','classification_time_s','voltage_rms_pu_min','severity_time_s','severity'});
% Render each deterministic sample once; overlapping windows are views of this sequence.
signal=eba.continuousSignal(schedule,(0:schedule.n_samples-1)',cfg);
featureMatrix=zeros(numel(ends),numel(model.mean));featureTimes=zeros(numel(ends),1);
for w=1:numel(ends)
    idx=(ends(w)-N:ends(w)-1)';x=signal(idx+1);
    timer=tic;featureMatrix(w,:)=eba.features(x,cfg.Fs,model.method,model.parameters);featureTimes(w)=toc(timer);
end
timer=tic;[labels,confidences]=eba.predict(model,featureMatrix);classificationPerWindow=toc(timer)/numel(ends);
for w=1:numel(ends)
    idx=(ends(w)-N:ends(w)-1)';x=signal(idx+1);label=labels(w);confidence=confidences(w);
    timer=tic;[grade,physical]=eba.severity(x,cfg.classes(label),cfg.Fs);ts=toc(timer);
    result(w,:)={idx(1)/cfg.Fs,ends(w)/cfg.Fs,ends(w)/cfg.Fs,label,confidence, ...
        featureTimes(w),classificationPerWindow,physical.voltage_rms_pu_min,ts,grade};
end
assert(all(isfinite(result{:,vartype('numeric')}),'all'),'eba:StreamPrediction','Nonfinite window evidence.');
if useCache
    signature=key;numeric_sha256=eba.hash(result{:,vartype('numeric')},'numeric');
    metadata_sha256=eba.hash(jsonencode(table2struct(result)));save(path,'result','signature','numeric_sha256','metadata_sha256','-v7');
end
end
