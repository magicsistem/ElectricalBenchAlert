function test_runtime()
%TEST_RUNTIME Actual measured stage timings, hop budget and train-only feature diagnostics.
cfg=eba.config();cfg.runtime_warmups=1;cfg.runtime_repetitions=8;
signals=cell(9,1);X=zeros(9,24);params=struct('nominal_frequency_hz',60);
for c=1:9
    signals{c}=sqrt(2)*(1+c/10)*sin(2*pi*(60+2*c)*(0:9999)'/cfg.Fs);
    X(c,:)=eba.features(signals{c},cfg.Fs,'FFT',params);
end
model=eba.fit([X;X+.001],repmat((1:9)',2,1),cfg,'SVM',struct('kernel','linear','box_constraint',1,'kernel_scale',1));
model.method="FFT";model.parameters=params;
[r,t]=eba.runtime(model,signals,cfg.Fs,.0125,cfg);
assert(abs(r.throughput_windows_per_s-height(t)/sum(t.total_s))<1e-12 && ...
    abs(r.throughput_input_samples_per_s-.0125*cfg.Fs*r.throughput_windows_per_s)<1e-9);
assert(height(t)==8 && all(t.feature_s>0 & t.classification_s>0 & t.total_s>0));
assert(abs(r.total_p95_s-quantile(t.total_s,.95))<1e-12 && abs(r.streaming_real_time_factor-r.total_p95_s/.0125)<1e-12);
assert(abs(r.streaming_real_time_factor/r.window_real_time_factor-80)<1e-10 && r.representation_bytes_median>0);
assert(isfinite(r.peak_process_RSS_bytes) && r.peak_process_RSS_bytes>=r.startup_and_model_RSS_bytes);
P=table(repelem(["f1";"f2"],3,1),repmat([Inf;20;5],2,1),repmat([0;1;1],2,1),repmat("train",6,1), ...
    'VariableNames',{'family_id','SNR_db','realization_id','split'});
A=repmat((1:6)',1,24);A(:,2)=A(:,1);A(:,3)=2;names="feature"+(1:24);
[review,pairs]=eba.featureReview(A,P,names,cfg);
assert(review.n_independent_families==2 && review.n_derived_records==6 && review.constant_features(3));
assert(any(pairs.feature_a=="feature1" & pairs.feature_b=="feature2") && all(review.paired_family_mean_absolute_change(:,3)==0));
assert(all(review.paired_family_mean_absolute_change(:,1)>0));
bad=P;bad.split(1)="test";rejects(@() eba.featureReview(A,bad,names,cfg),'eba:FeatureReviewSplit');
bad=P;bad.SNR_db(1)=20;rejects(@() eba.featureReview(A,bad,names,cfg),'eba:FeatureReviewPair');
rejects(@() eba.featureReview(A(:,1:23),P,names,cfg),'eba:FeatureReviewSchema');
fprintf('RUNTIME_SCIENTIFIC_TESTS_PASS repetitions=%d peak_process_RSS_bytes=%.0f\n',height(t),r.peak_process_RSS_bytes);
end
function rejects(f,id)
ok=false;try,f();catch err,ok=strcmp(err.identifier,id);end
assert(ok,'Expected rejection %s was not observed.',id);
end
