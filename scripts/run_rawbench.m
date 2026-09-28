function summary = run_rawbench()
%RUN_RAWBENCH Four fixed development baselines; final evaluation remains centrally sealed.
cfg=eba.config(); F=eba.families(cfg.families_per_cell,cfg);
F=F(F.class_id<=cfg.primary_class_count & F.split~="test",:);
familyHash=eba.hash(jsonencode(table2struct(F)));
sources={'+eba/rawArchitecture.m','+eba/rawTrain.m','+eba/rawPredict.m','scripts/run_rawbench.m', ...
    '+eba/subsetFamilies.m','+eba/families.m','+eba/waveform.m','+eba/noise.m','+eba/record.m', ...
    '+eba/config.m','+eba/hash.m','+eba/json.m','+eba/metrics.m','+eba/manifest.m'};
digests=cellfun(@(p) eba.hash(fullfile(cfg.root,p),'file'),sources,'UniformOutput',false);
sourceHash=eba.hash(strjoin(digests,'')); configHash=eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file');
id="raw_development_"+string(familyHash(1:12))+"_"+string(sourceHash(1:12))+"_"+string(configHash(1:12));
folder=fullfile(cfg.output,char(id)); assert(~isfolder(folder),'eba:RawImmutable','Raw experiment output already exists; preserve prior results.');
mkdir(folder); artifacts=strings(0,1);
summary=table('Size',[4 12],'VariableTypes',{'string','double','double','double','double','double','double','double','double','double','double','string'}, ...
    'VariableNames',{'method','model_seed','validation_accuracy','validation_macro_f1','training_time_s', ...
    'learnable_parameters','serialized_model_bytes','epochs_completed','local_receptive_field_samples', ...
    'startup_RSS_bytes','process_VmHWM_bytes','stop_reason'});
index=0;
for kind=["CNN" "TCN"]
    for seed=[cfg.model_seed cfg.model_seed+1]
        index=index+1; fprintf('RAW_DEVELOPMENT_TRAIN kind=%s seed=%d\n',kind,seed);
        [model,report]=eba.rawTrain(F,cfg,kind,seed);
        stem=lower(kind)+"_seed"+seed;
        modelPath=fullfile(folder,char(stem+"_model.mat")); save(modelPath,'model','-v7');
        resultPath=fullfile(folder,char(stem+"_results.mat")); save(resultPath,'report','-v7');
        reportPath=fullfile(folder,char(stem+"_report.json")); eba.json(reportPath,report);
        predictionPath=fullfile(folder,char(stem+"_validation_predictions.csv"));
        writetable(struct2table(report.validation_predictions),predictionPath);
        artifacts=[artifacts;string(modelPath);string(resultPath);string(reportPath);string(predictionPath)]; %#ok<AGROW>
        summary(index,:)={kind,seed,report.validation_metrics.accuracy,report.validation_metrics.macro_f1, ...
            report.training_time_s,report.architecture.learnable_parameters,report.model_serialized_bytes, ...
            report.epochs_completed,report.architecture.local_receptive_field_samples,report.startup_RSS_bytes, ...
            report.process_VmHWM_bytes,string(report.stop_reason)};
        fprintf('RAW_DEVELOPMENT_COMPLETE kind=%s seed=%d validation_macro_f1=%.6g\n',kind,seed,report.validation_metrics.macro_f1);
    end
end
summaryPath=fullfile(folder,'raw_summary.csv'); writetable(summary,summaryPath); artifacts(end+1)=summaryPath;
extra=struct('scope','primary nine classes; development only; fixed architecture; two seeds', ...
    'dataset_hash',familyHash,'split_hash',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'})))), ...
    'raw_source_hash',sourceHash,'source_files',{sources},'source_sha256',{digests}, ...
    'model_seeds',[cfg.model_seed cfg.model_seed+1],'augmentation_snr_db',[Inf 20 5], ...
    'augmentation_realization',1,'final_test_opened',false,'training_repetitions',2, ...
    'final_19_variant_evaluation','separate frozen central evaluation');
eba.manifest(id,cfg,extra,artifacts);
fprintf('RAW_DEVELOPMENT_BENCHMARK_COMPLETE models=4\n');
end
