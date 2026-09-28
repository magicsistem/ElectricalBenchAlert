function test_streaming()
%TEST_STREAMING Physical continuity, sample causality, persistence and event matching.
cfg=eba.config();F=eba.families(20,cfg);picked=F([],:);
for c=2:12,row=find(F.class_id==c & F.split=="validation",1);picked=[picked;F(row,:)];end %#ok<AGROW>
s=eba.continuousSchedule(picked,cfg,Inf,'control',cfg.stream_seed);
repeat=eba.continuousSchedule(picked,cfg,Inf,'control',cfg.stream_seed);
assert(isequal(s,repeat) && s.n_samples>10000 && s.normal_exposure_s==2*(height(picked)+1));
idx=(0:s.n_samples-1)';[x,truth]=eba.continuousSignal(s,idx,cfg);
chunks=[eba.continuousSignal(s,idx(1:17777),cfg);eba.continuousSignal(s,idx(17778:50000),cfg);eba.continuousSignal(s,idx(50001:end),cfg)];
assert(isequal(x,chunks) && all(isfinite(x)) && height(truth)==11);
base=eba.waveform(s.baseline,idx,cfg);normal=true(size(x));
for i=1:height(truth),normal(idx>=truth.start_sample(i)&idx<truth.end_sample(i))=false;end
assert(isequal(x(normal),base(normal)) && all(truth.end_sample>truth.start_sample));
steady=truth.steady_activation;assert(all(truth.physical_duration_s(steady)>=1 & truth.physical_duration_s(steady)<=3));
assert(all(abs(truth.physical_duration_s(~steady)-truth.canonical_physical_duration_s(~steady))<1e-12));
noisy=s;noisy.snr_db=20;[z,~,m]=eba.continuousSignal(noisy,idx,cfg);
pieces=[eba.continuousSignal(noisy,idx(1:10000),cfg);eba.continuousSignal(noisy,idx(10001:end),cfg)];
assert(isequal(z,pieces) && abs(m.measured_nominal_snr_db-20)<1e-10);
assert(abs(10*log10(s.baseline.base_rms_pu^2/mean((z-x).^2))-20)<1e-10);
more=noisy;more.snr_db=5;z2=eba.continuousSignal(more,idx,cfg);
assert(norm((z-x)/norm(z-x)-(z2-x)/norm(z2-x))<1e-11);
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
fprintf('STREAMING_SCIENTIFIC_TESTS_PASS events=%d samples=%d\n',height(truth),numel(x));
end
function p=prediction(start,c,confidence)
p=struct('window_start_s',start,'window_end_s',start+.1,'decision_time_s',start+.1,'class_id',c,'confidence',confidence,'severity','medium');
end
function rejects(f,id)
ok=false;try,f();catch err,ok=strcmp(err.identifier,id);end
assert(ok,'Expected rejection %s was not observed.',id);
end
