function out = fftAdapter(x,Fs,cfg)
%FFTADAPTER Prefer Source pq.analyzeFFT; otherwise use equivalent local baseline.
x = double(x(:));
usedSource = false;
if exist('pq.analyzeFFT','file') == 2
    r = pq.analyzeFFT(x,Fs,cfg.nominal_frequency_hz,cfg.fft.harmonic_orders);
    usedSource = true;
else
    n = numel(x);
    y = x-mean(x);
    k = (0:n-1)';
    win = 0.5-0.5*cos(2*pi*k/(n-1));
    cg = mean(win);
    z = fft(y.*win);
    half = floor(n/2)+1;
    z = z(1:half);
    f = (0:half-1)'*Fs/n;
    a = (2*abs(z)/(n*cg))/sqrt(2);
    a(1)=a(1)/2;
    mask = f>=0.8*cfg.nominal_frequency_hz & f<=1.2*cfg.nominal_frequency_hz;
    cand=find(mask); [~,li]=max(a(mask)); fi=cand(li);
    f1=f(fi); A1=a(fi);
    harms=zeros(size(cfg.fft.harmonic_orders));
    for q=1:numel(harms)
        [~,ii]=min(abs(f-cfg.fft.harmonic_orders(q)*f1));
        harms(q)=a(ii);
    end
    r = struct('fundamental_frequency_hz',f1,'fundamental_rms',A1, ...
        'harmonic_orders',cfg.fft.harmonic_orders, ...
        'harmonic_amplitudes_rms',harms, ...
        'thd_percent',100*sqrt(sum(harms.^2))/max(A1,eps), ...
        'spectral_energy',sum(y.^2), ...
        'frequencies_hz',f,'spectrum_rms',a);
end

feat = struct();
feat.fft_fundamental_hz = r.fundamental_frequency_hz;
feat.fft_fundamental_rms = r.fundamental_rms;
feat.fft_thd_percent = r.thd_percent;
feat.fft_log_energy = log10(r.spectral_energy+eps);
for q=1:numel(r.harmonic_orders)
    feat.(sprintf('fft_H%d_rms',r.harmonic_orders(q))) = r.harmonic_amplitudes_rms(q);
end
specPower = double(r.spectrum_rms(:)).^2;
total = sum(specPower)+eps;
p = specPower/total; p=p(p>0);
feat.fft_spectral_entropy_norm = -sum(p.*log2(p))/max(log2(numel(specPower)),eps);
feat.fft_spectral_centroid_hz = sum(double(r.frequencies_hz(:)).*specPower)/total;

score = legacy.timeDomainNovelty(x,Fs,cfg.nominal_frequency_hz);
tmp = r.spectrum_rms; %#ok<NASGU>
w=whos('tmp');
out=struct('features',feat,'local_score',score,'representation_bytes',w.bytes, ...
    'used_source',usedSource);
end
