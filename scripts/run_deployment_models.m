function summary=run_deployment_models()
%RUN_DEPLOYMENT_MODELS Native compact inference copies; paired full-validation equality proof.
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);F=F(F.split~="test" & F.class_id<=cfg.primary_class_count,:);
D=load(fullfile(cfg.output,'development_classifiers.mat'),'models');
trainingManifest=fullfile(cfg.output,'manifests','development_classifiers.json');
provenance=jsondecode(fileread(trainingManifest));assert(provenance.repository_state_clean,'eba:ModelSource','Training manifest must identify clean source.');
folder=fullfile(cfg.output,'deployment_models');if ~isfolder(folder),mkdir(folder);end
rows=cell(5,2);artifacts=strings(0,1);
for m=1:5
    for k=1:2
        original=D.models{m,k};[X,P]=eba.extract(F,original.method,original.parameters,cfg,'development');X=X(P.split=="validation",:);
        [before,c1,p1,s1]=eba.predict(original,X);
        model=original;model.fitted=compact(original.fitted);
        [after,c2,p2,s2]=eba.predict(model,X);
        assert(isequal(before,after) && isequal(c1,c2) && isequal(p1,p2) && isequal(s1,s2), ...
            'eba:CompactionPrediction','Native compaction changed a held-out prediction or calibrated/raw score.');
        model.training_git_commit=provenance.git_commit;
        model.training_manifest_sha256=eba.hash(trainingManifest,'file');
        name="model_"+lower(model.method)+"_"+lower(model.kind)+".mat";
        path=fullfile(folder,name);save(path,'model','-v7.3');
        source=dir(fullfile(cfg.output,name));destination=dir(path);
        rows{m,k}=table(model.method,model.kind,source.bytes,destination.bytes,size(X,1), ...
            max(abs(s1-s2),[],'all'),'VariableNames',{'method','classifier','training_object_bytes', ...
            'compact_model_bytes','n_compared_validation_rows','max_raw_score_difference'});
        artifacts(end+1)=path; %#ok<AGROW>
        fprintf('COMPACT_PREDICTION_EQUALITY_PASS method=%s classifier=%s rows=%d bytes=%d\n',model.method,model.kind,size(X,1),destination.bytes);
    end
end
summary=vertcat(rows{:});path=fullfile(cfg.output,'deployment_model_compaction.csv');writetable(summary,path);artifacts(end+1)=path;
eba.manifest('deployment_model_compaction',cfg,struct('scope','storage-only native compaction; exact full validation equality; no refitting', ...
    'dataset_hash',eba.hash(jsonencode(table2struct(F))),'split_hash',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'})))), ...
    'methods',["FFT","STFT","DWT","CWT","ST"],'classifiers',["SVM","RF"], ...
    'training_manifest_sha256',eba.hash(trainingManifest,'file')),artifacts);
fprintf('DEPLOYMENT_COMPACTION_COMPLETE models=10 test_accessed=0\n');
end
