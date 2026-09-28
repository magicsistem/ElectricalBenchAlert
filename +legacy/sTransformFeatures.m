function out = sTransformFeatures(x,Fs,cfg)
%STRANSFORMFEATURES Compact features from band-limited S-Transform.
[S,f] = legacy.sTransform(x,Fs,cfg);
power = double(abs(S).^2);
[feat,timeScore] = legacy.tfSummaryFeatures(power,f,'st');
timeScore = timeScore + 0.35*legacy.timeDomainNovelty(x,Fs,cfg.nominal_frequency_hz);
tmp = S; %#ok<NASGU>
w = whos('tmp');
out = struct('features',feat,'local_score',timeScore, ...
    'representation_bytes',w.bytes,'frequencies_hz',f(:));
end
