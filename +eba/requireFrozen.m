function freeze = requireFrozen(cfg)
%REQUIREFROZEN Deny final test access unless data/config/code/model freeze is intact.
path=fullfile(cfg.root,'FROZEN_EXPERIMENT.json');
assert(isfile(path),'eba:TestFirewall','Final test is sealed: no frozen experiment.');
freeze=jsondecode(fileread(path));
assert(isfield(freeze,'test_access_authorized') && freeze.test_access_authorized, ...
    'eba:TestFirewall','Test access has not been authorized by a completed development freeze.');
assert(strcmp(freeze.config_sha256,eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file')), ...
    'eba:TestFirewall','Configuration changed after freeze.');
assert(isfield(freeze,'bound_files') && ~isempty(freeze.bound_files),'eba:TestFirewall','No bound files.');
for k=1:numel(freeze.bound_files)
    f=freeze.bound_files(k);bound=fullfile(cfg.root,f.path);
    assert(isfile(bound) && strcmp(f.sha256,eba.hash(bound,'file')),'eba:TestFirewall','Frozen artifact changed: %s',f.path);
end
end
