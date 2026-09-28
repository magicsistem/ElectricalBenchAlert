function summary=run_scientific_sensitivity(stage)
%RUN_SCIENTIFIC_SENSITIVITY Paired development-only input-length and noise-reference checks.
if nargin<1,stage="clips";end
stage=string(stage);assert(any(stage==["clips","nominal_noise"]),'eba:SensitivityStage','Unknown sensitivity experiment.');
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test" & F.class_id<=cfg.primary_class_count,:);
S=load(fullfile(cfg.output,'development_transform_selection.mat'),'selected','methods');
D=load(fullfile(cfg.output,'development_classifiers.mat'),'models');
statCfg=cfg;statCfg.classes=cfg.classes(1:cfg.primary_class_count);artifacts=strings(0,1);
if stage=="clips"
    [families,cal]=eba.subsetFamilies(F,3,1);lengths=[.2 .5 1];predictions=[];names=strings(0,1);validation=[];rows=cell(5,3);
    for m=1:5
        for j=1:3
            N=round(lengths(j)*cfg.Fs);parameters=eba.windowParameters(S.methods(m),S.selected{m},N);
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
    coverage=vertcat(rows{:});writetable(coverage,fullfile(cfg.output,'sensitivity_clip_coverage.csv'));
    limitation='Oracle event-centred offline crops ensure target visibility; shorter clips can truncate physical support. This is conditional EventBench sensitivity and cannot select online timing.';
else
    valFamilies=F(F.split=="validation",:);predictions=[];validation=[];
    for m=1:5
        [X,P]=nominalFeatures(valFamilies,S.methods(m),S.selected{m},cfg);
        if isempty(validation),validation=P;else,assert(isequal(validation,P),'eba:PairedRecords','Noise-reference sensitivity lost pairing.');end
        predictions(:,m)=eba.predict(D.models{m,1},X); %#ok<AGROW>
        fprintf('NOISE_REFERENCE_SENSITIVITY_EVALUATED method=%s families=%d\n',S.methods(m),height(valFamilies));
    end
    statCfg.comparison_family="nominal_power_noise_secondary_dsp_comparisons";
    [summary,pairs,noise,details]=eba.familyStats(validation,predictions,S.methods,statCfg);
    limitation='Models trained with clean disturbed-record power; evaluation noise scaled to undisturbed fundamental RMS power. SNR axes explicitly use requested nominal-reference dB; measured disturbed-record SNR is separate.';
end
prefix="sensitivity_"+stage;paths=[fullfile(cfg.output,prefix+"_metrics.csv");fullfile(cfg.output,prefix+"_paired.csv");fullfile(cfg.output,prefix+"_snr.csv");fullfile(cfg.output,prefix+"_statistics.mat")];
writetable(summary,paths(1));writetable(pairs,paths(2));writetable(noise,paths(3));save(paths(4),'summary','pairs','noise','details','validation','predictions','limitation','-v7.3');artifacts=[artifacts;paths];
eba.manifest(prefix,cfg,struct('scope','development only; no test access; secondary scientific sensitivity', ...
    'method',stage,'parameters',struct('lengths_s',[.2 .5 1],'snrs_db',[Inf 20 5],'realization',1), ...
    'classifier','fixed selected SVM hyperparameters; no additional search', ...
    'dataset_hash',eba.hash(jsonencode(table2struct(F))),'split_hash',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'})))), ...
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
P.record_id=P.family_id+"_snr"+string(P.SNR_db)+"_r"+string(P.realization_id);
assert(all(isnan(coverage(P.class_id==1))) && all(coverage(P.class_id~=1)>0 & coverage(P.class_id~=1)<=1),'eba:ClipCoverage','Every conditional classification clip must contain physical target support.');
end
function [X,P]=nominalFeatures(F,method,parameters,cfg)
X=zeros(height(F)*3,24);P=metadata(height(F)*3);measured=zeros(height(P),1);k=0;
for i=1:height(F)
    p=jsondecode(F.parameters_json(i));clean=eba.record(F(i,:),Inf,1,cfg,'development');
    for snr=[Inf 20 5]
        k=k+1;signal=clean;
        if isfinite(snr)
            noisy=eba.record(F(i,:),snr,1,cfg,'development');noise=(noisy-clean)*p.base_rms_pu/sqrt(mean(clean.^2));signal=clean+noise;
            assert(abs(10*log10(p.base_rms_pu^2/mean(noise.^2))-snr)<1e-10,'eba:SNR','Nominal-reference SNR verification failed.');
            measured(k)=10*log10(mean(clean.^2)/mean(noise.^2));
        else,measured(k)=Inf;end
        X(k,:)=eba.features(signal,cfg.Fs,method,parameters);P(k,:)={F.family_id(i),F.split(i),F.class_id(i),snr,double(isfinite(snr))};
    end
end
P.record_id=P.family_id+"_snr"+string(P.SNR_db)+"_r"+string(P.realization_id);
P.measured_disturbed_record_snr_db=measured;
end
function P=metadata(n)
P=table('Size',[n 5],'VariableTypes',{'string','string','double','double','double'}, ...
    'VariableNames',{'family_id','split','class_id','SNR_db','realization_id'});
end
