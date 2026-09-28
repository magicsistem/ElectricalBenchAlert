function report=verify_dataset_records()
%VERIFY_DATASET_RECORDS Regenerate every candidate record; scientific invariant access only.
% Structural generation includes split-labelled records but computes no features/model responses.
% This validates the generator/catalog; it cannot authorize opening the final classifier test.
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);nVariants=1+numel(cfg.snr_db)*cfg.noise_realizations;
sources={'+eba/families.m','+eba/record.m','+eba/waveform.m','+eba/noise.m','+eba/hash.m','scripts/verify_dataset_records.m'};
digests=cellfun(@(x) eba.hash(fullfile(cfg.root,x),'file'),sources,'UniformOutput',false);
familyHash=eba.hash(jsonencode(table2struct(F)));sourceHash=eba.hash(strjoin(digests,''));
folder=fullfile(cfg.output,"record_catalog_"+familyHash(1:12)+"_"+sourceHash(1:12));if ~isfolder(folder),mkdir(folder);end
csvPath=fullfile(folder,'records.csv');matPath=fullfile(folder,'records.mat');reportPath=fullfile(folder,'report.json');existing=[];
if isfile(matPath),saved=load(matPath,'V');existing=saved.V;end
assert(isfile(matPath)==isfile(csvPath),'eba:PartialDataset','Incomplete record catalog must be preserved and reviewed before regeneration.');
V=table('Size',[height(F)*nVariants 11],'VariableTypes',{'string','string','string','double','double','double','double','double','double','double','string'}, ...
    'VariableNames',{'record_id','family_id','split','class_id','requested_snr_db','measured_snr_db','realization_id','noise_seed','family_seed','reference_power_pu2','waveform_sha256'});
k=0;maximumDeviation=0;
for i=1:height(F)
    for snr=[Inf cfg.snr_db(:).']
        reps=1:cfg.noise_realizations;if isinf(snr),reps=1;end
        for realization=reps
            [signal,meta]=eba.record(F(i,:),snr,realization,cfg,'structural');k=k+1;
            assert(numel(signal)==cfg.Fs*cfg.clip_duration_s && all(isfinite(signal)), ...
                'eba:DatasetWaveform','Invalid waveform size or finite range.');
            id=F.family_id(i)+"_snr"+snr+"_r"+meta.noise_realization;
            V(k,:)={id,F.family_id(i),F.split(i),F.class_id(i),snr,meta.measured_snr_db,meta.noise_realization, ...
                meta.noise_seed,F.family_seed(i),meta.reference_power_pu2,meta.waveform_sha256};
            if isfinite(snr),maximumDeviation=max(maximumDeviation,abs(meta.measured_snr_db-snr));end
        end
    end
    if mod(i,100)==0 || i==height(F),fprintf('STRUCTURAL_RECORD_REGENERATION families=%d/%d records=%d\n',i,height(F),k);end
end
assert(k==height(V) && numel(unique(V.record_id))==height(V) && maximumDeviation<1e-10, ...
    'eba:DatasetCatalog','Record count, identity or achieved SNR verification failed.');
reverified=~isempty(existing);
if reverified
    assert(isequaln(V,existing),'eba:DatasetDeterminism','Full regenerated catalog differs from the previous record identities, noise measurements or waveform hashes.');
else,writetable(V,csvPath);save(matPath,'V','-v7');end
report=struct('status','candidate generator scientifically validated; final dataset size/freeze acceptance separate', ...
    'n_independent_families',height(F),'n_derived_records',height(V),'n_clean_records',sum(isinf(V.requested_snr_db)), ...
    'n_noisy_records',sum(isfinite(V.requested_snr_db)),'maximum_snr_deviation_db',maximumDeviation, ...
    'noise_reference',cfg.noise_reference,'noise_levels_paired_within_family_realization',true, ...
    'dataset_parameter_sha256',familyHash,'generator_source_sha256',sourceHash, ...
    'catalog_csv_sha256',eba.hash(csvPath,'file'),'waveform_catalog_sha256',eba.hash(strjoin(V.waveform_sha256,'')), ...
    'full_catalog_regeneration_reverified',reverified,'model_responses_computed',false,'access_mode','structural');
% Keep original first-pass provenance separate from the independent re-verification.
if reverified,reportPath=fullfile(folder,'reverification_report.json');end
eba.json(reportPath,report);id="structural_records_"+familyHash(1:12)+"_"+sourceHash(1:12);if reverified,id=id+"_reverification";end
eba.manifest(id,cfg,struct('scope','full physical generation and SNR/hash invariants only; no classification/test tuning', ...
    'method','deterministic waveform plus scaled paired AWGN','parameters',struct('records_per_family',nVariants), ...
    'dataset_hash',familyHash,'split_hash',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'})))), ...
    'full_catalog_reverified',reverified,'waveform_catalog_sha256',report.waveform_catalog_sha256),{csvPath,matPath,reportPath});
fprintf('DATASET_RECORD_CATALOG_PASS families=%d records=%d maximum_snr_deviation_db=%.12g reverified=%d\n',height(F),height(V),maximumDeviation,reverified);
end
