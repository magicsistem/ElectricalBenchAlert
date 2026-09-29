function freeze=requireFrozen(cfg,action,families)
%REQUIREFROZEN Typed test firewall; full SHA verification at final experiment entry and exit.
% An explicit begin/end session reuses immutable in-memory inputs between those checks.
% It cannot attest to transient external edits that restore bytes before the exit check.
if nargin<2,action="verify";end
action=string(action);assert(isscalar(action) && any(action==["verify","begin","end","reset"]),'eba:TestFirewall','Unknown freeze action.');
persistent session
if action=="reset",session=[];freeze=[];return;end
path=fullfile(cfg.root,'FROZEN_EXPERIMENT.json');
assert(isfile(path),'eba:TestFirewall','Final test is sealed: no frozen experiment.');
freezeHash=eba.hash(path,'file');
if action=="verify" && ~isempty(session)
    assert(isequaln(cfg,session.config) && strcmp(freezeHash,session.freeze_sha256), ...
        'eba:TestFirewall','Configuration or freeze changed inside the final experiment.');
    if nargin>=3,verifyFamilySubset(families,session.families);end
    freeze=session.freeze;return;
end
freeze=jsondecode(fileread(path));required={'schema_version','experiment_id','source_commit','test_access_authorized', ...
    'config_sha256','dataset_sha256','split_sha256','bound_files','MATLAB_version','required_toolbox_versions'};
assert(isstruct(freeze) && isscalar(freeze) && all(isfield(freeze,required)), ...
    'eba:TestFirewall','The completed freeze schema is required.');
assert(islogical(freeze.test_access_authorized) && isscalar(freeze.test_access_authorized) && freeze.test_access_authorized, ...
    'eba:TestFirewall','Test access needs an explicit logical authorization from completed development.');
assert(ischar(freeze.schema_version) && strcmp(freeze.schema_version,'1.0.0') && ...
    ischar(freeze.experiment_id) && ~isempty(strtrim(freeze.experiment_id)) && ...
    ischar(freeze.source_commit) && ~isempty(regexp(freeze.source_commit,'^[0-9a-f]{40}$','once')), ...
    'eba:TestFirewall','Invalid freeze version, experiment identity or source commit.');
assert(ischar(freeze.MATLAB_version) && strcmp(freeze.MATLAB_version,version), ...
    'eba:TestFirewall','Frozen MATLAB build differs from the current numerical software.');
requiredNames=["Signal Processing Toolbox","Wavelet Toolbox","Statistics and Machine Learning Toolbox","Deep Learning Toolbox"];
software=freeze.required_toolbox_versions;actual=ver;
assert(isstruct(software) && numel(software)==numel(requiredNames) && all(isfield(software,{'Name','Version','Release'})) && ...
    isequal(sort(string({software.Name})),sort(requiredNames)), ...
    'eba:TestFirewall','All four declared numerical toolboxes must be bound.');
for t=1:numel(software)
    index=find(string({actual.Name})==string(software(t).Name));
    assert(isscalar(index) && strcmp(software(t).Version,actual(index).Version) && strcmp(software(t).Release,actual(index).Release), ...
        'eba:TestFirewall','A required numerical toolbox version differs from the freeze.');
end
for name=["config_sha256","dataset_sha256","split_sha256"]
    assert(validHash(freeze.(name)),'eba:TestFirewall','Invalid frozen SHA-256.');
end
configPath=fullfile(cfg.root,'config','research_v2.json');
assert(strcmp(freeze.config_sha256,eba.hash(configPath,'file')),'eba:TestFirewall','Configuration changed after freeze.');
expected=jsondecode(fileread(configPath));expected.classes=string(expected.classes(:));
assert(isequal(sort(string(fieldnames(cfg))),sort([string(fieldnames(expected));"root";"output"])), ...
    'eba:TestFirewall','Unbound in-memory configuration fields are forbidden during final data access.');
for name=string(fieldnames(expected)).'
    assert(isfield(cfg,name) && isequaln(cfg.(name),expected.(name)), ...
        'eba:TestFirewall','In-memory scientific configuration differs from the frozen file: %s',name);
end
files=freeze.bound_files;
assert(isstruct(files) && ~isempty(files) && all(isfield(files,{'path','sha256','role'})), ...
    'eba:TestFirewall','Frozen source, config, dataset, split and model artifacts are required.');
paths=strings(numel(files),1);roles=paths;canonicalRoot=char(java.io.File(cfg.root).getCanonicalPath());
for k=1:numel(files)
    f=files(k);assert(ischar(f.path) && ~isempty(f.path) && ~startsWith(f.path,'/') && ...
        ~contains(f.path,'\') && ~any(ismember(split(string(f.path),'/'),["..",".",""])) && ...
        validHash(f.sha256) && ischar(f.role) && any(string(f.role)==["source","config","dataset","split","model","evidence"]), ...
        'eba:TestFirewall','Frozen artifacts require canonical relative paths, roles and SHA-256.');
    paths(k)=string(f.path);roles(k)=string(f.role);bound=fullfile(cfg.root,f.path);
    resolved=char(java.io.File(bound).getCanonicalPath());
    assert(startsWith(resolved,[canonicalRoot filesep]) && isfile(bound) && strcmp(f.sha256,eba.hash(bound,'file')), ...
        'eba:TestFirewall','Frozen artifact is missing, changed or outside the repository: %s',f.path);
end
assert(numel(unique(paths))==numel(paths) && all(ismember(["source","config","dataset","split","model"],roles)), ...
    'eba:TestFirewall','Duplicate artifact or missing scientific binding role.');
F=eba.families(cfg.families_per_cell,cfg);
assert(strcmp(freeze.dataset_sha256,eba.hash(jsonencode(table2struct(F)))) && ...
    strcmp(freeze.split_sha256,eba.hash(jsonencode(table2struct(F(:,{'family_id','split'}))))), ...
    'eba:TestFirewall','Regenerated parameter families or splits differ from the freeze.');
if nargin>=3,verifyFamilySubset(families,F);end
if action=="begin"
    assert(isempty(session),'eba:TestFirewall','A final experiment session is already active.');
    session=struct('config',cfg,'freeze_sha256',freezeHash,'freeze',freeze,'families',F);
elseif action=="end"
    assert(~isempty(session) && isequaln(cfg,session.config) && strcmp(freezeHash,session.freeze_sha256), ...
        'eba:TestFirewall','Final experiment session changed.');session=[];
end
end
function yes=validHash(value)
yes=ischar(value) && ~isempty(regexp(value,'^[0-9a-f]{64}$','once'));
end

function verifyFamilySubset(requested,canonical)
assert(istable(requested) && height(requested)>0 && ...
    isequal(requested.Properties.VariableNames,canonical.Properties.VariableNames), ...
    'eba:TestFirewall','Final family input must use the complete frozen metadata schema.');
[present,index]=ismember(requested.family_id,canonical.family_id);
assert(all(present) && numel(unique(requested.family_id))==height(requested) && ...
    isequaln(requested,canonical(index,:)), ...
    'eba:TestFirewall','Final family parameters, labels, support or split differ from the frozen population.');
end
