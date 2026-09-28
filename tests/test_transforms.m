function test_transforms()
%TEST_TRANSFORMS Known-signal controls; no dataset/test-family access.
cfg=eba.config(); Fs=cfg.Fs; N=10000; t=(0:N-1)'/Fs;
x=sqrt(2)*sin(2*pi*60*t+0.2); methods=["FFT","STFT","DWT","CWT","ST"];
allowlist=strings(1,0);
for method=methods
    [v,names,bytes,d]=eba.features(x,Fs,method,cfg);
    if isempty(allowlist), allowlist=names; end
    assert(isequal(names,allowlist)&&numel(v)==24&&isrow(v));
    assert(all(isfinite(v))&&bytes>0&&isa(d.coefficients,'single'));
    [doublev,doubleNames]=eba.features(2*x,Fs,method,cfg);
    assert(isequal(doubleNames,names)&&abs(doublev(1)-2*v(1))<1e-10);
    assert(abs(doublev(6)-2*v(6))<1e-10&&abs(doublev(7)-2*v(7))<1e-10);
    assert(abs(doublev(17)-v(17)-log10(4))<2e-5); % no waveform z-scoring
    zero=eba.features(zeros(N,1),Fs,method,cfg);
    assert(all(isfinite(zero))&&zero(1)==0&&all(zero(9:16)==0));
    [dc,~,~,dcDetail]=eba.features(ones(N,1)*2,Fs,method,cfg);
    assert(all(isfinite(dc))&&dc(1)==2&&dc(2)==2);
    if method=="FFT", assert(abs(dcDetail.fft_mean_square-4)<1e-8); end
    if method=="ST", assert(dcDetail.dc_coefficient==2); end
end
assert(numel(unique(allowlist))==24);
assert(~any(contains(allowlist,["class_id","family_id","record_id","severity","snr","label"])));

% Single-sided Parseval control includes DC, even Nyquist and odd/off-bin records.
for count=[9999 10000]
    offbin=0.37+sqrt(2)*sin(2*pi*60.137*(0:count-1)'/Fs+0.1);
    [~,~,~,d]=eba.features(offbin,Fs,"FFT",cfg);
    assert(abs(d.fft_mean_square-mean(offbin.^2))<2e-6);
end
nyquist=3*(-1).^(0:N-1)'; [~,~,~,d]=eba.features(nyquist,Fs,"FFT",cfg);
assert(d.one_sided_scale(end)==1&&abs(d.fft_mean_square-9)<1e-8);
[~,~,~,d]=eba.features(x,Fs,"FFT",cfg);
assert(abs(d.frequencies_hz(argmax(d.frequency_power_mass))-60)<1e-10);

% STFT correct endpoint scaling and exact edge support, including short inputs.
short=cfg; short.stft.window_samples=167;
for count=[167 500 503]
    [v,n,~,d]=eba.features(ones(count,1),Fs,"STFT",short);
    assert(numel(v)==24&&isequal(n,allowlist)&&d.one_sided_scale(1)==1);
    assert(abs(sum(abs(double(d.coefficients(:,1))).^2.*d.one_sided_scale)-1)<2e-6);
    coverage=false(count,1);
    for j=1:numel(d.frame_start_samples)
        first=d.frame_first_observed_samples(j)+1;
        coverage(first:first+d.frame_valid_samples(j)-1)=true;
    end
    assert(all(coverage));
end
even=cfg; even.stft.window_samples=500;
[~,~,~,d]=eba.features(nyquist,Fs,"STFT",even);
assert(d.one_sided_scale(end)==1);
assert(abs(sum(abs(double(d.coefficients(:,1))).^2.*d.one_sided_scale)-9)<2e-5);
for location=[1 503]
    edge=zeros(503,1); edge(location)=1;
    [~,~,~,d]=eba.features(edge,Fs,"STFT",short);
    assert(sum(abs(double(d.coefficients(:))).^2)>0);
end

% Every declared candidate has stable width; infeasible DWT levels are excluded.
for method=methods
    candidates=eba.transformCandidates(method,2000,cfg);
    assert(numel(unique(string({candidates.id})))==numel(candidates));
    for candidate=candidates
        [v,n]=eba.features(x(1:2000),Fs,method,candidate.parameters);
        assert(numel(v)==24&&isequal(n,allowlist)&&all(isfinite(v)));
    end
end
assert(numel(eba.transformCandidates("FFT",N,cfg))==1);
assert(numel(eba.transformCandidates("STFT",N,cfg))==16);
assert(numel(eba.transformCandidates("DWT",N,cfg))==35);
assert(numel(eba.transformCandidates("CWT",N,cfg))==4);
assert(numel(eba.transformCandidates("ST",N,cfg))==6);
assert(isempty(eba.transformCandidates("STFT",100,cfg)));
for candidate=eba.transformCandidates("DWT",500,cfg)
    p=candidate.parameters.dwt;
    assert(p.level<=wmaxlev(500,char(p.wavelet)));
end

% DWT reconstruction and global extension restoration, including non-sym caller.
original=dwtmode('status','nodisp'); cleanup=onCleanup(@() dwtmode(original,'nodisp'));
dwtmode('per','nodisp'); [~,~,~,d]=eba.features(x,Fs,"DWT",cfg);
assert(strcmp(dwtmode('status','nodisp'),'per'));
assert(d.reconstruction_relative_error<3e-5);
assert(size(d.nominal_dyadic_ranges_hz,1)==cfg.dwt.level+1);
assert(all(d.band_power_fraction>=0)&&abs(sum(d.band_power_fraction)-1)<1e-10);
clear cleanup

% CWT actual grids, reflected edges, sinusoidal ridge and density sensitivity.
[v6,~,~,d6]=eba.features(x,Fs,"CWT",cfg);
assert(all(diff(d6.frequencies_hz)>0)&&all(d6.frequency_quadrature_weights>0));
assert(abs(sum(d6.frequency_quadrature_weights)-1)<1e-10);
assert(isequal(sort(d6.filter_center_frequencies_hz(:)),d6.frequencies_hz));
assert(d6.wt_frequency_precision=="single");
assert(d6.wt_frequency_rounding_max_hz<=double(eps(single(max(d6.frequencies_hz))))/2);
assert(d6.nominal_fundamental_in_actual_span);
interior=round(0.25*N):round(0.75*N);
ridge=d6.frequencies_hz(argmax(mean(abs(double(d6.coefficients(:,interior))).^2,2)));
assert(abs(ridge-60)/60<0.15);
assert(all(d6.edge_affected_fraction>=0&d6.edge_affected_fraction<=1));
dense=cfg; dense.cwt.voices=12; [v12,~,~,d12]=eba.features(x,Fs,"CWT",dense);
assert(numel(d12.frequencies_hz)>numel(d6.frequencies_hz));
assert(abs(sum(d12.frequency_quadrature_weights)-1)<1e-10);
fprintf('CWT_GRID_DENSITY_BAND_L1=%g LOGPOWER_DELTA=%g\n',sum(abs(v6(9:16)-v12(9:16))),v12(17)-v6(17));
[shortv,~,~,shortd]=eba.features(x(1:500),Fs,"CWT",cfg);
assert(numel(shortv)==24&&shortd.actual_frequency_limits_hz(1)>=30*(1-1e-10));
fprintf('CWT_500_ACTUAL_MIN_HZ=%g FUNDAMENTAL_INCLUDED=%d\n', ...
    shortd.actual_frequency_limits_hz(1),shortd.nominal_fundamental_in_actual_span);

% ST phase/sign/amplitude and direct-convolution oracle at an exact harmonic.
[vs,~,~,ds]=eba.features(x,Fs,"ST",cfg);
[~,q]=min(abs(ds.frequencies_hz-60)); assert(abs(ds.frequencies_hz(q)-60)<1e-10);
assert(abs(mean(abs(double(ds.coefficients(q,interior))))-1/sqrt(2))<0.015);
assert(abs(ds.frequencies_hz(argmax(ds.frequency_power_mass./ ...
    diff(ds.frequency_cells_hz,1,2)))-60)<5);
half=ds.half_support_samples(q); sigma=cfg.st.sigma_factor/60;
g=exp(-0.5*((-half:half)'/(Fs*sigma)).^2); g=g/sum(g);
direct=conv(x.*exp(-2i*pi*60*t),g,'same');
assert(max(abs(direct-double(ds.coefficients(q,:)).'))<2e-6);
assert(abs(sum(ds.frequency_quadrature_weights)-1)<1e-10&&all(ds.frequency_quadrature_weights>0));
[~,~,~,dc]=eba.features(ones(N,1),Fs,"ST",cfg);
assert(max(abs(double(dc.coefficients(q,interior))))<0.002);
impulse=zeros(N,1); impulse(round(N/2))=1;
[~,~,~,di]=eba.features(impulse,Fs,"ST",cfg);
assert(abs(argmax(sum(abs(double(di.coefficients)).^2,1))-round(N/2))<=1);
edge=zeros(1000,1); edge(end)=1;
[edgev,~,~,ed]=eba.features(edge,Fs,"ST",cfg);
assert(all(isfinite(edgev))&&sum(abs(double(ed.coefficients(:,end))).^2)>0);
denser=cfg; denser.st.log_frequencies=64; [vd,~,~,dd]=eba.features(x,Fs,"ST",denser);
assert(dd.actual_frequency_count>ds.actual_frequency_count);
fprintf('ST_GRID_DENSITY_BAND_L1=%g LOGPOWER_DELTA=%g\n',sum(abs(vs(9:16)-vd(9:16))),vd(17)-vs(17));

% Short-window fixed width is independent of full-record defaults.
for count=[500 1000 2000]
    p=cfg; p.stft.window_samples=min(count,500);
    p.dwt.level=min(3,wmaxlev(count,char(p.dwt.wavelet)));
    for method=methods
        [v,n]=eba.features(x(1:count),Fs,method,p);
        assert(numel(v)==24&&isequal(n,allowlist)&&all(isfinite(v)));
    end
end

% Trust-boundary negatives prove rejection rather than silent adjustment.
reject(@() eba.features(x,0,"FFT",cfg));
reject(@() eba.features(x,NaN,"FFT",cfg));
reject(@() eba.features([1 NaN 2 3],Fs,"FFT",cfg));
reject(@() eba.features(ones(3,1),Fs,"FFT",cfg));
reject(@() eba.features(complex(x,x),Fs,"FFT",cfg));
reject(@() eba.features(x,Fs,"UNKNOWN",cfg));
bad=cfg; bad.stft.overlap_fraction=1; reject(@() eba.features(x,Fs,"STFT",bad));
bad=cfg; bad.stft.window_samples=2*N; reject(@() eba.features(x,Fs,"STFT",bad));
bad=cfg; bad.stft.window="invented"; reject(@() eba.features(x,Fs,"STFT",bad));
bad=cfg; bad.dwt.level=wmaxlev(N,'db4')+1; reject(@() eba.features(x,Fs,"DWT",bad));
bad=cfg; bad.dwt.wavelet="haar"; reject(@() eba.features(x,Fs,"DWT",bad));
bad=cfg; bad.cwt.frequency_limits_hz=[4000 30]; reject(@() eba.features(x,Fs,"CWT",bad));
bad=cfg; bad.cwt.voices=0; reject(@() eba.features(x,Fs,"CWT",bad));
bad=cfg; bad.cwt.boundary="periodic"; reject(@() eba.features(x,Fs,"CWT",bad));
bad=cfg; bad.st.frequency_limits_hz=[30 Fs/2]; reject(@() eba.features(x,Fs,"ST",bad));
bad=cfg; bad.st.sigma_factor=0; reject(@() eba.features(x,Fs,"ST",bad));
bad=cfg; bad.st.class_id=1; reject(@() eba.features(x,Fs,"ST",bad));
bad=cfg; bad.class_id=1; reject(@() eba.features(x,Fs,"FFT",bad));
bad=cfg; bad.family_id="family-1"; reject(@() eba.features(x,Fs,"CWT",bad));
bad=cfg; bad.snr_db=20; reject(@() eba.features(x,Fs,"STFT",bad));
bad=cfg; bad.expected_samples=N+1; reject(@() eba.features(x,Fs,"FFT",bad));
reject(@() eba.transformCandidates("FFT",3,cfg));
fprintf('TRANSFORMS_SCIENTIFIC_TESTS_PASS\n');
end

function k=argmax(x)
[~,k]=max(x);
end

function reject(f)
failed=false;
try, f(); catch, failed=true; end
assert(failed,'eba:NegativeControl','Invalid transform input was accepted.');
end
