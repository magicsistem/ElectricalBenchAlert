function m = manifest(id,cfg,extra,artifacts)
%MANIFEST Capture actual source, environment, seeds, configuration and artifact digests.
if nargin<3,extra=struct();end;if nargin<4,artifacts=strings(0,1);end
artifacts=string(artifacts(:));
[status,commit]=system('git rev-parse HEAD');assert(status==0,'eba:GitProvenance','Scientific runs require a Git commit.');
[~,dirty]=system('git status --porcelain --untracked-files=normal');
[~,os]=system('uname -sr');[~,cpu]=system('lscpu');[~,ram]=system('free -b');
m=struct('experiment_id',string(id),'timestamp_utc',string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ssXXX")), ...
    'git_commit',strtrim(string(commit)),'repository_state_clean',strlength(strtrim(string(dirty)))==0, ...
    'MATLAB_version',version,'toolbox_versions',ver,'OS',strtrim(string(os)),'CPU',strtrim(string(cpu)), ...
    'RAM',strtrim(string(ram)),'dataset_version',cfg.dataset_version,'seed',cfg.master_seed, ...
    'split_seed',cfg.split_seed,'model_seed',cfg.model_seed,'stream_seed',cfg.stream_seed, ...
    'feature_schema_version',cfg.feature_schema_version, ...
    'config_hash',eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file'),'extra',extra);
% Dataset identity always denotes the complete declared population; actual inputs are separate.
F=eba.families(cfg.families_per_cell,cfg);
m.dataset_hash=eba.hash(jsonencode(table2struct(F)));
m.split_hash=eba.hash(jsonencode(table2struct(F(:,{'family_id','split'}))));
if isfield(extra,'dataset_hash'),m.input_family_subset_sha256=extra.dataset_hash;end
if isfield(extra,'split_hash'),m.input_subset_split_sha256=extra.split_hash;end
m.method=string(id);if isfield(extra,'method'),m.method=extra.method;elseif isfield(extra,'methods'),m.method=extra.methods;end
m.parameters=jsondecode(fileread(fullfile(cfg.root,'config','research_v2.json')));
if isfield(extra,'parameters'),m.parameters=extra.parameters;end
m.classifier="not_applicable";
if isfield(extra,'classifier'),m.classifier=extra.classifier;elseif isfield(extra,'classifier_tracks'),m.classifier=extra.classifier_tracks;end
m.hyperparameters=struct();if isfield(extra,'hyperparameters'),m.hyperparameters=extra.hyperparameters;end
if isfield(extra,'solver_configuration'),m.solver_configuration=extra.solver_configuration;end
m.hash_scope='dataset_hash: full canonical parameter families; split_hash: full family_id/split mapping; input subsets recorded separately';
items=struct('path',{},'sha256',{});
for k=1:numel(artifacts)
    path=char(artifacts(k));assert(isfile(path),'eba:ManifestArtifact','Missing artifact.');
    assert(startsWith(path,[cfg.root filesep]),'eba:ManifestPath','Artifacts must use repository outputs.');
    items(k).path=erase(path,[cfg.root filesep]);items(k).sha256=eba.hash(path,'file');
end
m.artifacts=items;
latest=fullfile(cfg.output,'manifests',string(id)+'.json');
eba.json(latest,m);
end
