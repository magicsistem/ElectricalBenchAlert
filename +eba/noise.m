function [x,measured_snr] = noise(clean,snr_db,noise_seed)
%NOISE Paired Gaussian unit vector scaled to exact finite-record signal energy.
assert(isnumeric(clean) && isreal(clean) && isvector(clean) && numel(clean)>=2 && all(isfinite(clean(:))), ...
    'eba:NoiseInput','Noise input must be a finite real vector with at least two samples.');
assert(isscalar(snr_db) && isreal(snr_db) && (isfinite(snr_db) || snr_db==Inf), ...
    'eba:SNR','SNR must be finite or positive infinity.');
assert(isscalar(noise_seed) && isfinite(noise_seed) && noise_seed==fix(noise_seed) && noise_seed>=0 && noise_seed<2^32, ...
    'eba:NoiseSeed','Seed must be an unsigned 32-bit integer.');
clean=double(clean(:)); signalEnergy=sum(clean.^2);
assert(isfinite(signalEnergy) && signalEnergy>0,'eba:ZeroEnergy','SNR is undefined for zero or nonfinite signal energy.');
if snr_db==Inf, x=clean; measured_snr=Inf; return; end
r=RandStream('mt19937ar','Seed',noise_seed); z=randn(r,size(clean)); z=z-mean(z);
noiseEnergy=signalEnergy/10^(snr_db/10);
assert(isfinite(noiseEnergy) && noiseEnergy>0 && sum(z.^2)>0,'eba:NoiseEnergy','Requested noise energy is not representable.');
z=z*sqrt(noiseEnergy/sum(z.^2)); x=clean+z;
measured_snr=10*log10(signalEnergy/sum((x-clean).^2));
assert(all(isfinite(x)) && isfinite(measured_snr),'eba:NoiseEnergy','Added noise is not representable.');
end
