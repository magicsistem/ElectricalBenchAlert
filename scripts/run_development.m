function report = run_development(stage)
%RUN_DEVELOPMENT Prospective family-only representation, size and classifier decisions.
% Test waveform predictions are never requested; classifiers share one validation-selected configuration.
if nargin<1,stage="all";end
stage=string(stage);assert(any(stage==["all","representations","learning","classifiers"]));
if stage=="all"
    run_development('representations');run_development('classifiers');report=run_development('learning');return;
end
cfg=eba.config(); F=eba.families(cfg.families_per_cell,cfg);
F=F(F.split~="test" & F.class_id<=cfg.primary_class_count,:);
assert(all(F.split~="test"),'eba:TestFirewall','Development cannot contain test rows.');
methods=["FFT","STFT","DWT","CWT","ST"];
selectionFile=fullfile(cfg.output,'development_transform_selection.mat');
learningFile=fullfile(cfg.output,'development_learning.mat');
classifierFile=fullfile(cfg.output,'development_classifiers.mat');
if stage=="all" || stage=="representations"
    [small,cal]=eba.subsetFamilies(F,3,1); selected=cell(5,1); tables=cell(5,1);
    hp=struct('kernel','linear','box_constraint',1,'kernel_scale',1);
    for m=1:5
        candidates=eba.transformCandidates(methods(m),round(cfg.Fs*cfg.clip_duration_s),cfg);
        rows=cell(numel(candidates),1);best=-Inf;
        for c=1:numel(candidates)
            p=candidates(c).parameters;
            [X,P,info]=eba.extract(small,methods(m),p,cfg,'development',[Inf 20 5],1);
            train=P.split=="train" & ~ismember(P.family_id,cal); val=P.split=="validation";
            model=eba.fit(X(train,:),P.class_id(train),cfg,'SVM',hp);
            predictions=eba.predict(model,X(val,:)); met=eba.metrics(P.class_id(val),predictions,cfg.primary_class_count);
            rows{c}=table(methods(m),candidates(c).id,string(jsonencode(p)),met.macro_f1, ...
                median(info.feature_time_s),quantile(info.feature_time_s,.95),median(info.representation_bytes), ...
                height(small),sum(val),'VariableNames',{'method','candidate_id','parameters_json','validation_macro_f1', ...
                'feature_median_s','feature_p95_s','representation_bytes','n_families','n_validation_records'});
            % No runtime measurement is a tuning endpoint here; exact ties retain JSON grid order.
            if met.macro_f1>best+1e-12,best=met.macro_f1;selected{m}=p;end
            fprintf('DSP_SELECTION %s %d/%d MacroF1=%.6f\n',methods(m),c,numel(candidates),met.macro_f1);
        end
        tables{m}=vertcat(rows{:});
    end
    selection=vertcat(tables{:}); config_hash=eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file');
    save(selectionFile,'selected','methods','selection','config_hash','-v7');
    writetable(selection,fullfile(cfg.output,'development_transform_selection.csv'));
    eba.manifest('development_transform_selection',cfg,struct('scope','train_validation_only', ...
        'selection_rule','maximum_validation_macro_f1_then_grid_order','classifier',hp, ...
        'training_families_per_cell',3,'validation_families_per_cell',1,'snrs',[Inf 20 5],'noise_realizations',1), ...
        {selectionFile,fullfile(cfg.output,'development_transform_selection.csv')});
end
assert(isfile(selectionFile),'eba:DevelopmentOrder','Run representation selection first.');
S=load(selectionFile);assert(strcmp(S.config_hash,eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file')), ...
    'eba:DevelopmentMutation','Configuration changed since representation selection.');
if stage=="all" || stage=="learning"
    assert(isfile(classifierFile),'eba:DevelopmentOrder','Select classifier hyperparameters before learning curves.');
    selectedModels=cell(5,1);modelPaths=strings(5,1);modelHashes=strings(5,1);
    for m=1:5
        name="model_"+lower(methods(m))+"_svm.mat";path=fullfile(cfg.output,name);
        stored=load(path,'model');selectedModels{m}=stored.model;modelPaths(m)=path;modelHashes(m)=eba.hash(path,'file');
    end
    sources={'+eba/fit.m','+eba/predict.m','+eba/familyStats.m','+eba/metrics.m', ...
        '+eba/features.m','+eba/record.m','+eba/waveform.m','+eba/noise.m','+eba/subsetFamilies.m', ...
        '+eba/learningAcceptance.m','scripts/run_development.m'};
    sourceHashes=cellfun(@(p) eba.hash(fullfile(cfg.root,p),'file'),sources,'UniformOutput',false);
    learningSignature=eba.hash(jsonencode(struct('config',S.config_hash,'families',eba.hash(jsonencode(table2struct(F))), ...
        'model_sha256',modelHashes,'parameters',{S.selected},'source_sha256',{sourceHashes})));
    checkpointFolder=fullfile(cfg.output,'learning_checkpoints');if ~isfolder(checkpointFolder),mkdir(checkpointFolder);end
    rows=cell(5,numel(cfg.learning_train_families_per_cell)); curves=cell(size(rows));
    for m=1:5
        [X,P,info]=eba.extract(F,methods(m),S.selected{m},cfg,'development');
        for j=1:numel(cfg.learning_train_families_per_cell)
            n=cfg.learning_train_families_per_cell(j);[nested,cal]=eba.subsetFamilies(F,n,3);
            train=P.split=="train" & ismember(P.family_id,nested.family_id) & ~ismember(P.family_id,cal);
            val=P.split=="validation";
            signature=eba.hash(jsonencode(struct('run',learningSignature,'method',methods(m),'train_per_cell',n)));
            checkpointPath=fullfile(checkpointFolder,signature+".mat");
            if isfile(checkpointPath)
                saved=load(checkpointPath,'checkpoint');assert(strcmp(saved.checkpoint.signature,signature),'eba:LearningMutation','Learning checkpoint identity changed.');
                rows{m,j}=saved.checkpoint.row;curves{m,j}=saved.checkpoint.details;
                fprintf('LEARNING_CHECKPOINT_REUSED %s train_per_cell=%d\n',methods(m),n);continue;
            end
            reference=selectedModels{m};standardized=(X(train,reference.keep)-reference.mean(reference.keep))./reference.scale(reference.keep);
            reuse=isprop(reference.fitted,'X') && isprop(reference.fitted,'Y') && ...
                isequaln(reference.fitted.X,standardized) && isequaln(double(reference.fitted.Y),P.class_id(train)) && ...
                isequal(unique(P.family_id(train)),reference.training_family_ids) && ...
                strcmp(info.family_hash,reference.training_dataset_hash) && reference.seed==cfg.model_seed && ...
                isequaln(reference.mean,mean(X(train,:),1)) && isequaln(reference.scale,std(X(train,:),0,1));
            if reuse,model=reference;
            else,model=eba.fit(X(train,:),P.class_id(train),cfg,'SVM',reference.hyperparameters);end
            fittingInput=(X(train,model.keep)-model.mean(model.keep))./model.scale(model.keep);
            pred=eba.predict(model,X(val,:)); statCfg=cfg;statCfg.classes=cfg.classes(1:cfg.primary_class_count);
            [summary,~,~,details]=eba.familyStats(P(val,:),pred,methods(m),statCfg);
            rows{m,j}=table(methods(m),n,(n-1)*12,numel(unique(P.family_id(train))),sum(train), ...
                summary.macro_f1,summary.macro_f1_ci_low,summary.macro_f1_ci_high, ...
                'VariableNames',{'method','train_per_cell','fit_families_per_class','n_fit_families','n_fit_records', ...
                'macro_f1','ci_low','ci_high'});
            curves{m,j}=details;
            checkpoint=struct('signature',signature,'row',rows{m,j},'details',details,'predictions',pred, ...
                'fit_family_ids',unique(P.family_id(train)),'validation_family_ids',unique(P.family_id(val)), ...
                'reused_exact_full_fit',reuse,'fitting_input_sha256',eba.hash(fittingInput,'numeric'),'reference_model_sha256',modelHashes(m), ...
                'reference_model_path',erase(modelPaths(m),[cfg.root filesep]));
            save(checkpointPath,'checkpoint','-v7');
            fprintf('LEARNING %s families/class=%d MacroF1=%.6f CI=[%.6f %.6f]\n',methods(m),(n-1)*12, ...
                summary.macro_f1,summary.macro_f1_ci_low,summary.macro_f1_ci_high);
        end
    end
    learning=vertcat(rows{:});
    acceptance=eba.learningAcceptance(learning,methods,cfg);
    save(learningFile,'learning','acceptance','curves','-v7');
    writetable(learning,fullfile(cfg.output,'development_learning.csv'));writetable(acceptance,fullfile(cfg.output,'development_size_acceptance.csv'));
    eba.manifest('development_learning',cfg,struct('scope','train_validation_only','acceptance',table2struct(acceptance),'learning_signature',learningSignature, ...
        'checkpoint_policy','immutable input/source/model-bound point checkpoints; exact full-fitting model reuse verified against native stored X/Y, family IDs and training statistics'), ...
        {learningFile,fullfile(cfg.output,'development_learning.csv'),fullfile(cfg.output,'development_size_acceptance.csv')});
end
if stage=="all" || stage=="classifiers"
    [small,smallCal]=eba.subsetFamilies(F,6,3);[~,cal]=eba.subsetFamilies(F,max(cfg.learning_train_families_per_cell),3);
    models=cell(5,2); predictions=cell(5,2); searches=cell(5,2); validationP=[];
    sources={'+eba/fit.m','+eba/predict.m','+eba/calibrate.m','+eba/selectClassifier.m', ...
        '+eba/features.m','+eba/record.m','+eba/recordId.m','+eba/featureCacheKey.m', ...
        '+eba/waveform.m','+eba/noise.m','+eba/sharedHyperparameters.m','scripts/run_development.m'};
    digests=cellfun(@(p) eba.hash(fullfile(cfg.root,p),'file'),sources,'UniformOutput',false);
    runSignature=eba.hash(jsonencode(struct('config',S.config_hash,'families',eba.hash(jsonencode(table2struct(F))), ...
        'parameters',{S.selected},'source_sha256',{digests})));
    searchFolder=fullfile(cfg.output,'classifier_search');if ~isfolder(searchFolder),mkdir(searchFolder);end
    kinds=["SVM","RF"];
    for m=1:5
        [tuneX,tuneP]=eba.extract(small,methods(m),S.selected{m},cfg,'development',[Inf 20 5],1);
        for k=1:2
            signature=eba.hash(jsonencode(struct('run',runSignature,'method',methods(m),'classifier',kinds(k))));
            path=fullfile(searchFolder,signature+".mat");
            if isfile(path)
                saved=load(path,'search','search_signature');assert(strcmp(saved.search_signature,signature), ...
                    'eba:DevelopmentMutation','Classifier search checkpoint identity changed.');searches{m,k}=saved.search;
                fprintf('CLASSIFIER_SEARCH_REUSED %s %s\n',methods(m),kinds(k));
            else
                [~,search]=eba.selectClassifier(tuneX,tuneP,cfg,kinds(k),smallCal);searches{m,k}=search;search_signature=signature;
                save(path,'search','search_signature','-v7');
            end
        end
    end
    shared=cell(1,2);
    for k=1:2
        [shared{k},comparison]=eba.sharedHyperparameters(searches(:,k),methods);
        writetable(comparison,fullfile(cfg.output,"shared_hyperparameters_"+lower(kinds(k))+".csv"));
        fprintf('SHARED_CLASSIFIER_SELECTED %s %s\n',kinds(k),jsonencode(shared{k}));
    end
    for m=1:5
        [X,P,info]=eba.extract(F,methods(m),S.selected{m},cfg,'development');
        train=P.split=="train" & ~ismember(P.family_id,cal);calmask=P.split=="train" & ismember(P.family_id,cal);val=P.split=="validation";
        [review,redundancy]=eba.featureReview(X(train,:),P(train,:),info.feature_names,cfg);
        eba.json(fullfile(cfg.output,"feature_review_"+lower(methods(m))+".json"),review);
        writetable(redundancy,fullfile(cfg.output,"feature_redundancy_"+lower(methods(m))+".csv"));
        if isempty(validationP),validationP=P(val,:);else,assert(isequal(validationP,P(val,:)),'eba:PairedRecords','Representations received different records.');end
        for k=1:2
            kinds=["SVM","RF"];kind=kinds(k);
            checkpointPath=fullfile(cfg.output,"development_checkpoint_"+lower(methods(m))+"_"+lower(kind)+".mat");
            if isfile(checkpointPath)
                previous=load(checkpointPath,'checkpoint');
                if strcmp(previous.checkpoint.signature,runSignature)
                    models{m,k}=previous.checkpoint.model;predictions{m,k}=previous.checkpoint.predictions;
                    searches{m,k}=previous.checkpoint.search;
                    fprintf('CLASSIFIER_CHECKPOINT_REUSED %s %s\n',methods(m),kind);continue;
                end
            end
            model=eba.fit(X(train,:),P.class_id(train),cfg,kind,shared{k});
            model=eba.calibrate(model,X(calmask,:),P.class_id(calmask),P.family_id(calmask));
            pred=eba.predict(model,X(val,:)); predictions{m,k}=pred;
            model.method=methods(m);model.parameters=S.selected{m};model.training_family_ids=unique(P.family_id(train));
            model.training_dataset_hash=info.family_hash;model.model_version="development-"+lower(methods(m))+"-"+lower(kind);
            models{m,k}=model; modelPath=fullfile(cfg.output,"model_"+lower(methods(m))+"_"+lower(kind)+".mat");
            save(modelPath,'model','-v7.3');
            calibration=eba.calibrationMetrics(model,X(val,:),P.class_id(val));
            eba.json(fullfile(cfg.output,"validation_calibration_"+lower(methods(m))+"_"+lower(kind)+".json"),calibration);
            writetable(searches{m,k},fullfile(cfg.output,"hyperparameters_"+lower(methods(m))+"_"+lower(kind)+".csv"));
            checkpoint=struct('signature',runSignature,'model',model,'predictions',pred, ...
                'search',searches{m,k},'calibration_metrics',calibration);
            save(checkpointPath,'checkpoint','-v7.3');
            fprintf('CLASSIFIER_REFIT_COMPLETE %s %s fit_families=%d validation_records=%d\n', ...
                methods(m),kind,numel(model.training_family_ids),sum(val));
        end
    end
    for k=1:2,for m=1:5,assert(isequal(models{m,k}.hyperparameters,shared{k}), ...
        'eba:SharedClassifier','A representation received different classifier hyperparameters.');end;end
    save(classifierFile,'models','predictions','searches','validationP','methods','shared','-v7.3');
    statCfg=cfg;statCfg.classes=cfg.classes(1:cfg.primary_class_count);
    for k=1:2
        kinds=["SVM","RF"];kind=kinds(k);statCfg.comparison_family="development_"+lower(kind);
        [summary,pairs,robustness,details]=eba.familyStats(validationP,horzcat(predictions{:,k}),methods,statCfg);
        writetable(summary,fullfile(cfg.output,"validation_"+lower(kind)+"_metrics.csv"));
        writetable(pairs,fullfile(cfg.output,"validation_"+lower(kind)+"_paired.csv"));
        writetable(robustness,fullfile(cfg.output,"validation_"+lower(kind)+"_snr.csv"));
        save(fullfile(cfg.output,"validation_"+lower(kind)+"_statistics.mat"),'summary','pairs','robustness','details','-v7.3');
    end
    eba.manifest('development_classifiers',cfg,struct('scope','train_validation_only','methods',methods, ...
        'classifier_tracks',["SVM","RF"],'tuning_snrs',[Inf 20 5],'tuning_realizations',1,'final_fit_variants_per_family',19, ...
        'hyperparameters',{shared},'hyperparameter_policy',cfg.classifier_hyperparameter_policy), ...
        {classifierFile,fullfile(cfg.output,'shared_hyperparameters_svm.csv'),fullfile(cfg.output,'shared_hyperparameters_rf.csv')});
end
report=struct('stage',stage,'test_accessed',false,'output','results/v2');
fprintf('DEVELOPMENT_STAGE_PASS stage=%s test_accessed=0\n',stage);
end
