function review = fixtureReview(cfg)
%FIXTUREREVIEW Inspect original MAT bytes against declared legacy equation candidates.
% A numerical match proves a candidate equation on these samples, not a missing generator.
if nargin<1, cfg=eba.config(); end
root=fullfile(cfg.root,'fixtures','dataset_fixture');
T=readtable(fullfile(root,'metadata.csv'),'TextType','string');
assert(height(T)==9,'eba:Fixtures','Expected the nine immutable original fixtures.');
items=cell(height(T),1);
for i=1:height(T)
    file=char(T.file(i));
    assert(~contains(file,'..') && startsWith(file,'signals/') && endsWith(file,'.mat'), ...
        'eba:FixturePath','Unsafe fixture path.');
    path=fullfile(root,file); originalHash=eba.hash(path,'file'); data=load(path);
    assert(isfield(data,'samples') && isvector(data.samples) && all(isfinite(data.samples(:))), ...
        'eba:Fixtures','Fixture samples are missing or nonfinite.');
    x=double(data.samples(:)); Fs=T.Fs(i); t=(0:numel(x)-1)'/Fs; p=jsondecode(T.parameters_json(i));
    base=sqrt(2)*p.amplitude_pu_rms*sin(2*pi*60*t+p.phase_rad);
    cls=string(T.label(i)); active=t>=T.event_start_s(i) & t<T.event_end_s(i);
    candidates=base; candidateNames="nominal_fundamental";
    switch cls
        case "voltage_sag"
            candidates=base.*(1+(p.residual_voltage_pu-1)*double(active)); candidateNames="rectangular_residual_voltage";
        case "voltage_swell"
            candidates=base.*(1+(p.swell_voltage_pu-1)*double(active)); candidateNames="rectangular_swell_voltage";
        case "interruption"
            candidates=base.*(1+(p.residual_voltage_pu-1)*double(active)); candidateNames="rectangular_interruption";
        case "harmonics"
            for j=1:numel(p.harmonic_orders)
                candidates=candidates+sqrt(2)*p.harmonic_amplitudes_pu_rms(j)* ...
                    sin(2*pi*60*p.harmonic_orders(j)*t+p.harmonic_phases_rad(j));
            end
            candidateNames="declared_additive_harmonics";
        case "flicker"
            candidates=base.*(1+p.modulation_depth*sin(2*pi*p.modulation_frequency_hz*t)); candidateNames="zero_phase_sinusoidal_modulation";
        case "oscillatory_transient"
            u=t-T.event_start_s(i); q=zeros(size(x));
            q(active)=p.transient_amplitude_pu*exp(-u(active)/p.decay_tau_s).*sin(2*pi*p.transient_frequency_hz*u(active));
            candidates=[base+q base+sqrt(2)*q]; candidateNames=["truncated_damped_sinusoid_peak" "truncated_damped_sinusoid_rms"];
        case "impulsive_transient"
            center=(T.event_start_s(i)+T.event_end_s(i))/2; width=p.width_s;
            q=p.polarity*p.transient_amplitude_pu*exp(-.5*((t-center)/(width/6)).^2);
            q2=p.polarity*p.transient_amplitude_pu*exp(-((t-center)/width).^2);
            candidates=[base+q base+q.*active base+q2 base+p.polarity*p.transient_amplitude_pu*double(active)];
            candidateNames=["gaussian_width_six_sigma" "truncated_gaussian_width_six_sigma" "gaussian_width_scale" "rectangular_pulse"];
        case "notching"
            cyclePhase=mod(2*pi*60*t,pi); wavePhase=mod(2*pi*60*t+p.phase_rad,pi);
            clockMask=cyclePhase<2*pi*60*p.notch_width_s;
            phaseMask=wavePhase<2*pi*60*p.notch_width_s;
            candidates=[base-p.notch_depth_pu*clockMask base-p.notch_depth_pu*phaseMask ...
                base.*(1-p.notch_depth_pu*clockMask) base.*(1-p.notch_depth_pu*phaseMask)];
            candidateNames=["clock_additive_notch" "phase_additive_notch" "clock_multiplicative_notch" "phase_multiplicative_notch"];
    end
    errors=max(abs(candidates-x),[],1); [bestError,best]=min(errors);
    away=abs(base)>.02; negative=base<-.02;
    residual=x-base; F=fft(residual); frequencies=(0:numel(x)-1)'*Fs/numel(x);
    highMask=frequencies>.4*Fs & frequencies<.6*Fs;
    highFraction=sum(abs(F(highMask)).^2)/max(sum(abs(F).^2),realmin);
    matFields=string(fieldnames(data)); metaFields=strings(0,1);
    if isfield(data,'metadata') && isstruct(data.metadata), metaFields=string(fieldnames(data.metadata)); end
    item=struct('class_name',char(cls),'file',file,'original_sha256',originalHash,'Fs_hz',Fs, ...
        'n_samples',numel(x),'declared_n_samples',T.n_samples(i),'mat_variables',{cellstr(matFields)}, ...
        'mat_metadata_fields',{cellstr(metaFields)},'metadata_csv_parameters',p, ...
        'best_candidate_equation',char(candidateNames(best)),'max_absolute_equation_error_pu',bestError, ...
        'rmse_equation_error_pu',sqrt(mean((candidates(:,best)-x).^2)), ...
        'equation_numerically_matches',bestError<=1e-11,'candidate_search_is_not_original_generator',true, ...
        'declared_event_sample_count',sum(active),'negative_half_amplification_count',sum(negative & abs(x)>abs(base)+1e-9), ...
        'sign_reversal_away_from_zero_count',sum(away & sign(x)~=sign(base)), ...
        'residual_energy_fraction_above_0_4_Fs',highFraction,'legacy_notch_risk',cls=="notching", ...
        'legacy_impulse_below_new_10_sample_support',cls=="impulsive_transient" && sum(active)<10);
    if isfield(data,'metadata'), item.original_mat_metadata=data.metadata;
    else, item.original_mat_metadata=struct(); end
    assert(numel(x)==T.n_samples(i) && Fs==cfg.Fs && numel(x)==round(Fs*T.duration_s(i)), ...
        'eba:Fixtures','Original sample metadata differs from waveform bytes.');
    assert(strcmp(originalHash,eba.hash(path,'file')),'eba:FixtureMutation','Fixture bytes changed during review.');
    items{i}=item;
end
review=struct('status','original_nine_fixture_reference_review','n_fixtures',height(T), ...
    'fixture_metadata_sha256',eba.hash(fullfile(root,'metadata.csv'),'file'),'fixtures',[items{:}], ...
    'original_full_dataset_mat_count_declared',630,'original_full_dataset_mat_count_available',9, ...
    'original630_identity_reconstructed',false,'new_dataset_is_separately_versioned',true, ...
    'scope_note','Candidate matches and measured artifacts apply only to preserved fixture bytes; missing original records and generator remain unavailable.');
end
