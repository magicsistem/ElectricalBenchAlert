function summary=run_scientific_sensitivity(stage)
%RUN_SCIENTIFIC_SENSITIVITY Paired development-only input-length and noise-reference checks.
if nargin<1,stage="clips";end
stage=string(stage);assert(any(stage==["clips","nominal_noise"]),'eba:SensitivityStage','Unknown sensitivity experiment.');
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test" & F.class_id<=cfg.primary_class_count,:);
S=load(fullfile(cfg.output,'development_transform_selection.mat'),'selected','methods');
D=load(fullfile(cfg.output,'development_classifiers.mat'),'models','validationP','predictions');
statCfg=cfg;statCfg.classes=cfg.classes(1:cfg.primary_class_count);artifacts=strings(0,1);
if stage=="clips"
    [families,cal]=eba.subsetFamilies(F,3,1);lengths=[.2 .5 1];parameterGrid=cell(5,3);inputFamilies=families;predictions=[];names=strings(0,1);validation=[];rows=cell(5,3);
    for m=1:5
        for j=1:3
            N=round(lengths(j)*cfg.Fs);parameters=eba.windowParameters(S.methods(m),S.selected{m},N);parameterGrid{m,j}=parameters;
            [X,P,coverage]=cropFeatures(families,N,S.methods(m),parameters,cfg);
            fitting=P.split=="train" & ~ismember(P.family_id,cal);val=P.split=="validation";
            model=eba.fit(X(fitting,:),P.class_id(fitting),cfg,'SVM',D.models{m,1}.hyperparameters);
            predicted=eba.predict(model,X(val,:));predictions(:,end+1)=predicted; %#ok<AGROW>
            names(end+1)=S.methods(m)+"_"+lengths(j)+"s"; %#ok<AGROW>
            if isempty(validation),validation=P(val,:);else,assert(isequal(validation,P(val,:)),'eba:PairedRecords','Clip sensitivity lost family pairing.');end
            rows{m,j}=table(S.methods(m),lengths(j),sum(val),numel(unique(P.family_id(val))),mean(coverage(val),'omitnan'), ...
                'VariableNames',{'method','clip_duration_s','n_validation_records','n_validation_families','mean_physical_support_fraction_retained'});
            fprintf('CLIP_SENSITIVITY_TRAINED method=%s duration_s=%.1f\n',S.methods(m),lengths(j));
        end
    end
    % Two predeclared comparisons against one second for each representation; one Holm family of ten.
    planned=zeros(10,2);
    for m=1:5,planned(2*m-1,:)=[3*m-2 3*m];planned(2*m,:)=[3*m-1 3*m];end
    statCfg.planned_comparisons=planned;statCfg.comparison_family="canonical_length_ten_secondary_comparisons";
    [summary,pairs,noise,details]=eba.familyStats(validation,predictions,names,statCfg);
    coverage=vertcat(rows{:});coveragePath=fullfile(cfg.output,'sensitivity_clip_coverage.csv');writetable(coverage,coveragePath);artifacts(end+1)=coveragePath;
    limitation='Oracle event-centred offline crops ensure target visibility; shorter clips can truncate physical support. This is conditional EventBench sensitivity and cannot select online timing.';
else
    valFamilies=F(F.split=="validation",:);inputFamilies=valFamilies;parameterGrid=S.selected;predictions=[];validation=[];names=strings(1,10);
    for m=1:5
        [X,P]=nominalFeatures(valFamilies,S.methods(m),S.selected{m},cfg);
        [found,index]=ismember(P.record_id,D.validationP.record_id);
        fields={'record_id','family_id','class_id','SNR_db','realization_id'};
        assert(all(found) && isequaln(P(:,fields),D.validationP(index,fields)) && ...
            isequal(P.reference_waveform_sha256,D.validationP.waveform_sha256(index)), ...
            'eba:PairedRecords','Reference predictions must match regenerated family/condition/waveform identities.');
        if isempty(validation),validation=P;else,assert(isequal(validation,P),'eba:PairedRecords','Noise-reference sensitivity lost pairing.');end
        reference=D.predictions{m,1}(index);nominal=eba.predict(D.models{m,1},X);
        assert(isequal(reference(P.SNR_db==Inf),nominal(P.SNR_db==Inf)), ...
            'eba:NoiseReference','The paired clean controls must be exactly equal.');
        predictions(:,2*m-1)=reference;predictions(:,2*m)=nominal; %#ok<AGROW>
        names(2*m-1)=S.methods(m)+"_disturbed_reference";names(2*m)=S.methods(m)+"_nominal_reference";
        fprintf('NOISE_REFERENCE_SENSITIVITY_EVALUATED method=%s families=%d\n',S.methods(m),height(valFamilies));
    end
    statCfg.comparison_family="paired_noise_reference_five_secondary_comparisons";
    statCfg.planned_comparisons=[(1:2:9)' (2:2:10)'];
    [summary,pairs,noise,details]=eba.familyStats(validation,predictions,names,statCfg);
    limitation='Five paired contrasts of fixed models under disturbed-record versus nominal-baseline noise power; identical validation families and clean/20/5 dB realization-1 conditions, each weighted one third. Shared record IDs identify paired conditions; separate waveform hashes identify the two power protocols. The requested dB axis uses each declared reference; measured disturbed-record SNR under nominal noise is stored separately. This cannot be compared directly with the original 19-condition aggregate.';
end
inputProtocol=struct('snrs_db',[Inf 20 5],'realization',1,'condition_weights',[1/3 1/3 1/3]);
if stage=="clips"
    inputProtocol.lengths_s=lengths;inputProtocol.noise_references=string(cfg.noise_reference);
else
    inputProtocol.lengths_s=cfg.clip_duration_s;
    inputProtocol.noise_references=["clean_disturbed_record_energy","nominal_baseline_rms_power"];
end
prefix="sensitivity_"+stage;paths=[fullfile(cfg.output,prefix+"_metrics.csv");fullfile(cfg.output,prefix+"_paired.csv");fullfile(cfg.output,prefix+"_snr.csv");fullfile(cfg.output,prefix+"_statistics.mat")];
writetable(summary,paths(1));writetable(pairs,paths(2));writetable(noise,paths(3));save(paths(4),'summary','pairs','noise','details','validation','predictions','limitation','-v7.3');artifacts=[artifacts;paths];
eba.manifest(prefix,cfg,struct('scope','development only; no test access; secondary scientific sensitivity', ...
    'method',stage,'methods',S.methods,'parameters',{parameterGrid}, ...
    'input_protocol',inputProtocol, ...
    'prediction_tracks',names,'source_classifiers_sha256',eba.hash(fullfile(cfg.output,'development_classifiers.mat'),'file'), ...
    'classifier','SVM','hyperparameters',D.models{1,1}.hyperparameters, ...
    'solver_configuration',D.models{1,1}.solver_configuration,'hyperparameter_policy','fixed selected shared core configuration; no additional search', ...
    'dataset_hash',eba.hash(jsonencode(table2struct(inputFamilies))),'split_hash',eba.hash(jsonencode(table2struct(inputFamilies(:,{'family_id','split'})))), ...
    'interpretation_limit',limitation),artifacts);
fprintf('SCIENTIFIC_SENSITIVITY_COMPLETE stage=%s test_accessed=0\n',stage);
end
function [X,P,coverage]=cropFeatures(F,N,method,parameters,cfg)
X=zeros(height(F)*3,24);P=metadata(height(F)*3);coverage=NaN(height(P),1);k=0;M=round(cfg.Fs*cfg.clip_duration_s);
for i=1:height(F)
    p=jsondecode(F.parameters_json(i));start=floor((M-N)/2);
    if F.class_id(i)~=1,start=min(M-N,max(0,round((p.start_sample+p.end_sample-N)/2)));end
    for snr=[Inf 20 5]
        k=k+1;signal=eba.record(F(i,:),snr,1,cfg,'development');X(k,:)=eba.features(signal(start+(1:N)),cfg.Fs,method,parameters);
        P(k,:)={F.family_id(i),F.split(i),F.class_id(i),snr,double(isfinite(snr))};
        if F.class_id(i)~=1,coverage(k)=max(0,min(start+N,p.end_sample)-max(start,p.start_sample))/(p.end_sample-p.start_sample);end
    end
end
P.record_id=canonicalIDs(P);
assert(all(isnan(coverage(P.class_id==1))) && all(coverage(P.class_id~=1)>0 & coverage(P.class_id~=1)<=1),'eba:ClipCoverage','Every conditional classification clip must contain physical target support.');
end
function [X,P]=nominalFeatures(F,method,parameters,cfg)
X=zeros(height(F)*3,24);P=metadata(height(F)*3);measured=zeros(height(P),1);k=0;
nominalHashes=strings(height(P),1);referenceHashes=nominalHashes;noiseSeeds=zeros(height(P),1);
for i=1:height(F)
    for snr=[Inf 20 5]
        k=k+1;[signal,meta]=eba.record(F(i,:),snr,1,cfg,'development','nominal_baseline_rms_power');
        assert(snr==Inf || abs(meta.measured_snr_db-snr)<1e-10,'eba:SNR','Nominal-reference SNR verification failed.');
        [~,referenceMeta]=eba.record(F(i,:),snr,1,cfg,'development','clean_disturbed_record_energy');
        assert(referenceMeta.noise_seed==meta.noise_seed,'eba:NoiseReference','Paired reference powers must share noise realization seeds.');
        nominalHashes(k)=string(meta.waveform_sha256);referenceHashes(k)=string(referenceMeta.waveform_sha256);noiseSeeds(k)=meta.noise_seed;
        measured(k)=meta.measured_disturbed_record_snr_db;
        X(k,:)=eba.features(signal,cfg.Fs,method,parameters);P(k,:)={F.family_id(i),F.split(i),F.class_id(i),snr,double(isfinite(snr))};
    end
end
P.record_id=canonicalIDs(P);
P.measured_disturbed_record_snr_db=measured;P.nominal_waveform_sha256=nominalHashes;
P.reference_waveform_sha256=referenceHashes;P.noise_seed=noiseSeeds;
end
function P=metadata(n)
P=table('Size',[n 5],'VariableTypes',{'string','string','double','double','double'}, ...
    'VariableNames',{'family_id','split','class_id','SNR_db','realization_id'});
end

function ids=canonicalIDs(P)
ids=strings(height(P),1);
for i=1:height(P),ids(i)=eba.recordId(P.family_id(i),P.SNR_db(i),P.realization_id(i));end
end
