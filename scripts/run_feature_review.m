function summary=run_feature_review()
%RUN_FEATURE_REVIEW Explicit train-only diagnostics; no feature selection or final-test access.
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);
F=F(F.split~="test" & F.class_id<=cfg.primary_class_count,:);
S=load(fullfile(cfg.output,'development_transform_selection.mat'),'selected','methods','config_hash');
assert(strcmp(S.config_hash,eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file')), ...
    'eba:DevelopmentMutation','Configuration differs from the representation-selection experiment.');
artifacts=strings(0,1);rows=cell(numel(S.methods),1);
for m=1:numel(S.methods)
    method=S.methods(m);path=fullfile(cfg.output,"model_"+lower(method)+"_svm.mat");trained=load(path,'model');
    [X,P,info]=eba.extract(F,method,S.selected{m},cfg,'development');
    fitting=ismember(P.family_id,trained.model.training_family_ids);
    assert(all(P.split(fitting)=="train") && all(isfinite(X(fitting,:)),'all'), ...
        'eba:FeatureReviewSplit','Diagnostics must use the stored model fitting families only.');
    assert(max(abs(mean(X(fitting,:),1)-trained.model.mean))<1e-12, ...
        'eba:FeatureReviewSource','Stored model standardization does not match its fitting rows.');
    [review,redundancy]=eba.featureReview(X(fitting,:),P(fitting,:),info.feature_names,cfg);
    review.training_matrix_sha256=eba.hash(X(fitting,:),'numeric');review.feature_cache_signature=info.signature;
    review.source_model_sha256=eba.hash(path,'file');
    jsonPath=fullfile(cfg.output,"feature_review_"+lower(method)+".json");
    csvPath=fullfile(cfg.output,"feature_redundancy_"+lower(method)+".csv");
    eba.json(jsonPath,review);writetable(redundancy,csvPath);
    artifacts=[artifacts;jsonPath;csvPath]; %#ok<AGROW>
    rows{m}=table(method,review.n_independent_families,review.n_derived_records, ...
        sum(review.constant_features),height(redundancy), ...
        'VariableNames',{'method','n_families','n_records','n_constant_features','n_redundant_pairs'});
end
summary=vertcat(rows{:});path=fullfile(cfg.output,'feature_review_summary.csv');writetable(summary,path);
artifacts(end+1)=path;
eba.manifest('development_feature_review',cfg,struct('scope','fitting families only; descriptive diagnostics without feature selection', ...
    'dataset_hash',info.family_hash,'split_hash',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'}))))),artifacts);
fprintf('FEATURE_REVIEW_COMPLETE methods=%d test_accessed=0\n',numel(S.methods));
end
