function x = waveform(p,sample_indices,cfg)
%WAVEFORM Physical components at absolute zero-based samples; p.u. nominal RMS.
assert(isstruct(p) && isscalar(p),'eba:Parameters','One parameter structure is required.');
assert(isnumeric(sample_indices) && isreal(sample_indices) && all(isfinite(sample_indices(:))) && ...
    all(sample_indices(:)>=0 & sample_indices(:)==fix(sample_indices(:))), ...
    'eba:SampleIndices','Sample indices must be finite nonnegative integers.');
assert(isscalar(cfg.Fs) && isfinite(cfg.Fs) && cfg.Fs>0,'eba:Sampling','Invalid sample rate.');
cls=string(p.class_name); assert(any(cls==string(cfg.classes)),'eba:Class','Unknown waveform class.');
assert(all(isfinite([p.frequency_hz p.base_rms_pu p.phase_rad])) && p.frequency_hz>0 && ...
    p.frequency_hz<cfg.Fs/2 && p.base_rms_pu>0,'eba:Parameters','Invalid fundamental parameters.');
idx=double(sample_indices(:)); t=idx/cfg.Fs; phase=2*pi*p.frequency_hz*t+p.phase_rad;
fund=sqrt(2)*p.base_rms_pu*sin(phase); x=fund;
if cls=="normal", return; end
assert(all(isfinite([p.start_sample p.end_sample])) && p.start_sample>=0 && p.end_sample>p.start_sample && ...
    all([p.start_sample p.end_sample]==fix([p.start_sample p.end_sample])), ...
    'eba:EventSupport','Event support must use increasing integer boundaries.');
active=idx>=p.start_sample & idx<p.end_sample;
u=(idx-p.start_sample)/(p.end_sample-p.start_sample); elapsed=(idx-p.start_sample)/cfg.Fs;
localizedAmplitude=any(cls==["voltage_sag" "voltage_swell" "interruption" "voltage_sag_harmonics" "voltage_swell_harmonics"]);
env=double(active);
if localizedAmplitude
    assert(isfinite(p.voltage_factor) && p.voltage_factor>=0 && isfinite(p.taper_s) && p.taper_s>0, ...
        'eba:Parameters','Invalid amplitude or taper.');
    distance=min(elapsed,(p.end_sample-idx)/cfg.Fs);
    env(active)=.5-.5*cos(pi*min(distance(active)/p.taper_s,1));
end
if contains(cls,"harmonics")
    orders=p.harmonic_orders(:); ratios=p.harmonic_ratios(:); angles=p.harmonic_phases_rad(:);
    assert(numel(orders)==numel(ratios) && numel(orders)==numel(angles) && all(isfinite([orders;ratios;angles])) && ...
        all(orders>=2 & orders==fix(orders)) && numel(unique(orders))==numel(orders) && ...
        all(orders*p.frequency_hz<cfg.Fs/2) && all(ratios>0),'eba:Harmonics','Invalid harmonic components.');
    h=zeros(size(x));
    for j=1:numel(orders)
        h=h+sqrt(2)*p.base_rms_pu*ratios(j)*sin(2*pi*orders(j)*p.frequency_hz*t+angles(j));
    end
    x=x+env.*h;
end
if localizedAmplitude, x=x.*(1+(p.voltage_factor-1)*env); end
if contains(cls,"flicker")
    assert(all(isfinite([p.modulation_depth p.modulation_frequency_hz p.modulation_phase_rad])) && ...
        p.modulation_depth>0 && p.modulation_depth<1 && p.modulation_frequency_hz>0 && ...
        p.modulation_frequency_hz<cfg.Fs/2,'eba:Flicker','Invalid modulation.');
    x=x.*(1+double(active)*p.modulation_depth.*sin(2*pi*p.modulation_frequency_hz*t+p.modulation_phase_rad));
end
if cls=="oscillatory_transient"
    assert(all(isfinite([p.transient_amplitude_pu p.transient_frequency_hz p.decay_tau_s p.transient_phase_rad])) && ...
        p.transient_amplitude_pu>0 && p.transient_frequency_hz>0 && p.transient_frequency_hz<cfg.Fs/2 && ...
        p.decay_tau_s>0,'eba:Transient','Invalid oscillatory parameters.');
    q=zeros(size(x)); q(active)=sin(pi*u(active)).^2.*exp(-elapsed(active)/p.decay_tau_s).* ...
        sin(2*pi*p.transient_frequency_hz*elapsed(active)+p.transient_phase_rad);
    x=x+p.transient_amplitude_pu*q;
elseif cls=="impulsive_transient"
    assert(isfinite(p.transient_amplitude_pu) && p.transient_amplitude_pu>0 && any(p.polarity==[-1 1]), ...
        'eba:Transient','Invalid impulse parameters.');
    q=zeros(size(x)); q(active)=sin(pi*u(active)).^4;
    x=x+p.polarity*p.transient_amplitude_pu*q;
elseif cls=="notching"
    assert(isfinite(p.notch_depth) && p.notch_depth>0 && p.notch_depth<1 && isfinite(p.notch_width_s) && ...
        p.notch_width_s>0 && isfinite(p.notch_center_phase_rad) && p.notch_center_phase_rad>0 && p.notch_center_phase_rad<pi && ...
        pi*p.frequency_hz*p.notch_width_s<min(p.notch_center_phase_rad,pi-p.notch_center_phase_rad), ...
        'eba:Notching','Invalid notch parameters or zero-crossing overlap.');
    delta=mod(phase-p.notch_center_phase_rad+pi/2,pi)-pi/2;
    halfWidth=pi*p.frequency_hz*p.notch_width_s;
    mask=active & abs(delta)<halfWidth;
    taper=zeros(size(x)); taper(mask)=.5+.5*cos(pi*delta(mask)/halfWidth);
    x=x.*(1-p.notch_depth*taper);
end
assert(all(isfinite(x)),'eba:NonFiniteSignal','Generated waveform is not finite.');
end
