function out = cwtFeatures(x,Fs,cfg)
%CWTFEATURES CWT filterbank features using Wavelet Toolbox.
x = double(x(:));
fmin = max(1,cfg.cwt.min_frequency_hz);
fmax = min([cfg.cwt.max_frequency_hz,0.45*Fs,Fs/2-eps]);
if fmin >= fmax
    error('legacy:CWTFrequencyLimits','Invalid CWT frequency limits.');
end
fb = cwtfilterbank( ...
    'SignalLength',numel(x), ...
    'SamplingFrequency',Fs, ...
    'VoicesPerOctave',cfg.cwt.voices_per_octave, ...
    'FrequencyLimits',[fmin fmax]);
[coef,f] = wt(fb,x);
power = abs(coef).^2;
[feat,timeScore] = legacy.tfSummaryFeatures(power,f,'cwt');
timeScore = timeScore + 0.35*legacy.timeDomainNovelty(x,Fs,cfg.nominal_frequency_hz);

tmp = coef; %#ok<NASGU>
w = whos('tmp');
bytes = w.bytes;
out = struct('features',feat,'local_score',timeScore, ...
    'representation_bytes',bytes,'frequencies_hz',f(:));
end
