function [labels,confidence,probabilities,raw_scores] = rawPredict(model,X)
%RAWPREDICT Nominal pu waveforms; calibrated log-softmax evidence, no record normalization.
assert(isstruct(model) && isfield(model,'network') && isa(model.network,'dlnetwork') && ...
    isfield(model,'sequence_samples') && isfield(model,'classes') && isfield(model,'temperature'), ...
    'eba:RawModel','A fitted raw-waveform model is required.');
if isnumeric(X) && isvector(X), X={X}; end
assert(iscell(X) && ~isempty(X),'eba:RawInput','Supply a waveform vector or cells of waveform vectors.');
X=X(:);
for i=1:numel(X)
    x=X{i}; assert(isnumeric(x) && isreal(x) && isvector(x) && numel(x)==model.sequence_samples && all(isfinite(x(:))), ...
        'eba:RawInput','Waveform input must be a finite real vector of the fitted sample length.');
    X{i}=single(x(:)');
end
assert(isscalar(model.temperature) && isfinite(model.temperature) && model.temperature>0, ...
    'eba:RawTemperature','Temperature must be finite and positive.');
scores=minibatchpredict(model.network,X,'InputDataFormats','CTB','OutputDataFormats','BC', ...
    'MiniBatchSize',64,'ExecutionEnvironment','cpu');
if isa(scores,'dlarray'), scores=extractdata(scores); end
scores=double(scores);
assert(isequal(size(scores),[numel(X) numel(model.classes)]) && all(isfinite(scores),'all') && ...
    all(scores>=0,'all') && all(abs(sum(scores,2)-1)<1e-5), 'eba:RawOutput','Softmax output is invalid.');
% Network probabilities are single, but calibration/normalization use double.
raw_scores=log(max(scores,double(realmin('single'))));
a=raw_scores/model.temperature; a=a-max(a,[],2);
probabilities=exp(a); probabilities=probabilities./sum(probabilities,2);
[confidence,index]=max(probabilities,[],2); labels=double(model.classes(index)); labels=labels(:);
end
