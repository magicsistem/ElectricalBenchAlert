function test_pipeline()
%TEST_PIPELINE Dataset -> fixed feature schema -> controlled training -> calibration and freeze controls.
cfg=eba.config();F=eba.families(20,cfg);F=F(F.split~="test",:);
chosen=F([],:);cal=strings(0,1);
for c=1:9
    train=F(F.class_id==c & F.split=="train",:);val=F(F.class_id==c & F.split=="validation",:);
    chosen=[chosen;train(1:3,:);val(1,:)];cal(end+1)=train.family_id(3); %#ok<AGROW>
end
params=struct('nominal_frequency_hz',60);
[X,P,info]=eba.extract(chosen,'FFT',params,cfg,'development',[Inf 20],1:2);
[again,againP,againInfo]=eba.extract(chosen,'FFT',params,cfg,'development',[Inf 20],1:2);
assert(isequal(X,again) && isequal(P,againP) && isequal(info,againInfo));
assert(size(X,2)==24 && size(X,1)==height(chosen)*3 && numel(unique(P.family_id))==height(chosen));
assert(all(abs(P.measured_snr_db(isfinite(P.SNR_db))-P.SNR_db(isfinite(P.SNR_db)))<1e-10));
cfg.svm_grid.box_constraint=1;cfg.svm_grid.kernel_scale=1;
[model,search]=eba.selectClassifier(X,P,cfg,'SVM',cal);
assert(model.calibrated && height(search)==2 && model.calibration.n_families==9);
val=P.split=="validation";[pred,confidence,prob]=eba.predict(model,X(val,:));
assert(all(pred>=1 & pred<=9) && all(confidence>=0 & confidence<=1) && all(abs(sum(prob,2)-1)<1e-12));
reliability=eba.calibrationMetrics(model,X(val,:),P.class_id(val));assert(isfinite(reliability.brier) && reliability.ece_10_bins>=0);
original=eba.config();testRows=eba.families(20,original);testRows=testRows(testRows.split=="test",:);
rejects(@() eba.extract(testRows(1,:),'FFT',params,original,'development',Inf,1),'eba:TestFirewall');
rejects(@() eba.selectClassifier(X,assignTest(P),cfg,'SVM',cal),'eba:TestFirewall');
rejects(@() eba.requireFrozen(original),'eba:TestFirewall');
% Local positive-control freeze, isolated from the real experiment.
folder=tempname;mkdir(folder);cleanup=onCleanup(@() rmdir(folder,'s'));mkdir(fullfile(folder,'config'));
copyfile(fullfile(original.root,'config','research_v2.json'),fullfile(folder,'config','research_v2.json'));
eba.json(fullfile(folder,'bound.json'),struct('value',1));testCfg=original;testCfg.root=folder;
freeze=struct('test_access_authorized',false,'config_sha256',eba.hash(fullfile(folder,'config','research_v2.json'),'file'), ...
    'bound_files',struct('path','bound.json','sha256',eba.hash(fullfile(folder,'bound.json'),'file')));
eba.json(fullfile(folder,'FROZEN_EXPERIMENT.json'),freeze);rejects(@() eba.requireFrozen(testCfg),'eba:TestFirewall');
freeze.test_access_authorized=true;eba.json(fullfile(folder,'FROZEN_EXPERIMENT.json'),freeze);eba.requireFrozen(testCfg);
eba.json(fullfile(folder,'bound.json'),struct('value',2));rejects(@() eba.requireFrozen(testCfg),'eba:TestFirewall');
fprintf('PIPELINE_INTEGRATION_TESTS_PASS families=%d records=%d features=%d\n',height(chosen),height(P),size(X,2));
end
function P=assignTest(P)
P.split(1)="test";
end
function rejects(f,id)
ok=false;try,f();catch err,ok=strcmp(err.identifier,id);end
assert(ok,'Expected rejection %s was not observed.',id);
end
