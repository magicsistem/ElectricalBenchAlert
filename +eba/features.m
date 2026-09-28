function [v,names,bytes,detail] = features(x,Fs,method,params)
%FEATURES Frozen-width, waveform-only DSP protocol (8 time + 16 summaries).
% Scientific scope and reproduction instructions are in the root README.
if nargin<4, params=struct(); end
validateattributes(x,{'single','double'},{'real','vector','finite','nonempty'});
validateattributes(Fs,{'numeric'},{'real','scalar','finite','positive'});
assert(isstruct(params)&&isscalar(params),'eba:DSPParameters','Parameters must be a scalar struct.');
forbidden=["class_id","class_name","family_id","record_id","labels","label", ...
    "severity","project_severity","requested_snr_db","measured_snr_db","event_start_sample","event_end_sample"];
assert(~any(ismember(lower(string(fieldnames(params))),forbidden)), ...
    'eba:DSPTruth','Ground-truth/record metadata is not a transform input.');
fields=string(fieldnames(params)); snrField=fields(strcmpi(fields,"snr_db"));
if ~isempty(snrField)
    assert(isnumeric(params.(snrField))&&isvector(params.(snrField))&&numel(params.(snrField))>1, ...
        'eba:DSPTruth','A record SNR is not a transform input; a global configuration grid is ignored.');
end
x=double(x(:)); N=numel(x);
assert(N>=4,'eba:DSPLength','At least four samples are required.');
assert(all(isfinite(single(x))),'eba:DSPRange','Input exceeds single representation range.');
if isfield(params,'expected_samples')
    validateattributes(params.expected_samples,{'numeric'},{'real','scalar','integer','>=',4});
    assert(N==params.expected_samples,'eba:DSPLength','Unexpected input window length.');
end
if isfield(params,'minimum_samples')
    validateattributes(params.minimum_samples,{'numeric'},{'scalar','integer','>=',4});
    assert(N>=params.minimum_samples,'eba:DSPLength','Input window is too short.');
end
method=upper(string(method));
assert(isscalar(method)&&any(method==["FFT","STFT","DWT","CWT","ST"]), ...
    'eba:DSPMethod','Unknown representation.');
f0=60;
if isfield(params,'nominal_frequency_hz'), f0=params.nominal_frequency_hz; end
validateattributes(f0,{'numeric'},{'real','scalar','finite','positive','<',Fs/2});
field=char(lower(method)); p=struct();
if isfield(params,field), p=params.(field); end
assert(isstruct(p)&&isscalar(p),'eba:DSPParameters','Method parameters must be a scalar struct.');
detail=struct('method',method,'schema_version',"2.0.0",'sample_count',N, ...
    'Fs_hz',Fs,'nominal_frequency_hz',f0,'precision',"single representation; double summaries", ...
    'frequency_resolution_floor_hz',Fs/N,'power_measure',"normalized coefficient power, not physical energy");
t=(0:N-1)/Fs;
switch method
    case "FFT"
        checkFields(p,strings(0,1));
        coef=single(fft(x)/N); coef=coef(1:floor(N/2)+1);
        f=(0:numel(coef)-1)'*Fs/N;
        scale=ones(numel(f),1)*2; scale(1)=1;
        if mod(N,2)==0, scale(end)=1; end
        row=abs(double(coef)).^2.*scale;
        cells=frequencyCells(f,[0 Fs/2]);
        if sum(row)>0, temporal=ones(1,8)/8; else, temporal=zeros(1,8); end
        detail.boundary="finite rectangular record; no padding";
        detail.temporal_policy="uniform; FFT has no temporal localization";
        detail.fft_mean_square=sum(row);
        detail.one_sided_scale=scale;
    case "STFT"
        checkFields(p,["window_samples","overlap_fraction","window"]);
        required(p,["window_samples","overlap_fraction","window"]);
        W=p.window_samples;
        validateattributes(W,{'numeric'},{'real','scalar','integer','>=',4,'<=',N});
        validateattributes(p.overlap_fraction,{'numeric'},{'real','scalar','finite','>=',0,'<',1});
        O=round(W*p.overlap_fraction); hop=W-O;
        assert(hop>=1,'eba:STFTOverlap','Overlap leaves no advance.');
        k=(0:W-1)';
        switch lower(string(p.window))
            case "hann", win=0.5-0.5*cos(2*pi*k/(W-1));
            case "blackman", win=0.42-0.5*cos(2*pi*k/(W-1))+0.08*cos(4*pi*k/(W-1));
            otherwise, error('eba:STFTWindow','Use hann or blackman.');
        end
        centers=0:hop:(N-1);
        if centers(end)<N-1, centers(end+1)=N-1; end
        starts=centers-floor((W-1)/2);
        F=floor(W/2)+1; coef=complex(zeros(F,numel(starts),'single'));
        times=centers/Fs; valid=zeros(1,numel(starts)); firstObserved=zeros(1,numel(starts));
        for j=1:numel(starts)
            first=max(0,starts(j)); last=min(N-1,starts(j)+W-1);
            observed=(first:last)-starts(j)+1; segment=zeros(W,1);
            segment(observed)=x(first+1:last+1);
            % Normalize by observed weights, excluding both boundary paddings.
            normfactor=sqrt(W*sum(win(observed).^2));
            assert(normfactor>0,'eba:STFTWindow','Window has no observed support.');
            z=fft(segment.*win)/normfactor;
            coef(:,j)=single(z(1:F));
            valid(j)=numel(observed); firstObserved(j)=first;
        end
        f=(0:F-1)'*Fs/W;
        scale=ones(F,1)*2; scale(1)=1;
        if mod(W,2)==0, scale(end)=1; end
        cells=frequencyCells(f,[0 Fs/2]);
        [row,profile]=coefficientMass(coef,scale,timeWeights(times,N/Fs));
        temporal=temporalBins(profile,times,N/Fs);
        detail.boundary="centered frames; two-sided zero padding; first/last samples have nonzero support";
        detail.window_samples=W; detail.window_duration_s=W/Fs;
        detail.frequency_resolution_hz=Fs/W;
        detail.overlap_samples=O; detail.hop_samples=hop;
        detail.frame_start_samples=starts; detail.frame_valid_samples=valid;
        detail.frame_first_observed_samples=firstObserved;
        detail.one_sided_scale=scale; detail.times_s=times;
    case "DWT"
        checkFields(p,["wavelet","level"]); required(p,["wavelet","level"]);
        wavelet=string(p.wavelet);
        assert(isscalar(wavelet)&&any(wavelet==["db4","db6","db8","sym4","sym6","coif3","coif5"]), ...
            'eba:DWTWavelet','Wavelet is outside the declared search.');
        maxlevel=wmaxlev(N,char(wavelet));
        validateattributes(p.level,{'numeric'},{'real','scalar','integer','positive','<=',maxlevel});
        % wrcoef uses the global extension setting; always restore it, even on error.
        oldmode=dwtmode('status','nodisp'); cleanup=onCleanup(@() dwtmode(oldmode,'nodisp'));
        dwtmode('sym','nodisp');
        [coef,L]=wavedec(single(x),p.level,char(wavelet),Mode="sym");
        coef=single(coef); cells=zeros(p.level+1,2); row=zeros(p.level+1,1);
        profile=zeros(1,N); reconstruction=zeros(N,1);
        for j=0:p.level
            if j==0
                c=appcoef(coef,L,char(wavelet),p.level);
                r=double(wrcoef('a',coef,L,char(wavelet),p.level));
                cells(1,:)=[0 Fs/2^(p.level+1)];
            else
                c=detcoef(coef,L,j);
                r=double(wrcoef('d',coef,L,char(wavelet),j));
                cells(j+1,:)=[Fs/2^(j+1) Fs/2^j];
            end
            r=r(:); assert(numel(r)==N,'eba:DWTReconstruction','Unexpected reconstruction length.');
            reconstruction=reconstruction+r;
            row(j+1)=sum(abs(double(c)).^2)/N;
            rp=r.^2; s=sum(rp);
            if s>0, profile=profile+(rp/s*row(j+1)).'; end
        end
        [f,order]=sort(mean(cells,2)); cells=cells(order,:); row=row(order);
        temporal=temporalBins(profile,t,N/Fs);
        detail.boundary="half-point symmetric extension; global mode restored";
        detail.wavelet=wavelet; detail.level=p.level; detail.maximum_feasible_level=maxlevel;
        detail.bookkeeping=L; detail.nominal_dyadic_ranges_hz=cells;
        detail.frequency_resolution_policy="nominal dyadic intervals; no resolved frequency ridge";
        detail.reconstruction_relative_error=norm(reconstruction-x)/max(norm(x),eps);
        detail.times_s=t;
        clear cleanup
    case "CWT"
        checkFields(p,["wavelet","voices","frequency_limits_hz","boundary"]);
        required(p,["wavelet","voices","frequency_limits_hz","boundary"]);
        wavelet=string(p.wavelet);
        assert(isscalar(wavelet)&&any(wavelet==["Morse","amor"]),'eba:CWTWavelet','Use Morse or amor.');
        validateattributes(p.voices,{'numeric'},{'real','scalar','integer','>=',1,'<=',48});
        assert(isequal(string(p.boundary),"reflection"),'eba:CWTBoundary','Reflection is the frozen boundary policy.');
        limits=validateLimits(p.frequency_limits_hz,Fs);
        persistent cwtKey cwtBank cwtFrequencies
        key=eba.hash(jsonencode(struct('N',N,'Fs',Fs,'parameters',p)));
        if isempty(cwtKey)||~strcmp(cwtKey,key)
            cwtBank=cwtfilterbank(SignalLength=N,SamplingFrequency=Fs,Wavelet=wavelet, ...
                VoicesPerOctave=p.voices,FrequencyLimits=limits,Boundary="reflection");
            cwtKey=key; cwtFrequencies=[];
        end
        [coef,wtFrequencies,coi]=wt(cwtBank,single(x)); coef=single(coef);
        if isempty(cwtFrequencies)
            cwtFrequencies=double(centerFrequencies(cwtBank));
        end
        % wt reports single frequencies for single input. Preserve authoritative
        % double centers, and prove that coefficient rows agree after rounding.
        assert(isequal(single(wtFrequencies(:)),single(cwtFrequencies(:))), ...
            'eba:CWTGrid','Coefficient frequencies differ from the filter centers.');
        [f,order]=sort(cwtFrequencies(:)); coef=coef(order,:);
        assert(numel(f)>=2,'eba:CWTGrid','Filter bank has fewer than two frequencies.');
        % MATLAB may raise the low limit for finite support; report actual centers.
        cells=frequencyCells(f,[min(f) max(f)]);
        weights=(cells(:,2)-cells(:,1))/(max(f)-min(f));
        [row,profile]=coefficientMass(coef,weights,ones(1,N)/N);
        temporal=temporalBins(profile,t,N/Fs);
        detail.boundary="reflection; all coefficients retained including cone of influence";
        detail.requested_frequency_limits_hz=limits;
        detail.actual_frequency_limits_hz=[min(f) max(f)];
        if nargout>=4
            detail.filter_center_frequencies_hz=cwtFrequencies;
            detail.wt_frequency_precision=string(class(wtFrequencies));
            detail.wt_frequency_rounding_max_hz=max(abs(double(wtFrequencies(:))-cwtFrequencies(:)));
            detail.frequency_grid_policy="double filter centers; exact agreement with wt after single rounding";
            detail.cone_of_influence_hz=coi;
            detail.edge_affected_fraction=mean(f(:)<double(coi(:).'),2);
        end
        detail.nominal_fundamental_in_actual_span=min(f)<=f0&&max(f)>=f0;
        detail.centers_below_record_resolution=f<Fs/N;
        detail.frequency_quadrature_weights=weights; detail.cache_key=key;
        detail.wavelet=wavelet; detail.voices=p.voices; detail.times_s=t;
    case "ST"
        checkFields(p,["frequency_limits_hz","log_frequencies","sigma_factor","truncate_sigma"]);
        required(p,["frequency_limits_hz","log_frequencies","sigma_factor","truncate_sigma"]);
        limits=validateLimits(p.frequency_limits_hz,Fs);
        validateattributes(p.log_frequencies,{'numeric'},{'real','scalar','integer','>=',2});
        validateattributes(p.sigma_factor,{'numeric'},{'real','scalar','finite','positive'});
        validateattributes(p.truncate_sigma,{'numeric'},{'real','scalar','finite','>=',2});
        persistent stKey stBank
        key=eba.hash(jsonencode(struct('N',N,'Fs',Fs,'f0',f0,'parameters',p)));
        if isempty(stKey)||~strcmp(stKey,key)
            f=unique([logspace(log10(limits(1)),log10(limits(2)),p.log_frequencies), ...
                f0*(ceil(limits(1)/f0):floor(limits(2)/f0))]).';
            f=f(f>=limits(1)*(1-1e-12)&f<=limits(2)*(1+1e-12));
            stBank=struct('frequencies',f,'kernel_fft',{cell(numel(f),1)}, ...
                'half_support',zeros(numel(f),1),'fft_length',zeros(numel(f),1));
            for j=1:numel(f)
                sigma=p.sigma_factor/f(j); half=ceil(p.truncate_sigma*sigma*Fs);
                g=exp(-0.5*((-half:half)'/(Fs*sigma)).^2); g=g/sum(g);
                nf=2^nextpow2(N+numel(g)-1);
                stBank.kernel_fft{j}=fft(g,nf); stBank.half_support(j)=half;
                stBank.fft_length(j)=nf;
            end
            stKey=key;
        end
        f=stBank.frequencies; coef=complex(zeros(numel(f),N,'single'));
        for j=1:numel(f)
            carrier=x.*exp(-2i*pi*f(j)*t(:)); nf=stBank.fft_length(j);
            z=ifft(fft(carrier,nf).*stBank.kernel_fft{j}); half=stBank.half_support(j);
            coef(j,:)=single(z(half+1:half+N).');
        end
        cells=frequencyCells(f,limits); weights=(cells(:,2)-cells(:,1))/diff(limits);
        [row,profile]=coefficientMass(coef,weights,ones(1,N)/N);
        temporal=temporalBins(profile,t,N/Fs);
        detail.boundary="zero extension; finite Gaussian convolution";
        detail.requested_frequency_limits_hz=limits; detail.actual_frequency_limits_hz=[min(f) max(f)];
        detail.log_frequency_count=p.log_frequencies; detail.actual_frequency_count=numel(f);
        detail.frequency_quadrature_weights=weights; detail.sigma_factor=p.sigma_factor;
        detail.truncate_sigma=p.truncate_sigma; detail.half_support_samples=stBank.half_support;
        detail.dc_coefficient=mean(x); detail.dc_policy="DC separate, excluded from positive-frequency summaries";
        detail.phase_convention="global exp(-2*pi*i*f*t) demodulation";
        detail.cache_key=key; detail.times_s=t;
end
assert(all(isfinite(coef(:))),'eba:DSPRange','Representation overflow.');
names=["time_rms_pu","time_mean_pu","time_peak_abs_pu","time_crest_factor", ...
    "time_kurtosis","time_cycle_rms_q10_pu","time_cycle_rms_q90_pu","time_cycle_rms_std_pu", ...
    "rep_band_0_45_fraction","rep_band_45_75_fraction","rep_band_75_120_fraction", ...
    "rep_band_120_300_fraction","rep_band_300_600_fraction","rep_band_600_1500_fraction", ...
    "rep_band_1500_3000_fraction","rep_band_3000_up_fraction","rep_log10_coefficient_power", ...
    "rep_frequency_centroid_hz","rep_band_entropy_norm","rep_dominant_frequency_hz", ...
    "rep_time_concentration","rep_time_centroid_fraction","rep_time_entropy_norm","rep_max_time_bin_fraction"];
rmsx=sqrt(mean(x.^2)); peak=max(abs(x)); centered=x-mean(x); variance=mean(centered.^2);
if variance>0, kurt=mean(centered.^4)/variance^2; else, kurt=0; end
envelope=sqrt(movmean(x.^2,min(N,max(1,round(Fs/f0))),Endpoints="shrink"));
common=[rmsx,mean(x),peak,peak/max(rmsx,eps),kurt, ...
    quantile(envelope,0.1),quantile(envelope,0.9),std(envelope,1)];
[summary,bands]=summarize(row,f,cells,temporal);
v=[common summary]; assert(numel(v)==24&&all(isfinite(v)),'eba:DSPFeatures','Nonfinite feature output.');
info=whos('coef'); bytes=info.bytes;
if method=="DWT", infoL=whos('L'); bytes=bytes+infoL.bytes; end
detail.coefficients=coef; detail.frequencies_hz=f; detail.frequency_cells_hz=cells;
detail.frequency_power_mass=row; detail.band_power_fraction=bands;
detail.temporal_bin_fraction=temporal; detail.feature_names=names;
detail.representation_bytes=bytes;
end

function checkFields(p,allowed)
assert(all(ismember(string(fieldnames(p)),allowed)),'eba:DSPParameters','Undeclared method parameter.');
end

function required(p,fields)
assert(all(isfield(p,cellstr(fields))),'eba:DSPParameters','Missing method parameter.');
end

function limits=validateLimits(value,Fs)
validateattributes(value,{'numeric'},{'real','vector','numel',2,'finite','positive'});
limits=double(value(:).');
assert(limits(1)<limits(2)&&limits(2)<Fs/2,'eba:DSPFrequency','Frequency limits must increase below Nyquist.');
end

function cells=frequencyCells(f,limits)
f=double(f(:));
assert(numel(f)>=2&&all(diff(f)>0),'eba:DSPGrid','At least two increasing frequencies required.');
edges=[limits(1);(f(1:end-1)+f(2:end))/2;limits(2)];
cells=[edges(1:end-1),edges(2:end)];
assert(all(cells(:,2)>cells(:,1)),'eba:DSPGrid','Frequency quadrature cells must have positive width.');
end

function weights=timeWeights(t,duration)
edges=[0,(t(1:end-1)+t(2:end))/2,duration];
weights=diff(edges)/duration;
assert(all(weights>0),'eba:DSPTime','Time quadrature must have positive weights.');
end

function [row,profile]=coefficientMass(coef,frequencyWeights,temporalWeights)
% Rowwise double work avoids a second full double time-frequency matrix.
row=zeros(size(coef,1),1); profile=zeros(1,size(coef,2));
for j=1:size(coef,1)
    power=abs(double(coef(j,:))).^2*frequencyWeights(j);
    row(j)=sum(power.*temporalWeights);
    profile=profile+power.*temporalWeights;
end
end

function bins=temporalBins(profile,t,duration)
indices=min(8,max(1,floor(double(t)/duration*8)+1));
bins=accumarray(indices(:),double(profile(:)),[8 1]).';
if sum(bins)>0, bins=bins/sum(bins); else, bins=zeros(1,8); end
end

function [v,bands]=summarize(row,f,cells,temporal)
edges=[0 45 75 120 300 600 1500 3000 Inf]; bands=zeros(1,8); total=sum(row);
for j=1:8
    overlap=max(0,min(cells(:,2),edges(j+1))-max(cells(:,1),edges(j)));
    bands(j)=sum(row.*overlap./(cells(:,2)-cells(:,1)))/max(total,eps);
end
if total>0
    centroid=sum(f.*row)/total; [~,j]=max(row./(cells(:,2)-cells(:,1)));
    dominant=f(j);
else
    centroid=0; dominant=0;
end
centers=((1:8)-0.5)/8;
v=[bands,log10(total+eps),centroid,entropy(bands),dominant, ...
    sum(temporal.^2),sum(centers.*temporal),entropy(temporal),max(temporal)];
end

function h=entropy(p)
p=p(p>0); h=-sum(p.*log2(p))/3;
end
