function test_streaming()
%TEST_STREAMING Physical continuity, sample causality, persistence and event matching.
cfg=eba.config();F=eba.families(20,cfg);picked=F([],:);
for c=2:12,row=find(F.class_id==c & F.split=="validation",1);picked=[picked;F(row,:)];end %#ok<AGROW>
s=eba.continuousSchedule(picked,cfg,Inf,'control',cfg.stream_seed);
repeat=eba.continuousSchedule(picked,cfg,Inf,'control',cfg.stream_seed);
assert(isequal(s,repeat) && s.n_samples>10000 && abs(s.normal_exposure_s-2*(height(picked)+1)-s.initial_onset_jitter_s)<1e-12);
idx=(0:s.n_samples-1)';[x,truth]=eba.continuousSignal(s,idx,cfg);
chunks=[eba.continuousSignal(s,idx(1:17777),cfg);eba.continuousSignal(s,idx(17778:50000),cfg);eba.continuousSignal(s,idx(50001:end),cfg)];
assert(isequal(x,chunks) && all(isfinite(x)) && height(truth)==11);
base=eba.waveform(s.baseline,idx,cfg);normal=true(size(x));
for i=1:height(truth),normal(idx>=truth.start_sample(i)&idx<truth.end_sample(i))=false;end
assert(isequal(x(normal),base(normal)) && all(truth.end_sample>truth.start_sample));
steady=truth.steady_activation;assert(all(truth.physical_duration_s(steady)>=1 & truth.physical_duration_s(steady)<=3));
assert(all(abs(truth.physical_duration_s(~steady)-truth.canonical_physical_duration_s(~steady))<1e-12));
closeCfg=cfg;closeCfg.stream_gap_s=.075;
close=eba.continuousSchedule(picked,closeCfg,Inf,'spacing_control',cfg.stream_seed);
assert(abs(close.normal_exposure_s-.075*(height(picked)+1)-close.initial_onset_jitter_s)<1e-12 && close.normal_gap_s==.075);
assert(s.initial_onset_jitter_s>=0 && s.initial_onset_jitter_s<1 && ...
    s.events.start_sample(1)==20000+round(s.initial_onset_jitter_s*cfg.Fs));
assert(all(close.events.start_sample(2:end)-close.events.end_sample(1:end-1)==750));
closeCfg.stream_gap_s=0;rejects(@() eba.continuousSchedule(picked,closeCfg,Inf,'bad',7),'eba:StreamSpacing');
noisy=s;noisy.snr_db=20;noisy.noise_realization=1;[z,~,m]=eba.continuousSignal(noisy,idx,cfg);
pieces=[eba.continuousSignal(noisy,idx(1:10000),cfg);eba.continuousSignal(noisy,idx(10001:end),cfg)];
assert(isequal(z,pieces) && abs(m.measured_nominal_snr_db-20)<1e-10);
assert(abs(10*log10(s.baseline.base_rms_pu^2/mean((z-x).^2))-20)<1e-10);
badReal=noisy;badReal.noise_realization=0;rejects(@() eba.continuousSignal(badReal,idx,cfg),'eba:StreamRealization');
more=noisy;more.snr_db=5;z2=eba.continuousSignal(more,idx,cfg);
assert(norm((z-x)/norm(z-x)-(z2-x)/norm(z2-x))<1e-11);
otherReal=eba.continuousSchedule(picked,cfg,20,'control',cfg.stream_seed,'development',2);
assert(isequal(s.events,otherReal.events) && isequal(s.baseline,otherReal.baseline) && ...
    s.noise_seed~=otherReal.noise_seed && otherReal.noise_realization==2);
assert(~isequal(z,eba.continuousSignal(otherReal,idx,cfg)));
% Adjacent sequence seeds and realization ranks occupy disjoint noise-seed slots.
adjacent=eba.continuousSchedule(picked,cfg,20,'control',cfg.stream_seed+1,'development',1);
assert(adjacent.noise_seed~=otherReal.noise_seed);
rejects(@() eba.continuousSchedule(picked,cfg,20,'bad',7,'development',0),'eba:StreamRealization');
bad=picked;bad.split(1)="test";rejects(@() eba.continuousSchedule(bad,cfg,20,'bad',7),'eba:StreamSplit');
bad=picked;bad.split(:)="test";rejects(@() eba.continuousSchedule(bad,cfg,20,'bad',7),'eba:TestFirewall');
rejects(@() eba.continuousSignal(s,-1,cfg),'eba:StreamIndices');

[~,sha]=system('git rev-parse HEAD');settings=struct('threshold_on',.7,'threshold_off',.5,'min_windows',3, ...
    'min_evidence_s',.15,'recovery_windows',2,'refractory_s',.1,'classes',cfg.classes, ...
    'method_version','control','model_version','control','dataset_version',cfg.dataset_version, ...
    'git_commit',strtrim(sha),'sequence_id','state_control','confidence_calibrated',true);
state=[];p=prediction(0,1,.9);[state,event]=eba.stateStep(state,p,settings);assert(state.phase=="NORMAL" && isempty(event));
p=prediction(.5,2,.8);[state,event,t]=eba.stateStep(state,p,settings);assert(state.phase=="SUSPECTED" && isempty(event) && t.from=="NORMAL");
p=prediction(.525,2,.8);[state,event]=eba.stateStep(state,p,settings);assert(state.phase=="SUSPECTED" && isempty(event));
p=prediction(.55,2,.8);[state,event]=eba.stateStep(state,p,settings);assert(state.phase=="CONFIRMED" && event.status=="CONFIRMED");
assert(event.estimated_start==.5 && abs(event.confirmation_time-.65)<1e-12 && abs(event.duration_so_far-.15)<1e-12);
assert(numel(event.supporting_windows)==3 && event.confidence==.8 && event.class=="voltage_sag");immutable=event;
schema=jsondecode(fileread(fullfile(cfg.root,'contracts','confirmed_event.schema.json')));
assert(all(isfield(event,cellstr(string(schema.required)))) && ~isempty(regexp(event.git_commit,'^[0-9a-f]{40}$','once')));
p=prediction(.575,2,.6);[state,event]=eba.stateStep(state,p,settings);assert(state.phase=="CONFIRMED" && isempty(event));
p=prediction(.6,1,.9);[state,~,t]=eba.stateStep(state,p,settings);assert(state.phase=="RECOVERY" && isempty(t.completed_event));
p=prediction(.625,1,.9);[state,~,t]=eba.stateStep(state,p,settings);assert(state.phase=="NORMAL" && t.completed_event.status=="ENDED");
assert(t.completed_event.confirmation_time==immutable.confirmation_time && ...
    numel(t.completed_event.supporting_windows)==3 && abs(t.completed_event.estimated_end_s-.675)<1e-12);
p=prediction(.65,2,.95);[state,event,t]=eba.stateStep(state,p,settings);assert(state.phase=="NORMAL" && isempty(event) && t.suppressed);
state=[];[state]=eba.stateStep(state,prediction(0,2,.8),settings);[state,event]=eba.stateStep(state,prediction(.025,1,.99),settings);
assert(state.phase=="NORMAL" && isempty(event),'A single strong window became a confirmed event.');
state=[];state=eba.stateStep(state,prediction(0,2,.8),settings);state=eba.stateStep(state,prediction(.025,3,.8),settings);
assert(state.phase=="SUSPECTED" && numel(state.candidate.windows)==1,'Class switch retained preceding class evidence.');
state=eba.stateStep(state,prediction(.05,3,NaN),settings);assert(state.phase=="NORMAL");
bad=prediction(0,2,.8);bad.actual_onset=0;rejects(@() eba.stateStep([],bad,settings),'eba:StatePrediction');
bad=prediction(0,2,.8);bad.decision_time_s=.05;rejects(@() eba.stateStep([],bad,settings),'eba:StateCausality');
state=eba.stateStep([],prediction(0,2,.8),settings);rejects(@() eba.stateStep(state,prediction(0,2,.8),settings),'eba:StateCausality');

changed=settings;changed.threshold_on=.8;
rejects(@() eba.stateStep(state,prediction(.075,2,.9),changed),'eba:StateSettings');
changed=settings;changed.git_commit='short';rejects(@() eba.stateStep([],prediction(0,2,.9),changed),'eba:StateSettings');
changed=settings;changed.confidence_calibrated=1;rejects(@() eba.stateStep([],prediction(0,2,.9),changed),'eba:StateSettings');

changed=settings;changed.confidence_calibrated=false;rejects(@() eba.stateStep([],prediction(0,2,.9),changed),'eba:StateSettings');
gt=table(["s1";"s1";"s2"],["f1";"f2";"f3"],[2;3;2],[1;3;1],[2;4;2], ...
    'VariableNames',{'sequence_id','family_id','class_id','start_s','end_s'});
est=table(["s1";"s1";"s1";"s2"],[2;2;3;3],[1;1.2;3;1],[2;1.8;4;2],[1.2;1.3;3.2;1.2], ...
    'VariableNames',{'sequence_id','class_id','estimated_start_s','estimated_end_s','confirmation_time_s'});
cfg.temporal_bootstrap_replicates=100;[r,pairs,cluster]=eba.eventMetrics(gt,est,[60;120],cfg);
assert(r.n_matched_events==2 && r.false_alarms==2 && abs(r.precision-.5)<1e-12 && abs(r.recall-2/3)<1e-12);
assert(abs(r.f1-4/7)<1e-12 && abs(r.false_alarms_per_minute-2/3)<1e-12 && all(pairs.iou==1));
assert(abs(r.mean_latency_s-.2)<1e-12 && r.mean_absolute_start_error_s==0 && r.n_independent_sequences==2);
assert(sum(cluster.true_positives)==2 && numel(unique(pairs.truth_row))==2 && numel(unique(pairs.estimated_row))==2);
bad=est;bad.estimated_end_s(1)=NaN;rejects(@() eba.eventMetrics(gt,bad,[60;120],cfg),'eba:EventBoundary');
paired=gt;paired.family_id(3)=paired.family_id(1);r=eba.eventMetrics(paired,est,[60;120],cfg);
assert(r.n_sequences==2 && r.n_independent_clusters==1 && r.n_independent_families==2);
assert(abs(r.f1_ci_low-r.f1_ci_high)<1e-12,'Paired noise sequences were independently bootstrapped.');
bad=gt;bad.family_id(3)=bad.family_id(2);rejects(@() eba.eventMetrics(bad,est,[60;120],cfg),'eba:EventIndependence');
early=est(1,:);early.estimated_start_s=.5;early.confirmation_time_s=.9;
r=eba.eventMetrics(gt(1,:),early,60,cfg);assert(r.n_matched_events==0 && r.false_alarms==1 && r.missed_event_rate==1);
rejects(@() eba.eventMetrics(gt,est,180,cfg),'eba:EventExposure');
% Summed IoU alone selects one match although two valid detections exist.
cardinalTruth=gt(1:2,:);cardinalTruth.family_id=["cardinal_f1";"cardinal_f2"];
cardinalTruth.class_id(:)=2;cardinalTruth.start_s=[0;1];cardinalTruth.end_s=[1;2];
cardinalEstimate=est(1:2,:);cardinalEstimate.class_id(:)=2;cardinalEstimate.estimated_start_s=[0;.2];
cardinalEstimate.estimated_end_s=[1.4;.7];cardinalEstimate.confirmation_time_s=[1.3;.7];
r=eba.eventMetrics(cardinalTruth,cardinalEstimate,60,cfg);
assert(r.n_matched_events==2 && r.false_alarms==0 && r.recall==1,'Matching sacrificed an eligible detection to increase IoU.');
normalFamily=F(find(F.class_id==1 & F.split=="validation",1),:);
normalSchedule=eba.continuousSchedule(normalFamily,cfg,Inf,'normal_control',93);
assert(isempty(normalSchedule.events) && normalSchedule.normal_exposure_s==30 && normalSchedule.n_samples==300000);
normalSignal=eba.continuousSignal(normalSchedule,(0:normalSchedule.n_samples-1)',cfg);
assert(isequal(normalSignal,eba.waveform(jsondecode(normalFamily.parameters_json),(0:299999)',cfg)));
normalExposure=table(["n1";"n2"],[60;60],["normal_f";"normal_f"], ...
    'VariableNames',{'sequence_id','normal_exposure_s','family_id'});
r=eba.eventMetrics(gt([],:),est([],:),normalExposure,cfg);
assert(r.n_independent_clusters==1 && r.n_independent_families==1 && r.normal_exposure_s==120);
cfg.temporal_bootstrap_replicates=0;r=eba.eventMetrics(gt([],:),est([],:),60,cfg);assert(r.false_alarms==0 && r.false_alarms_per_minute==0);
% Censored confirmations still count; unavailable full end metrics remain undefined.
open=early;open.confirmation_time_s=1.2;open.estimated_start_s=1;open.estimated_end_s=NaN;open.observed_until_s=2;
r=eba.eventMetrics(gt(1,:),open,60,cfg);
assert(r.n_matched_events==1 && r.n_censored_estimates==1 && r.n_completed_matches==0 && ...
    r.recall==1 && isnan(r.mean_iou) && isnan(r.mean_absolute_end_error_s) && abs(r.mean_latency_s-.2)<1e-12);
shortTruth=gt(1,:);shortTruth.end_s=1.001;
short=est(1,:);short.estimated_start_s=.99;short.estimated_end_s=1.05;short.confirmation_time_s=1.025;
r=eba.eventMetrics(shortTruth,short,60,cfg);
assert(r.n_matched_events==1 && r.mean_iou<.1,'Detection and boundary localization were conflated for a millisecond event.');
strict=cfg;strict.event_iou_threshold=.1;r=eba.eventMetrics(shortTruth,short,60,strict);assert(r.n_matched_events==0);
beforeSupport=short;beforeSupport.confirmation_time_s=1;beforeSupport.estimated_end_s=2;
r=eba.eventMetrics(shortTruth,beforeSupport,60,cfg);assert(r.n_matched_events==0, ...
    'An alarm supported entirely before the onset was matched using its later held interval.');
ongoingTruth=gt(1,:);ongoingTruth.end_s=10;r=eba.eventMetrics(ongoingTruth,open,60,cfg);
assert(r.n_matched_events==1 && isnan(r.mean_iou) && r.n_completed_matches==0, ...
    'Prefix detection was penalized using an unobserved future truth duration.');
open.class_id=3;r=eba.eventMetrics(gt(1,:),open,60,cfg);
assert(r.n_estimated_events==1 && r.false_alarms==1 && r.false_alarms_per_minute==1 && r.recall==0);
open.observed_until_s=1.1;rejects(@() eba.eventMetrics(gt(1,:),open,60,cfg),'eba:EventBoundary');
confirmation=immutable;ended=confirmation;ended.estimated_end_s=.8;
rows=eba.eventEstimates(confirmation,struct([]),1);
assert(height(rows)==1 && isnan(rows.estimated_end_s) && rows.observed_until_s==1);
rows=eba.eventEstimates(confirmation,ended,1);assert(rows.estimated_end_s==.8);
ended.confirmation_time_s=.7;rejects(@() eba.eventEstimates(confirmation,ended,1),'eba:EventIdentity');
rejects(@() eba.eventEstimates([confirmation confirmation],struct([]),1),'eba:EventIdentity');
% Actual synthetic waveform -> DSP -> calibrated unit model -> stop on CONFIRMED.
parameters=struct('nominal_frequency_hz',60,'expected_samples',500);t=(0:499)'/cfg.Fs;
gains=[.98 1 1.02 .15 .25 .35];frequencies=[59.9 60 60.1];phases=(0:3)*pi/2;
X=zeros(numel(gains)*numel(frequencies)*numel(phases),24);labels=zeros(size(X,1),1);row=0;
for g=1:numel(gains)
    for f=frequencies
        for phase=phases
            row=row+1;X(row,:)=eba.features(sqrt(2)*gains(g)*sin(2*pi*f*t+phase),cfg.Fs,'FFT',parameters);
            labels(row)=1+(g>3);
        end
    end
end
model=eba.fit(X,labels,cfg,'SVM',struct('kernel','linear','box_constraint',1,'kernel_scale',1));
calX=zeros(8,24);calLabels=repelem([1;2],4);row=0;
for gain=[1.01 .2]
    for f=[59.95 60.05]
        for phase=[.37 2.13]
            row=row+1;calX(row,:)=eba.features(sqrt(2)*gain*sin(2*pi*f*t+phase),cfg.Fs,'FFT',parameters);
        end
    end
end
model=eba.calibrate(model,calX,calLabels,"unit_cal_"+string((1:8)'));
model.method="FFT";model.parameters=parameters;model.window_samples=500;model.hop_samples=125;
fixture=F(find(F.class_id==2 & F.split=="validation" & F.severity_stratum==3 & F.duration_stratum==4,1),:);
unitSchedule=eba.continuousSchedule(fixture,cfg,Inf,'unit_continuous_confirmation',121);
unitSettings=settings;unitSettings.min_evidence_s=.05;unitSettings.refractory_s=0;
unitCfg=cfg;unitCfg.temporal_bootstrap_replicates=0;
result=eba.processStream(unitSchedule,model,unitSettings,unitCfg,true);
assert(result.final_state.phase=="CONFIRMED" && result.stopped_at_confirmation && ...
    numel(result.confirmed_events)==1 && result.censored_confirmations==1 && height(result.estimated_events)==1);
assert(any(result.phases=="NORMAL") && any(result.phases=="SUSPECTED") && result.phases(end)=="CONFIRMED");
assert(result.metrics.n_matched_events==1 && result.metrics.false_alarms==0 && result.metrics.n_censored_estimates==1);
assert(isnan(result.metrics.mean_absolute_end_error_s) && result.observed_until_s<unitSchedule.duration_s);
assert(result.confirmed_events.class=="voltage_sag" && result.confirmed_events.confirmation_time>=unitSchedule.events.start_s);
fprintf('STREAMING_SCIENTIFIC_TESTS_PASS events=%d samples=%d\n',height(truth),numel(x));
end
function p=prediction(start,c,confidence)
p=struct('window_start_s',start,'window_end_s',start+.1,'decision_time_s',start+.1,'class_id',c,'confidence',confidence,'severity','medium');
end
function rejects(f,id)
ok=false;try,f();catch err,ok=strcmp(err.identifier,id);end
assert(ok,'Expected rejection %s was not observed.',id);
end
