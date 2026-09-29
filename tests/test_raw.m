function test_raw()
%TEST_RAW Real one-epoch training, causal-prefix and amplitude controls on CPU.
cfg=eba.config();cfg.families_per_cell=20;cfg.learning_train_families_per_cell=[3 6 9 14]; F=eba.families(20,cfg);
F=F(F.class_id<=9 & F.split~="test" & F.severity_stratum==1 & F.duration_stratum==1,:);
bad=F; bad.split(1)="test"; rejects(@() eba.rawTrain(bad,cfg,'CNN',11),'eba:TestFirewall');
bad=F; bad.class_id(1)=12; rejects(@() eba.rawTrain(bad,cfg,'CNN',11),'eba:RawClasses');
bad=[F;F(1,:)]; rejects(@() eba.rawTrain(bad,cfg,'CNN',11),'eba:FamilyLeakage');
rejects(@() eba.rawArchitecture('unknown',9,500),'eba:RawKind');
seed=77; old=rng; restore=onCleanup(@() rng(old));
for kind=["CNN" "TCN"]
    N=500; if kind=="TCN", N=1000; end
    rng(seed,'twister'); [net,a]=eba.rawArchitecture(kind,9,N);
    rng(seed,'twister'); repeat=eba.rawArchitecture(kind,9,N);
    initialHash=weightsHash(net); assert(strcmp(initialHash,weightsHash(repeat)));
    assert(strcmp(net.Layers(1).Normalization,'none') && a.input_normalization=="none");
    if kind=="CNN"
        assert(a.learnable_parameters==4057 && a.local_receptive_field_samples==171 && a.effective_sample_stride==40);
    else
        assert(a.learnable_parameters==3137 && a.local_receptive_field_samples==5111 && a.effective_sample_stride==10);
        convs=net.Layers(arrayfun(@(x) isa(x,'nnet.cnn.layer.Convolution1DLayer'),net.Layers));
        assert(numel(convs)==15 && all(arrayfun(@(x) strcmp(x.PaddingMode,'causal'),convs)));
        assert(sum(arrayfun(@(x) x.FilterSize==3,convs))==14 && a.causal_feature_stack);
    end
    x=single(sqrt(2)*sin(2*pi*60*(0:N-1)/cfg.Fs));
    amplitude=minibatchpredict(net,{x;2*x},'InputDataFormats','CTB','OutputDataFormats','CTB', ...
        'Outputs','input','ExecutionEnvironment','cpu');
    if isa(amplitude,'dlarray'), amplitude=extractdata(amplitude); end
    assert(max(abs(amplitude(1,:,1)-x))<1e-6 && max(abs(amplitude(1,:,2)-2*x))<1e-6, ...
        'Nominal waveform amplitude was normalized away.');
    prototype=struct('network',net,'sequence_samples',N,'classes',(1:9)','temperature',1);
    [p,c,q,raw]=eba.rawPredict(prototype,{x;2*x});
    [p2,c2,q2,raw2]=eba.rawPredict(prototype,{x;2*x});
    assert(isequal(p,p2) && isequal(c,c2) && isequal(q,q2) && isequal(raw,raw2));
    assert(all(isfinite(raw),'all') && all(isfinite(q),'all') && all(abs(sum(q,2)-1)<1e-12) && all(c>=0 & c<=1));
    singlePrediction=eba.rawPredict(prototype,x(:)); assert(singlePrediction==p(1));
    rejects(@() eba.rawPredict(prototype,NaN(N,1)),'eba:RawInput');
    rejects(@() eba.rawPredict(prototype,ones(N-1,1)),'eba:RawInput');
    if kind=="TCN"
        changed=x; changed(501:end)=changed(501:end)+4;
        causal=minibatchpredict(net,{x;changed},'InputDataFormats','CTB','OutputDataFormats','CTB', ...
            'Outputs','block7_out','ExecutionEnvironment','cpu');
        if isa(causal,'dlarray'), causal=extractdata(causal); end
        prefix=causal(:,1:50,1)-causal(:,1:50,2);
        suffix=causal(:,51:end,1)-causal(:,51:end,2);
        assert(max(abs(prefix),[],'all')<1e-6 && any(abs(suffix)>1e-5,'all'), ...
            'Future perturbation changed causal prefix, or positive sensitivity control failed.');
    end
    cfg.raw_test=struct('max_epochs',1,'sequence_samples',N); before=rng;
    [model,report]=eba.rawTrain(F,cfg,kind,seed); after=rng; assert(isequal(before,after));
    assert(report.epochs_completed==1 && report.iterations_completed>=1 && report.training_time_s>0);
    assert(model.calibrated && report.structural_test_only && report.maximum_epochs==1 && ~report.test_evaluated);
    assert(~strcmp(initialHash,weightsHash(model.network)),'Actual training did not alter learned parameters.');
    assert(isempty(intersect(model.fit_family_ids,model.calibration_family_ids)) && ...
        isempty(intersect(model.fit_family_ids,model.validation_family_ids)) && ...
        isempty(intersect(model.calibration_family_ids,model.validation_family_ids)));
    assert(report.n_fit_families==9*13 && report.n_calibration_families==9 && report.n_validation_families==9*3);
    assert(report.n_fit_records==9*13*3 && report.n_calibration_records==9*3 && report.n_validation_records==9*3*3);
    assert(report.calibration.nll_calibrated<=report.calibration.nll_uncalibrated+1e-8);
    assert(report.model_serialized_bytes>0 && report.architecture.learnable_parameters<10000);
    assert(isfinite(report.startup_RSS_bytes) && report.process_VmHWM_bytes>=report.startup_RSS_bytes);
    [p,c,q,s]=eba.rawPredict(model,{x;2*x});
    assert(all(ismember(p,1:9)) && all(c>=0 & c<=1) && all(isfinite(s),'all') && all(abs(sum(q,2)-1)<1e-12));
    [retrained,repeatedReport]=eba.rawTrain(F,cfg,kind,seed);
    assert(strcmp(weightsHash(model.network),weightsHash(retrained.network)) && ...
        model.temperature==retrained.temperature && isequal(report.validation_raw_scores,repeatedReport.validation_raw_scores), ...
        'Same-seed one-epoch native CPU retraining changed learned weights or calibrated evidence.');
    path=[tempname '.mat'];portableCleanup=onCleanup(@() delete(path));
    eba.saveModel(path,model);portable=load(path,'model');
    [p2,c2,q2,s2]=eba.rawPredict(portable.model,{x;2*x});
    assert(isequal(p,p2) && isequal(c,c2) && isequal(q,q2) && isequal(s,s2),'Portable raw model changed inference.');
    clear portableCleanup
    fprintf('RAW_ONE_EPOCH_RETRAINING_EQUALITY_PASS kind=%s\n',kind);
    fprintf('RAW_ONE_EPOCH_TRAINED kind=%s parameters=%d iterations=%d seconds=%.6g\n',kind,a.learnable_parameters,report.iterations_completed,report.training_time_s);
end
fprintf('RAW_BASELINES_TESTS_PASS\n');
end

function h=weightsHash(net)
parts=strings(height(net.Learnables),1);
for i=1:numel(parts), parts(i)=eba.hash(extractdata(net.Learnables.Value{i}),'numeric'); end
h=eba.hash(strjoin(parts,''));
end

function rejects(f,expected)
ok=false; try, f(); catch err, ok=strcmp(err.identifier,expected); end
assert(ok,'Rejection positive control failed for %s.',expected);
end
