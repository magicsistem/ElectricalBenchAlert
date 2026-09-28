function p=windowParameters(method,p,N)
%WINDOWPARAMETERS Explicit constrained adaptation of offline configuration to shorter records.
method=upper(string(method));
if method=="STFT",p.stft.window_samples=min(p.stft.window_samples,N);end
if method=="DWT"
    limit=wmaxlev(N,char(p.dwt.wavelet));assert(limit>=1,'eba:WindowDWT','No feasible wavelet level.');
    p.dwt.level=min(p.dwt.level,limit);
end
p.expected_samples=N;
end
