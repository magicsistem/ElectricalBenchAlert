function score = timeDomainNovelty(x,Fs,nominalFrequency)
%TIMEDOMAINNOVELTY Cycle-RMS deviation plus high-frequency residual energy.
x = double(x(:));
cycleN = max(4,round(Fs/nominalFrequency));
rmsEnv = sqrt(movmean(x.^2,cycleN));
base = median(rmsEnv);
ampScore = abs(rmsEnv-base) ./ max(base,eps);

smooth = movmean(x,cycleN);
residual = x-smooth;
hf = sqrt(movmean(residual.^2,max(3,round(cycleN/4))));
hf = hf ./ max(median(hf),eps);
score = ampScore + 0.25*abs(hf-median(hf));
end
