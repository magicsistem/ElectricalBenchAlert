function test_firewall()
%TEST_FIREWALL Isolated positive freeze and type/path/config/SHA mutation controls.
original=eba.config();F=eba.families(original.families_per_cell,original);
folder=tempname;mkdir(folder);cleanup=onCleanup(@() rmdir(folder,'s'));mkdir(fullfile(folder,'config'));
copyfile(fullfile(original.root,'config','research_v2.json'),fullfile(folder,'config','research_v2.json'));
cfg=original;cfg.root=folder;eba.requireFrozen(cfg,'reset');
paths={'source.json','dataset.json','split.json','model.json','config/research_v2.json'};
roles={'source','dataset','split','model','config'};bound=struct('path',{},'sha256',{},'role',{});
for k=1:4,eba.json(fullfile(folder,paths{k}),struct('fixture',1));end
for k=1:5,bound(k)=struct('path',paths{k},'sha256',eba.hash(fullfile(folder,paths{k}),'file'),'role',roles{k});end
software=ver;requiredNames=["Signal Processing Toolbox","Wavelet Toolbox","Statistics and Machine Learning Toolbox","Deep Learning Toolbox"];
toolboxes=software(ismember(string({software.Name}),requiredNames));assert(numel(toolboxes)==4);
freeze=struct('schema_version','1.0.0','experiment_id','isolated_test_control','source_commit',repmat('a',1,40), ...
    'test_access_authorized',true,'MATLAB_version',version,'required_toolbox_versions',toolboxes,'config_sha256',bound(5).sha256,'dataset_sha256',eba.hash(jsonencode(table2struct(F))), ...
    'split_sha256',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'})))),'bound_files',bound);
path=fullfile(folder,'FROZEN_EXPERIMENT.json');eba.json(path,freeze);eba.requireFrozen(cfg);
bad=freeze;bad.MATLAB_version='different_build';eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.required_toolbox_versions(1).Version='different_version';eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.required_toolbox_versions=bad.required_toolbox_versions(2:end);eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
for value={false,1,[true true]}
    bad=freeze;bad.test_access_authorized=value{1};eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
end
bad=freeze;bad.dataset_sha256=repmat('0',1,64);eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.split_sha256=repmat('0',1,64);eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.bound_files(1).path='../outside.json';eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.bound_files(1).path='/tmp/outside.json';eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.bound_files(1).path='a/./source.json';eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.bound_files(1).sha256='invalid';eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.bound_files(2).path=bad.bound_files(1).path;eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
bad=freeze;bad.bound_files(4).role='source';eba.json(path,bad);fails(@() eba.requireFrozen(cfg));
eba.json(path,freeze);changed=cfg;changed.Fs=9000;fails(@() eba.requireFrozen(changed));
unbound=cfg;unbound.stream_gap_s=.01;fails(@() eba.requireFrozen(unbound));
% Same length and restored timestamp still fail the full SHA check.
modelPath=fullfile(folder,'model.json');file=java.io.File(modelPath);stamp=file.lastModified();before=dir(modelPath);
eba.json(modelPath,struct('fixture',2));after=dir(modelPath);assert(before.bytes==after.bytes);assert(file.setLastModified(stamp));
fails(@() eba.requireFrozen(cfg));eba.json(modelPath,struct('fixture',1));eba.requireFrozen(cfg);
% Explicit experiment sessions bind configuration/freeze and recheck every artifact at exit.
eba.requireFrozen(cfg,'begin');eba.requireFrozen(cfg);fails(@() eba.requireFrozen(changed));
eba.json(modelPath,struct('fixture',2));fails(@() eba.requireFrozen(cfg,'end'));eba.requireFrozen(cfg,'reset');
eba.json(modelPath,struct('fixture',1));eba.requireFrozen(cfg,'begin');eba.requireFrozen(cfg,'end');
fails(@() eba.requireFrozen(cfg,'end'));eba.requireFrozen(cfg,'reset');
options=struct('gap_s',2,'context_s',2,'normal_duration_s',30);
freeze.stream_protocol=struct('schedule_options',options);eba.json(path,freeze);eba.requireFrozen(cfg,'begin');
family=F(find(F.split=="test" & F.class_id==2,1),:);
sequence=eba.continuousSchedule(family,cfg,Inf,'frozen_timing_control',7,'final',1,options);
assert(sequence.split=="test" && sequence.normal_context_s==2 && sequence.normal_gap_s==2);
eba.requireFrozen(cfg,'verify',family);
changedFamily=family;parameters=jsondecode(family.parameters_json);parameters.base_rms_pu=parameters.base_rms_pu+.001;
changedFamily.parameters_json=string(jsonencode(parameters));
fails(@() eba.requireFrozen(cfg,'verify',changedFamily));
fails(@() eba.record(changedFamily,Inf,1,cfg,'final'));
fails(@() eba.extract(changedFamily,'FFT',struct(),cfg,'final'));
fails(@() eba.continuousSchedule(changedFamily,cfg,Inf,'changed_family',7,'final',1,options));
changedOptions=options;changedOptions.gap_s=.01;
fails(@() eba.continuousSchedule(family,cfg,Inf,'bad_timing',7,'final',1,changedOptions));
eba.requireFrozen(cfg,'end');
fprintf('TEST_FIREWALL_TYPED_AND_MUTATION_CONTROLS_PASS\n');
end
function fails(f)
ok=false;try,f();catch err,ok=strcmp(err.identifier,'eba:TestFirewall');end
assert(ok,'Expected test-firewall rejection was not observed.');
end
