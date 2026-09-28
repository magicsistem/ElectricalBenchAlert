function out = dwtFeatures(x,Fs,wname,level,cfg)
%DWTFEATURES DWT representation, compact features and novelty score.
x = double(x(:));
wname = char(wname);
maxLevel = wmaxlev(numel(x),wname);
if level > maxLevel
    error('legacy:DWTLevel','Level %d exceeds wmaxlev=%d for %s.',level,maxLevel,wname);
end

[C,L] = wavedec(x,level,wname);
a = appcoef(C,L,wname,level);
detailEnergy = zeros(1,level);
detailMax = zeros(1,level);
detailN = zeros(1,level);
for j = 1:level
    d = detcoef(C,L,j);
    detailEnergy(j) = sum(abs(d).^2);
    detailMax(j) = max(abs(d));
    detailN(j) = numel(d);
end
approxEnergy = sum(abs(a).^2);
energies = [approxEnergy detailEnergy];
total = sum(energies);
p = energies ./ max(total,eps);
entropyNorm = -sum(p(p>0).*log2(p(p>0))) / max(log2(numel(p)),eps);

feat = struct();
feat.dwt_approx_energy_fraction = approxEnergy/max(total,eps);
feat.dwt_detail_energy_fraction = sum(detailEnergy)/max(total,eps);
feat.dwt_entropy_norm = entropyNorm;
feat.dwt_max_abs = max(abs(C));
[~,dom] = max(detailEnergy);
feat.dwt_dominant_detail_level = dom;
feat.dwt_highfreq_fraction = sum(detailEnergy(1:min(2,level)))/max(total,eps);
feat.dwt_lowdetail_fraction = sum(detailEnergy(max(1,level-1):level))/max(total,eps);
feat.dwt_coeff_rms = sqrt(mean(abs(C).^2));

for j = 1:level
    feat.(sprintf('dwt_E_D%d',j)) = detailEnergy(j)/max(total,eps);
    feat.(sprintf('dwt_Max_D%d',j)) = detailMax(j);
    feat.(sprintf('dwt_N_D%d',j)) = detailN(j);
end

% Time localization score: DWT detail reconstruction + cycle-RMS change.
detailLocal = zeros(size(x));
try
    for j = 1:level
        dr = wrcoef('d',C,L,wname,j);
        dr = dr(:);
        if numel(dr) >= numel(x)
            detailLocal = detailLocal + dr(1:numel(x)).^2;
        end
    end
    detailLocal = sqrt(movmean(detailLocal,max(3,round(Fs*0.001))));
    detailLocal = detailLocal/max(median(detailLocal),eps);
catch
    detailLocal = zeros(size(x));
end
score = legacy.timeDomainNovelty(x,Fs,cfg.nominal_frequency_hz) + ...
        0.25*abs(detailLocal-median(detailLocal));

tmpC = C; tmpL = L; %#ok<NASGU>
w = whos('tmpC','tmpL');
bytes = sum([w.bytes]);

out = struct('features',feat,'local_score',score, ...
    'representation_bytes',bytes,'level',level,'wavelet',string(wname));
end
