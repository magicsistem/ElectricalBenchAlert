function test_signals()
%TEST_SIGNALS Scientific controls; run only in the central MATLAB verification session.
cfg=eba.config(); T=eba.families(20,cfg); again=eba.families(20,cfg);
assert(isequaln(T,again)); r=eba.validateFamilies(T,cfg);
assert(r.ok && height(T)==2880 && sum(T.class_id<=9)==2160 && r.families_per_cell==20);
assert(all(r.cell_counts(:)==20)); quotas=reshape(r.split_counts,[],3);
assert(all(quotas(:,1)==14) && all(quotas(:,2)==3) && all(quotas(:,3)==3));
assert(1+numel(cfg.snr_db)*cfg.noise_realizations==19);
expanded=eba.families(40,cfg); [present,where]=ismember(T.family_id,expanded.family_id);
assert(all(present) && isequaln(T,expanded(where,:)),'Earlier families or splits changed on expansion.');
assert(sum(expanded.split=="train")==2*sum(T.split=="train"));

% Known positive controls: the oracle must reject leakage and scientific corruption.
bad=[T;T(1,:)]; bad.split(end)="test"; rejects(@() eba.validateFamilies(bad,cfg),'eba:FamilyLeakage');
bad=T; bad.class_id(1)=2; rejects(@() eba.validateFamilies(bad,cfg),'eba:Class');
bad=T; bad.family_id(1)="missing"; rejects(@() eba.validateFamilies(bad,cfg),'eba:FamilyIdentity');
bad=T; bad.project_severity(241)="none"; rejects(@() eba.validateFamilies(bad,cfg),'eba:Severity');
bad=T; bad.split(1)="unknown"; rejects(@() eba.validateFamilies(bad,cfg),'eba:Split');
bad=T; bad.split(1)="train"; if T.split(1)=="train", bad.split(1)="validation"; end
rejects(@() eba.validateFamilies(bad,cfg),'eba:SplitIdentity');
bad=T; bad.event_end_sample(241)=bad.event_end_sample(241)+1; rejects(@() eba.validateFamilies(bad,cfg),'eba:EventSupport');
bad=T; bad.physical_event_duration_s(241)=2; rejects(@() eba.validateFamilies(bad,cfg),'eba:Duration');
bad=T; bad.labels_json(1)='"normal"'; rejects(@() eba.validateFamilies(bad,cfg),'eba:Labels');
bad=T(1:end-1,:); rejects(@() eba.validateFamilies(bad,cfg),'eba:Balance');
bad=T; p=jsondecode(bad.parameters_json(241)); p.voltage_factor=.999; bad.parameters_json(241)=jsonencode(p);
rejects(@() eba.validateFamilies(bad,cfg),'eba:Amplitude');
badCfg=cfg; badCfg.model_seed=badCfg.stream_seed; rejects(@() eba.validateFamilies(T,badCfg),'eba:SeedCollision');

N=round(cfg.Fs*cfg.clip_duration_s); idx=(0:N-1)'; hashes=strings(height(T),1); repeated=hashes;
for i=1:height(T)
    p=jsondecode(T.parameters_json(i)); x=eba.waveform(p,idx,cfg);
    assert(isa(x,'double') && iscolumn(x) && numel(x)==10000 && all(isfinite(x)));
    hashes(i)=eba.hash(x,'numeric');
    repeated(i)=eba.hash(eba.waveform(jsondecode(again.parameters_json(i)),idx,cfg),'numeric');
    if T.class_name(i)=="notching"
        base=reference(p,idx,cfg); away=abs(base)>.02;
        assert(all(sign(x(away))==sign(base(away))) && all(abs(x)<=abs(base)+1e-12));
        assert(any(abs(x-base)>1e-6),'Notch perturbation is absent.');
    elseif T.class_name(i)=="impulsive_transient"
        assert(p.end_sample-p.start_sample>=10);
        support=idx>=p.start_sample & idx<p.end_sample;
        base=reference(p,idx,cfg); assert(all(abs(x(~support)-base(~support))<1e-12));
        assert(sum(abs(x(support)-base(support))>1e-9)>=8);
    elseif any(T.class_name(i)==["voltage_sag" "voltage_swell" "interruption"])
        base=reference(p,idx,cfg); interior=idx>=p.start_sample+p.taper_samples & idx<=p.end_sample-p.taper_samples;
        assert(max(abs(x(interior)-p.voltage_factor*base(interior)))<1e-11);
    end
end
wholeHash=eba.hash(strjoin(hashes,''),'text');
assert(strcmp(wholeHash,eba.hash(strjoin(repeated,''),'text')),'Whole-dataset deterministic waveform identity failed.');
assert(numel(unique(hashes))==height(T),'Independent generated families unexpectedly duplicate waveform bytes.');

for c=1:12
    i=find(T.class_id==c & T.split=="train",1); p=jsondecode(T.parameters_json(i));
    full=eba.waveform(p,idx,cfg); chunks=[eba.waveform(p,idx(1:1777),cfg); ...
        eba.waveform(p,idx(1778:6000),cfg);eba.waveform(p,idx(6001:end),cfg)];
    assert(isequal(full,chunks),'Absolute phase differs across chunks.');
    [clean,meta]=eba.record(T(i,:),Inf,1,cfg,'development');
    assert(isequal(clean,full) && isinf(meta.measured_snr_db) && meta.noise_realization==0 && ...
        strcmp(meta.waveform_sha256,eba.hash(full,'numeric')));
    assert(string(meta.record_id)==eba.recordId(T.family_id(i),Inf,0));
    [nominal,nominalMeta]=eba.record(T(i,:),20,1,cfg,'development','nominal_baseline_rms_power');
    assert(abs(nominalMeta.measured_snr_db-20)<1e-10 && abs(10*log10(p.base_rms_pu^2/mean((nominal-clean).^2))-20)<1e-10);
    assert(nominalMeta.reference_power_pu2==p.base_rms_pu^2 && string(nominalMeta.record_id)==eba.recordId(T.family_id(i),20,1));
    assert(abs(nominalMeta.measured_disturbed_record_snr_db-10*log10(mean(clean.^2)/mean((nominal-clean).^2)))<1e-12);
    unit=[];
    for snr=cfg.snr_db(:)'
        [noisy,m]=eba.record(T(i,:),snr,1,cfg,'development'); z=noisy-clean;
        assert(abs(m.measured_snr_db-snr)<1e-10 && abs(10*log10(sum(clean.^2)/sum(z.^2))-snr)<1e-10);
        assert(string(m.record_id)==eba.recordId(T.family_id(i),snr,1));
        assert(abs(mean(z))<1e-12 && m.noise_realization==1 && m.requested_snr_db==snr);
        direction=z/norm(z); if isempty(unit), unit=direction; else, assert(norm(direction-unit)<1e-12); end
        [duplicate,m2]=eba.record(T(i,:),snr,1,cfg,'development'); assert(isequal(noisy,duplicate) && isequal(m,m2));
    end
    [x1,m1]=eba.record(T(i,:),10,1,cfg,'development'); [x2,m2]=eba.record(T(i,:),10,2,cfg,'development');
    assert(m1.noise_seed~=m2.noise_seed && ~isequal(x1,x2));
end
rejects(@() eba.recordId("f",Inf,1),'eba:RecordIdentity');
rejects(@() eba.recordId("f",20,0),'eba:RecordIdentity');
rejects(@() eba.record(T(1,:),20,1,cfg,'development','undefined'),'eba:NoiseReference');
i=find(T.split=="test",1); rejects(@() eba.record(T(i,:),Inf,1,cfg,'development'),'eba:TestFirewall');
structural=eba.record(T(i,:),Inf,1,cfg,'structural'); assert(numel(structural)==N);
rejects(@() eba.record(T(1,:),Inf,1,cfg,'unknown'),'eba:RecordMode');
rejects(@() eba.record(T(1,:),10,0,cfg,'structural'),'eba:Realization');
rejects(@() eba.noise(zeros(N,1),10,12),'eba:ZeroEnergy');
rejects(@() eba.noise([1 NaN],10,12),'eba:NoiseInput');
rejects(@() eba.noise(ones(10,1),-Inf,12),'eba:SNR');
rejects(@() eba.waveform(jsondecode(T.parameters_json(1)),[-1 0],cfg),'eba:SampleIndices');

% Numerical alias sensitivity: smooth compact pulses are never claimed strictly bandlimited.
i=find(T.class_name=="impulsive_transient" & T.duration_stratum==1,1); p=jsondecode(T.parameters_json(i));
p.end_sample=p.start_sample+10; highCfg=cfg; highCfg.Fs=8*cfg.Fs; highP=p;
highP.start_sample=p.start_sample*8; highP.end_sample=p.end_sample*8;
highIdx=(0:8*N-1)'; high=eba.waveform(highP,highIdx,highCfg)-reference(highP,highIdx,highCfg);
H=fft(high); frequency=(0:numel(H)-1)'*highCfg.Fs/numel(H);
outOfBand=frequency>cfg.Fs/2 & frequency<highCfg.Fs-cfg.Fs/2;
aliasFraction=sum(abs(H(outOfBand)).^2)/sum(abs(H).^2);
assert(isfinite(aliasFraction) && aliasFraction<.01,'One-millisecond smooth pulse has excessive numerical out-of-band energy.');
assert(max(abs(eba.waveform(p,idx,cfg)-eba.waveform(highP,8*idx,highCfg)))<1e-11);

review=eba.fixtureReview(cfg); assert(review.n_fixtures==9 && ~review.original630_identity_reconstructed);
assert(all([review.fixtures.n_samples]==10000) && all(isfinite([review.fixtures.max_absolute_equation_error_pu])));
notch=review.fixtures(strcmp({review.fixtures.class_name},'notching')); assert(notch.legacy_notch_risk);
impulse=review.fixtures(strcmp({review.fixtures.class_name},'impulsive_transient'));
assert(impulse.legacy_impulse_below_new_10_sample_support && impulse.declared_event_sample_count<10);
for i=1:9
    assert(strcmp(review.fixtures(i).original_sha256, ...
        eba.hash(fullfile(cfg.root,'fixtures','dataset_fixture',review.fixtures(i).file),'file')));
end
fprintf('SIGNALS_SCIENTIFIC_TESTS_PASS families=%d core=%d derivatives=%d waveform_hash=%s pulse_alias_fraction=%.12g\n', ...
    height(T),sum(T.class_id<=9),height(T)*19,wholeHash,aliasFraction);
end

function x=reference(p,idx,cfg)
x=sqrt(2)*p.base_rms_pu*sin(2*pi*p.frequency_hz*double(idx(:))/cfg.Fs+p.phase_rad);
end

function rejects(f,expected)
failed=false;
try, f(); catch err, failed=strcmp(err.identifier,expected); end
assert(failed,'Positive rejection control failed for %s.',expected);
end
