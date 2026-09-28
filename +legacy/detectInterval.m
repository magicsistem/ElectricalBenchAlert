function [start_s,end_s,mask,threshold] = detectInterval(score,Fs,eventCfg)
%DETECTINTERVAL Robust interval detector from a non-negative novelty score.
score = double(score(:));
if isempty(score) || all(~isfinite(score))
    start_s = NaN; end_s = NaN; mask = false(size(score)); threshold = NaN; return;
end
score(~isfinite(score)) = 0;
smoothN = max(1,round(eventCfg.smooth_ms*1e-3*Fs));
if smoothN > 1, score = movmean(score,smoothN); end

med = median(score);
robustSigma = 1.4826 * median(abs(score-med));
if robustSigma <= eps
    robustSigma = std(score);
end
if robustSigma <= eps
    start_s = NaN; end_s = NaN; mask = false(size(score)); threshold = med; return;
end
threshold = med + eventCfg.threshold_mad*robustSigma;
mask = score > threshold;

minN = max(1,round(eventCfg.min_event_ms*1e-3*Fs));
if any(mask) && minN > 1
    d = diff([false;mask;false]);
    starts = find(d==1); stops = find(d==-1)-1;
    for k = 1:numel(starts)
        if stops(k)-starts(k)+1 < minN
            mask(starts(k):stops(k)) = false;
        end
    end
end

if ~any(mask)
    start_s = NaN; end_s = NaN; return;
end
idx = find(mask);
start_s = (idx(1)-1)/Fs;
end_s = (idx(end)-1)/Fs;
end
