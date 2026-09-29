function run_manifest_correction()
%RUN_MANIFEST_CORRECTION Metadata-only repair; preserve original computation provenance and bytes.
cfg=eba.config();S=load(fullfile(cfg.output,'development_transform_selection.mat'),'selected','methods','selection');
D=load(fullfile(cfg.output,'development_classifiers.mat'),'shared');
ids=["development_transform_selection","development_classifiers","development_learning"];
if isfile(fullfile(cfg.output,'manifests','deployment_model_compaction.json')),ids(end+1)="deployment_model_compaction";end
for id=ids
    path=fullfile(cfg.output,'manifests',id+".json");old=jsondecode(fileread(path));extra=old.extra;
    assert(old.repository_state_clean,'eba:ManifestCorrection','Original computation must identify clean source.');
    extra.manifest_operation='metadata-only correction; results/model artifacts are not changed';
    if ~isfield(extra,'original_computation_git_commit')
        extra.original_computation_git_commit=old.git_commit;extra.original_computation_timestamp_utc=old.timestamp_utc;
        extra.original_manifest_sha256=eba.hash(path,'file');
    end
    extra.previous_manifest_sha256=eba.hash(path,'file');
    extra.methods=S.methods;extra.parameters=cell2struct(S.selected,cellstr(lower(S.methods)),1);
    if id=="development_transform_selection"
        extra.classifier='SVM';extra.hyperparameters=struct('kernel','linear','box_constraint',1,'kernel_scale',1);
        extra.parameter_grid=table2struct(S.selection(:,{'method','candidate_id','parameters_json'}));
    elseif any(id==["development_classifiers","deployment_model_compaction"])
        extra.classifier_tracks=["SVM","RF"];extra.hyperparameters=D.shared;
    else
        extra.classifier='SVM';extra.hyperparameters=D.shared{1};
    end
    artifacts=string({old.artifacts.path})';before=string({old.artifacts.sha256})';
    artifacts=fullfile(cfg.root,artifacts);actual=string(arrayfun(@(p) eba.hash(p,'file'),artifacts,'UniformOutput',false));
    assert(isequal(actual,before),'eba:ManifestCorrection','Original result artifacts changed before metadata repair.');
    eba.manifest(id,cfg,extra,artifacts);
    corrected=jsondecode(fileread(path));assert(isequal(string({corrected.artifacts.sha256})',before), ...
        'eba:ManifestCorrection','Metadata correction changed result artifact digests.');
    fprintf('MANIFEST_METADATA_CORRECTION_PASS stage=%s computation_commit=%s artifact_bytes_unchanged=1\n',id,extra.original_computation_git_commit);
end
end
