function [S,freq] = sTransform(x,Fs,cfg)
%STRANSFORM Discrete band-limited Stockwell transform.
%
% S(tau,f) is approximated by demodulating x at each requested frequency
% and convolving with a Gaussian whose temporal sigma is proportional to 1/f.
% The frequency grid is explicit and reproducible; this is NOT an exhaustive
% all-FFT-bin S-transform.

x = double(x(:));
N = numel(x);
fmin = max(1,cfg.st.min_frequency_hz);
fmax = min([cfg.st.max_frequency_hz,0.45*Fs,Fs/2-eps]);
if fmin >= fmax, error('legacy:STFrequencyLimits','Invalid S-transform frequency limits.'); end

base = logspace(log10(fmin),log10(fmax),cfg.st.num_log_frequencies);
harmonics = cfg.nominal_frequency_hz*(1:floor(fmax/cfg.nominal_frequency_hz));
freq = unique([base(:);harmonics(:)]);
freq = freq(freq>=fmin & freq<=fmax);
freq = sort(freq);

t = (0:N-1)'/Fs;
S = complex(zeros(numel(freq),N,'single'));

for k = 1:numel(freq)
    f = freq(k);
    sigma = cfg.st.gaussian_sigma_factor/f;
    half = max(2,ceil(cfg.st.truncate_sigma*sigma*Fs));
    tg = (-half:half)'/Fs;
    g = exp(-0.5*(tg/sigma).^2);
    g = g/sum(g);
    carrier = x .* exp(-1i*2*pi*f*t);

    M = numel(g);
    nfft = 2^nextpow2(N+M-1);
    yy = ifft(fft(carrier,nfft).*fft(g,nfft));
    startIdx = floor((M-1)/2)+1;
    yy = yy(startIdx:startIdx+N-1);
    S(k,:) = single(yy.');
end
end
