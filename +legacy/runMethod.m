function result = runMethod(method,samples,Fs,meta,cfg)
%RUNMETHOD Common M5 interface for FFT/STFT/DWT/CWT/S-Transform.
%
% result fields:
% prediction (filled later by classifier)
% processing_time_s
% features, feature_vector, feature_names
% detected_start_s, detected_end_s
% representation_bytes

method = upper(string(method));
rng(cfg.seed,'twister');
ticId = tic;
switch method
    case "FFT"
        r = legacy.fftAdapter(samples,Fs,cfg);
    case "STFT"
        r = legacy.stftAdapter(samples,Fs,cfg);
    case "DWT"
        r = legacy.dwtFeatures(samples,Fs,cfg.dwt.selected_wavelet,cfg.dwt.selected_level,cfg);
    case "CWT"
        r = legacy.cwtFeatures(samples,Fs,cfg);
    case {"ST","S-TRANSFORM","STRANSFORM"}
        r = legacy.sTransformFeatures(samples,Fs,cfg);
        method = "ST";
    otherwise
        error('legacy:UnknownMethod','Unknown method: %s',method);
end
processing = toc(ticId);
[start_s,end_s,~,threshold] = legacy.detectInterval(r.local_score,Fs,cfg.event);
[v,names] = legacy.structToFeatureVector(r.features);

result = struct();
result.method = method;
result.prediction = "";
result.processing_time_s = processing;
result.features = r.features;
result.feature_vector = v;
result.feature_names = names;
result.detected_start_s = start_s;
result.detected_end_s = end_s;
result.detection_threshold = threshold;
result.representation_bytes = r.representation_bytes;
if nargin >= 4 && ~isempty(meta)
    if isstruct(meta)
        if isfield(meta,'label'), result.label=string(meta.label); else, result.label=""; end
    elseif istable(meta)
        result.label=string(meta.label(1));
    else
        result.label="";
    end
else
    result.label="";
end
end
