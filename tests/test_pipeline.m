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
% Cached numeric/label corruption must fail before any training uses it.
cachePath=fullfile(cfg.output,'feature_cache',info.signature+".mat");backup=[tempname '.mat'];copyfile(cachePath,backup);
cacheCleanup=onCleanup(@() restoreCache(backup,cachePath));cached=load(cachePath,'X','P','info');
corrupt=cached;corrupt.X(1,1)=corrupt.X(1,1)+.001;save(cachePath,'-struct','corrupt','-v7');
rejects(@() eba.extract(chosen,'FFT',params,cfg,'development',[Inf 20],1:2),'eba:FeatureCacheMutation');
corrupt=cached;corrupt.P.class_id(1)=2;save(cachePath,'-struct','corrupt','-v7');
rejects(@() eba.extract(chosen,'FFT',params,cfg,'development',[Inf 20],1:2),'eba:FeatureCacheMutation');
corrupt=cached;corrupt.P.SNR_db(1)=NaN;
assert(strcmp(jsonencode(table2struct(corrupt.P)),jsonencode(table2struct(cached.P))), ...
    'Positive control must expose the JSON Inf/NaN collision.');
save(cachePath,'-struct','corrupt','-v7');
rejects(@() eba.extract(chosen,'FFT',params,cfg,'development',[Inf 20],1:2),'eba:FeatureCacheMutation');
corrupt=cached;corrupt.X=reshape(corrupt.X,24,[]);
assert(strcmp(eba.hash(corrupt.X,'numeric'),eba.hash(cached.X,'numeric')));
save(cachePath,'-struct','corrupt','-v7');
rejects(@() eba.extract(chosen,'FFT',params,cfg,'development',[Inf 20],1:2),'eba:FeatureCacheMutation');
clear cacheCleanup;
rejects(@() eba.extract(chosen,'FFT',params,cfg,'development',[NaN 20],1:2),'eba:ExtractSNR');
rejects(@() eba.extract(chosen,'FFT',params,cfg,'development',[Inf Inf 20],1:2),'eba:ExtractSNR');
rejects(@() eba.extract(chosen,'FFT',params,cfg,'development',[Inf 20],[1 1]),'eba:ExtractRealization');
rejects(@() eba.extract(chosen,'FFT',params,cfg,'structural',[Inf 20],1:2),'eba:ExtractMode');
changedCfg=cfg;changedCfg.Fs=9000;
rejects(@() eba.extract(chosen,'FFT',params,changedCfg,'development',[Inf 20],1:2),'eba:Sampling');
assert(size(X,2)==24 && size(X,1)==height(chosen)*3 && numel(unique(P.family_id))==height(chosen));
assert(all(abs(P.measured_snr_db(isfinite(P.SNR_db))-P.SNR_db(isfinite(P.SNR_db)))<1e-10));
cfg.svm_grid.box_constraint=1;cfg.svm_grid.kernel_scale=1;
[model,search]=eba.selectClassifier(X,P,cfg,'SVM',cal);
assert(model.calibrated && height(search)==2 && model.calibration.n_families==9);
val=P.split=="validation";[pred,confidence,prob]=eba.predict(model,X(val,:));
assert(all(pred>=1 & pred<=9) && all(confidence>=0 & confidence<=1) && all(abs(sum(prob,2)-1)<1e-12));
eba.requireCandidateCoverage(["FFT","DWT"],["DWT","FFT"],'positive control');
rejects(@() eba.requireCandidateCoverage(["FFT","DWT"],"DWT",'missing candidate control'),'eba:CandidateCoverage');
candidateFixture=table([.50;.65;.40;.99],[.45;.40;.35;.98],[1;2;3;0],[.1;.2;.3;.1],[.1;.2;.3;1.1], ...
    [1;100;2;1],[true;true;true;false],'VariableNames',{'event_f1','event_f1_ci_low','false_alarms_per_minute', ...
    'matched_latency_s','stream_RTF_p95','model_bytes','eligible'});
[winner,front]=eba.selectStreamCandidate(candidateFixture);assert(winner==1&&front(1)&&front(2)&&~front(3)&&~front(4));
reliability=eba.calibrationMetrics(model,X(val,:),P.class_id(val));assert(isfinite(reliability.brier) && reliability.ece_10_bins>=0);
original=eba.config();testRows=eba.families(20,original);testRows=testRows(testRows.split=="test",:);
rejects(@() eba.extract(testRows(1,:),'FFT',params,original,'development',Inf,1),'eba:TestFirewall');
rejects(@() eba.selectClassifier(X,assignTest(P),cfg,'SVM',cal),'eba:TestFirewall');
tamperedFreezeCfg=original;tamperedFreezeCfg.Fs=original.Fs+1;
rejects(@() eba.requireFrozen(tamperedFreezeCfg),'eba:TestFirewall');
% Row/column method lists agree; worsening curves cannot masquerade as stability.
learning=table(repelem(["FFT";"STFT"],3),repmat([3;6;9],2,1), ...
    [.5;.505;.509;.8;.6;.4],[.48;.485;.489;.78;.58;.38],[.52;.525;.529;.82;.62;.42], ...
    'VariableNames',{'method','train_per_cell','macro_f1','ci_low','ci_high'});
accept=eba.learningAcceptance(learning,["FFT","STFT"],original);
assert(isequal(accept,eba.learningAcceptance(learning,["FFT";"STFT"],original)) && accept.accepted(1) && ~accept.accepted(2));
wide=learning;wide.ci_low(3)=.4;wide.ci_high(3)=.7;reject=eba.learningAcceptance(wide,["FFT","STFT"],original);assert(~reject.accepted(1));
invalid=learning;invalid.train_per_cell(2)=3;rejects(@() eba.learningAcceptance(invalid,["FFT","STFT"],original),'eba:LearningCurve');
% Typed/hash mutation positive controls run separately in test_firewall.
fprintf('PIPELINE_INTEGRATION_TESTS_PASS families=%d records=%d features=%d\n',height(chosen),height(P),size(X,2));
end
function P=assignTest(P)
P.split(1)="test";
end
function rejects(f,id)
ok=false;try,f();catch err,ok=strcmp(err.identifier,id);end
assert(ok,'Expected rejection %s was not observed.',id);
end

function restoreCache(backup,path)
if isfile(backup),[ok,msg]=movefile(backup,path,'f');assert(ok,'eba:CacheRestore','%s',msg);end
end
