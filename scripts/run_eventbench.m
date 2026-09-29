function report=run_eventbench()
%RUN_EVENTBENCH Frozen offline test; no training, selection, thresholds or model updates.
cfg=eba.config();freeze=eba.requireFrozen(cfg,'begin');cleanup=onCleanup(@() eba.requireFrozen(cfg,'reset'));
assert(isfield(freeze,'offline_models') && isfield(freeze,'raw_models') && isfield(freeze,'combined_models'), ...
    'eba:TestFirewall','All frozen offline model paths must be declared before test.');
F=eba.families(cfg.families_per_cell,cfg);test=F(F.split=="test" & F.class_id<=cfg.primary_class_count,:);
bindings=freeze.bound_files;catalogIndex=find(string({bindings.role})=="dataset" & endsWith(string({bindings.path}),'/records.csv'));
assert(isscalar(catalogIndex),'eba:FrozenRecords','Exactly one waveform catalog must be hash bound.');
catalog=readtable(fullfile(cfg.root,bindings(catalogIndex).path),'TextType','string');

stamp=string(datetime('now','TimeZone','UTC','Format',"yyyyMMdd'T'HHmmssSSS"));
folder=fullfile(cfg.output,"final_eventbench_"+stamp);assert(~isfolder(folder),'eba:FinalImmutable','Final outputs must be append-only.');mkdir(folder);
artifacts=strings(0,1);modelSpecs=cell(0,1);allMetadata=[];predictions=cell(5,2);methods=["FFT","STFT","DWT","CWT","ST"];
for m=1:numel(methods)
    for k=1:2
        kinds=["SVM","RF"];kind=kinds(k);
        entry=find(string({freeze.offline_models.method})==methods(m) & string({freeze.offline_models.classifier})==kind);
        assert(numel(entry)==1,'eba:TestFirewall','Each frozen representation/classifier needs exactly one model.');
        M=load(fullfile(cfg.root,freeze.offline_models(entry).path),'model');model=M.model;
        modelSpecs{end+1}=struct('track','primary_nine_classes','method',model.method,'classifier',model.kind, ...
            'parameters',model.parameters,'hyperparameters',model.hyperparameters,'path',freeze.offline_models(entry).path); %#ok<AGROW>
        assert(model.method==methods(m) && model.kind==kind && model.calibrated,'eba:FrozenModel','Frozen offline model identity differs.');
        [X,P]=eba.extract(test,model.method,model.parameters,cfg,'final');
        verifyCanonicalRecords(P,catalog);
        if isempty(allMetadata),allMetadata=P;else,assert(isequal(allMetadata,P),'eba:PairedRecords','Final representations received different records.');end
        [pred,confidence]=eba.predict(model,X);predictions{m,k}=pred;
        tableOut=P;tableOut.predicted_class_id=pred;tableOut.confidence=confidence;
        path=fullfile(folder,"predictions_"+lower(methods(m))+"_"+lower(kind)+".csv");writetable(tableOut,path);artifacts(end+1)=path; %#ok<AGROW>
        fprintf('FINAL_OFFLINE_PREDICTIONS method=%s classifier=%s independent_families=%d records=%d\n',methods(m),kind,numel(unique(P.family_id)),height(P));
    end
end
statCfg=cfg;statCfg.classes=cfg.classes(1:cfg.primary_class_count);tracks=cell(2,1);
for k=1:2
    kinds=["SVM","RF"];kind=kinds(k);statCfg.comparison_family="frozen_final_dsp_"+lower(kind);
    [summary,pairs,noise,details]=eba.familyStats(allMetadata,horzcat(predictions{:,k}),methods,statCfg);tracks{k}=summary;
    artifacts=[artifacts;writeStatistics(folder,"dsp_"+lower(kind),summary,pairs,noise,details)]; %#ok<AGROW>
end
% Raw architectures/seeds are separately identified; seeds are never counted as families.
rawNames=strings(numel(freeze.raw_models),1);rawPredictions=zeros(height(allMetadata),numel(rawNames));
for r=1:numel(rawNames)
    entry=freeze.raw_models(r);M=load(fullfile(cfg.root,entry.path),'model');model=M.model;
    assert(~model.structural_test_only && model.calibrated && model.sequence_samples==cfg.Fs*cfg.clip_duration_s, ...
        'eba:FrozenModel','A full trained, calibrated raw model is required.');
    rawNames(r)=string(model.kind)+"_seed"+model.seed;
    modelSpecs{end+1}=struct('track','raw_primary_nine_classes','method',model.kind,'classifier',model.kind, ...
        'parameters',model.architecture,'hyperparameters',struct('seed',model.seed,'input_normalization','none'), ...
        'path',entry.path); %#ok<AGROW>
    out=allMetadata;out.predicted_class_id=zeros(height(out),1);out.confidence=zeros(height(out),1);
    for first=1:64:height(out)
        rows=first:min(first+63,height(out));waves=cell(numel(rows),1);
        for j=1:numel(rows)
            index=find(test.family_id==out.family_id(rows(j)));assert(numel(index)==1);
            [waves{j},meta]=eba.record(test(index,:),out.SNR_db(rows(j)),max(1,out.realization_id(rows(j))),cfg,'final');
            assert(string(meta.waveform_sha256)==out.waveform_sha256(rows(j)),'eba:FrozenRecords','Raw and DSP tracks must receive the same catalog-verified waveform.');
        end
        [pred,confidence]=eba.rawPredict(model,waves);out.predicted_class_id(rows)=pred;out.confidence(rows)=confidence;
    end
    rawPredictions(:,r)=out.predicted_class_id;
    path=fullfile(folder,"predictions_"+lower(rawNames(r))+".csv");writetable(out,path);artifacts(end+1)=path; %#ok<AGROW>
    fprintf('FINAL_RAW_PREDICTIONS method=%s independent_families=%d records=%d\n',rawNames(r),numel(unique(out.family_id)),height(out));
end
statCfg.comparison_family="frozen_raw_seed_sensitivity";statCfg.planned_comparisons=nchoosek(1:numel(rawNames),2);
[rawSummary,rawPairs,rawNoise,rawDetails]=eba.familyStats(allMetadata,rawPredictions,rawNames,statCfg);
artifacts=[artifacts;writeStatistics(folder,"raw",rawSummary,rawPairs,rawNoise,rawDetails)];
% Closed-composite sensitivity has a different twelve-class estimand and its own comparisons.
combinedTest=F(F.split=="test",:);combinedPredictions=cell(5,2);combinedMetadata=[];
for m=1:numel(methods)
    for k=1:2
        kinds=["SVM","RF"];kind=kinds(k);
        entry=find(string({freeze.combined_models.method})==methods(m) & string({freeze.combined_models.classifier})==kind);
        assert(numel(entry)==1,'eba:TestFirewall','Every closed-composite model must be frozen.');
        M=load(fullfile(cfg.root,freeze.combined_models(entry).path),'model');model=M.model;
        modelSpecs{end+1}=struct('track','secondary_twelve_closed_classes','method',model.method,'classifier',model.kind, ...
            'parameters',model.parameters,'hyperparameters',model.hyperparameters,'path',freeze.combined_models(entry).path); %#ok<AGROW>
        [X,P]=eba.extract(combinedTest,model.method,model.parameters,cfg,'final');
        verifyCanonicalRecords(P,catalog);
        if isempty(combinedMetadata),combinedMetadata=P;else,assert(isequal(combinedMetadata,P),'eba:PairedRecords','Closed-composite records differ.');end
        [pred,confidence]=eba.predict(model,X);combinedPredictions{m,k}=pred;
        out=P;out.predicted_class_id=pred;out.confidence=confidence;
        path=fullfile(folder,"combined_predictions_"+lower(methods(m))+"_"+lower(kind)+".csv");writetable(out,path);artifacts(end+1)=path; %#ok<AGROW>
    end
end
combinedTracks=cell(2,1);statCfg=cfg;
for k=1:2
    kinds=["SVM","RF"];kind=kinds(k);statCfg.comparison_family="frozen_closed_composite_"+lower(kind)+"_secondary";
    [summary,pairs,noise,details]=eba.familyStats(combinedMetadata,horzcat(combinedPredictions{:,k}),methods,statCfg);combinedTracks{k}=summary;
    artifacts=[artifacts;writeStatistics(folder,"closed_composite_"+lower(kind),summary,pairs,noise,details)]; %#ok<AGROW>
end
report=struct('experiment_id',freeze.experiment_id,'freeze_sha256',eba.hash(fullfile(cfg.root,'FROZEN_EXPERIMENT.json'),'file'), ...
    'test_families',height(test),'test_records',height(allMetadata),'dsp_svm',table2struct(tracks{1}), ...
    'dsp_rf',table2struct(tracks{2}),'raw',table2struct(rawSummary), ...
    'closed_composite_families',height(combinedTest),'closed_composite_records',height(combinedMetadata), ...
    'closed_composite_svm',table2struct(combinedTracks{1}),'closed_composite_rf',table2struct(combinedTracks{2}), ...
    'model_selection_after_test',false,'uncertainty_scope','family bootstrap conditional on frozen fitted models; raw seeds reported separately');
path=fullfile(folder,'eventbench_report.json');eba.json(path,report);artifacts(end+1)=path;
eba.requireFrozen(cfg,'end');eba.manifest('final_eventbench',cfg,struct('scope','frozen test evaluation only', ...
    'freeze_sha256',report.freeze_sha256,'n_primary_families',height(test),'n_primary_records',height(allMetadata), ...
    'methods',[methods "CNN" "TCN"],'parameters',{modelSpecs}, ...
    'hyperparameters',{cellfun(@(q) q.hyperparameters,modelSpecs,'UniformOutput',false)}, ...
    'classifier_tracks',["SVM","RF","raw CNN/TCN fixed seeds"]),artifacts);
fprintf('FROZEN_EVENTBENCH_PASS models=%d primary_families=%d records_per_model=%d training_calls=0\n',20+numel(rawNames),height(test),height(allMetadata));
end
function paths=writeStatistics(folder,prefix,summary,pairs,noise,details)
paths=[fullfile(folder,prefix+"_metrics.csv");fullfile(folder,prefix+"_paired.csv"); ...
    fullfile(folder,prefix+"_snr.csv");fullfile(folder,prefix+"_statistics.mat"); ...
    fullfile(folder,prefix+"_per_class.csv")];
writetable(summary,paths(1));writetable(pairs,paths(2));writetable(noise,paths(3));
save(paths(4),'summary','pairs','noise','details','-v7.3');writetable(details.per_class_recall,paths(5));
end

function verifyCanonicalRecords(P,catalog)
% Byte identities precede frozen model responses; CSV SNR rounding is explicitly tolerated.
fields={'family_id','split','class_id','requested_snr_db','realization_id','waveform_sha256'};
assert(isequaln(P.SNR_db,P.requested_snr_db),'eba:FrozenRecords','Reported SNR conditions differ from the declared physical noise levels.');
assert(numel(unique(P.record_id))==height(P) && numel(unique(catalog.record_id))==height(catalog), ...
    'eba:FrozenRecords','Record identities must be unique.');
[found,index]=ismember(P.record_id,catalog.record_id);
assert(all(found) && isequaln(P(:,fields),catalog(index,fields)), ...
    'eba:FrozenRecords','Evaluated physical records differ from the frozen canonical waveform identities.');
assert(all(isfinite(P.measured_snr_db) | P.measured_snr_db==Inf) && ...
    isequaln(isinf(P.measured_snr_db),isinf(catalog.measured_snr_db(index))), ...
    'eba:FrozenRecords','Clean/noisy power metadata differs.');
noisy=isfinite(P.measured_snr_db);difference=abs(P.measured_snr_db(noisy)-catalog.measured_snr_db(index(noisy)));
assert(all(difference<1e-12) && all(isfinite(P.measured_snr_db(noisy))), ...
    'eba:FrozenRecords','Measured SNR differs beyond native CSV roundoff.');
end
