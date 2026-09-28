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
if isfield(extra,'dataset_hash'),m.dataset_hash=extra.dataset_hash;end
if isfield(extra,'split_hash'),m.split_hash=extra.split_hash;end
items=struct('path',{},'sha256',{});
for k=1:numel(artifacts)
    path=char(artifacts(k));assert(isfile(path),'eba:ManifestArtifact','Missing artifact.');
    assert(startsWith(path,[cfg.root filesep]),'eba:ManifestPath','Artifacts must use repository outputs.');
    items(k).path=erase(path,[cfg.root filesep]);items(k).sha256=eba.hash(path,'file');
end
m.artifacts=items;
eba.json(fullfile(cfg.output,'manifests',string(id)+'.json'),m);
end
