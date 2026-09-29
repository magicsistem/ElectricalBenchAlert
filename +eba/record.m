function [x,meta] = record(row,snr_db,realization,cfg,mode,reference)
%RECORD Lazy regeneration; structural reads may never be used for model tuning.
if nargin<5, mode="development"; end
if nargin<6,reference=cfg.noise_reference;end
reference=string(reference);
assert(isscalar(reference) && any(reference==["clean_disturbed_record_energy","nominal_baseline_rms_power"]), ...
    'eba:NoiseReference','Unknown physical noise-power reference.');
assert(istable(row) && height(row)==1,'eba:RecordRow','Exactly one family row is required.');
mode=string(mode); assert(isscalar(mode) && any(mode==["development" "structural" "final"]), ...
    'eba:RecordMode','Unknown access mode.');
assert(any(string(row.split)==["train" "validation" "test"]),'eba:Split','Invalid family split.');
if mode=="development"
    assert(string(row.split)~="test",'eba:TestFirewall','Development waveform access denies test families.');
elseif mode=="final"
    eba.requireFrozen(cfg,'verify',row);
end
assert(isscalar(realization) && realization==fix(realization) && realization>=1 && realization<=cfg.noise_realizations, ...
    'eba:Realization','Noise realization is outside the configured range.');
assert(isscalar(snr_db) && (snr_db==Inf || any(snr_db==cfg.snr_db)), ...
    'eba:SNR','Requested SNR is outside the configured experiment.');
p=jsondecode(row.parameters_json); assert(double(row.Fs_hz)==cfg.Fs && double(row.clip_duration_s)==cfg.clip_duration_s, ...
    'eba:Sampling','Family sampling differs from configuration.');
assert(string(p.class_name)==string(row.class_name) && double(p.family_seed)==double(row.family_seed), ...
    'eba:RecordRow','Parameter and family metadata differ.');
noiseSeed=1000000000+double(cfg.master_seed)+double(p.family_serial)*16+realization;
clean=eba.waveform(p,(0:round(cfg.Fs*cfg.clip_duration_s)-1)',cfg);
[x,measured]=eba.noise(clean,snr_db,noiseSeed);referencePower=mean(clean.^2);
if reference=="nominal_baseline_rms_power"
    referencePower=p.base_rms_pu^2;
    if isfinite(snr_db)
        z=(x-clean)*sqrt(referencePower/mean(clean.^2));x=clean+z;
        measured=10*log10(referencePower/mean((x-clean).^2));
    end
end
measuredDisturbed=Inf;if isfinite(snr_db),measuredDisturbed=10*log10(mean(clean.^2)/mean((x-clean).^2));end
meta=struct('family_id',char(row.family_id),'split',char(row.split),'class_id',double(row.class_id), ...
    'class_name',char(row.class_name),'labels',{cellstr(string(jsondecode(row.labels_json)))}, ...
    'requested_snr_db',snr_db,'measured_snr_db',measured,'noise_seed',noiseSeed, ...
    'noise_realization',realization,'reference_power_pu2',referencePower, ...
    'noise_reference',char(reference),'Fs_hz',cfg.Fs,'n_samples',numel(x), ...
    'waveform_sha256',eba.hash(x,'numeric'),'dataset_version',char(cfg.dataset_version), ...
    'method_version',char(cfg.method_version),'access_mode',char(mode));
if snr_db==Inf, meta.noise_realization=0; end
meta.record_id=char(eba.recordId(row.family_id,snr_db,meta.noise_realization));
meta.measured_disturbed_record_snr_db=measuredDisturbed;
end
