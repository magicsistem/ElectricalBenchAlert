function candidates = transformCandidates(method,N,cfg)
%TRANSFORMCANDIDATES Declared engineering grid, never accepts labels or data.
validateattributes(N,{'numeric'},{'real','scalar','integer','>=',4});
assert(isstruct(cfg)&&isscalar(cfg)&&isfield(cfg,'Fs')&&isfield(cfg,'nominal_frequency_hz'), ...
    'eba:DSPCandidates','Configuration needs Fs and nominal frequency.');
validateattributes(cfg.Fs,{'numeric'},{'real','scalar','finite','positive'});
validateattributes(cfg.nominal_frequency_hz,{'numeric'},{'real','scalar','finite','positive','<',cfg.Fs/2});
method=upper(string(method)); assert(isscalar(method),'eba:DSPMethod','Method must be scalar.');
root=fileparts(fileparts(mfilename('fullpath')));
grid=jsondecode(fileread(fullfile(root,'config','dsp_candidates.json')));
candidates=struct('id',{},'parameters',{});
switch method
    case "FFT"
        candidates=add(candidates,"fft_rectangular",struct(),cfg);
    case "STFT"
        for W=grid.stft.window_samples(:).'
            if W>N, continue; end
            for window=string(grid.stft.window(:)).'
                for overlap=grid.stft.overlap_fraction(:).'
                    p=struct('window_samples',W,'overlap_fraction',overlap,'window',window);
                    id=sprintf('stft_%d_%s_overlap_%02d',W,window,round(100*overlap));
                    candidates=add(candidates,string(id),struct('stft',p),cfg);
                end
            end
        end
    case "DWT"
        for wavelet=string(grid.dwt.wavelet(:)).'
            maxlevel=wmaxlev(N,char(wavelet));
            levels=grid.dwt.level(:).';
            for level=levels(levels<=maxlevel)
                p=struct('wavelet',wavelet,'level',level);
                candidates=add(candidates,"dwt_"+wavelet+"_level_"+level,struct('dwt',p),cfg);
            end
        end
    case "CWT"
        assert(cfg.Fs/2>grid.cwt.frequency_limits_hz(2),'eba:DSPFrequency','Candidate upper limit must be below Nyquist.');
        for wavelet=string(grid.cwt.wavelet(:)).'
            for voices=grid.cwt.voices(:).'
                p=struct('wavelet',wavelet,'voices',voices,'frequency_limits_hz',grid.cwt.frequency_limits_hz(:).','boundary',string(grid.cwt.boundary));
                candidates=add(candidates,"cwt_"+wavelet+"_voices_"+voices,struct('cwt',p),cfg);
            end
        end
    case "ST"
        assert(cfg.Fs/2>grid.st.frequency_limits_hz(2),'eba:DSPFrequency','Candidate upper limit must be below Nyquist.');
        for count=grid.st.log_frequencies(:).'
            for sigma=grid.st.sigma_factor(:).'
                p=struct('frequency_limits_hz',grid.st.frequency_limits_hz(:).','log_frequencies',count,'sigma_factor',sigma,'truncate_sigma',grid.st.truncate_sigma);
                candidates=add(candidates,sprintf('st_log_%d_sigma_%g',count,sigma),struct('st',p),cfg);
            end
        end
    otherwise
        error('eba:DSPMethod','Unknown representation.');
end
end

function candidates=add(candidates,id,parameters,cfg)
parameters.nominal_frequency_hz=cfg.nominal_frequency_hz;
candidates(end+1)=struct('id',string(id),'parameters',parameters);
end
