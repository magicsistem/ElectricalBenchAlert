function [feat,timeScore] = tfSummaryFeatures(power,freq,prefix)
%TFSUMMARYFEATURES Shared compact descriptors for CWT/STFT/S-Transform.
power = double(power);
freq = double(freq(:));
if size(power,1) ~= numel(freq)
    error('legacy:TFShape','Rows of power must match frequency vector.');
end
total = sum(power(:));
if total <= eps, total = eps; end
rowEnergy = sum(power,2);
timeEnergy = sum(power,1);

feat = struct();
bands = [0 120;120 600;600 1500;1500 inf];
names = {'low','harmonic','mid','high'};
for b = 1:size(bands,1)
    mask = freq>=bands(b,1) & freq<bands(b,2);
    value = sum(rowEnergy(mask))/total;
    feat.(sprintf('%s_energy_%s',prefix,names{b})) = value;
end

nz = power(power>0);
pnz = nz/total;
entropyNorm = -sum(pnz.*log2(pnz)) / max(log2(numel(power)),eps);
feat.(sprintf('%s_entropy_norm',prefix)) = entropyNorm;
feat.(sprintf('%s_max_power_fraction',prefix)) = max(power(:))/total;
feat.(sprintf('%s_time_concentration',prefix)) = sum(max(power,[],1))/total;
feat.(sprintf('%s_frequency_centroid_hz',prefix)) = sum(freq.*rowEnergy)/total;
[~,idx] = max(rowEnergy);
feat.(sprintf('%s_dominant_frequency_hz',prefix)) = freq(idx);
feat.(sprintf('%s_total_log_energy',prefix)) = log10(total+eps);

te = timeEnergy(:);
te = te/max(median(te),eps);
timeScore = abs(te-median(te));
end
