function [state,event,transition]=stateStep(state,pred,settings)
%STATESTEP Causal persistent classification; confirmation is emitted once and immutable.
required={'threshold_on','threshold_off','min_windows','min_evidence_s','recovery_windows', ...
    'refractory_s','classes','method_version','model_version','dataset_version','git_commit','sequence_id'};
assert(isstruct(settings) && isscalar(settings) && all(isfield(settings,required)), ...
    'eba:StateSettings','Complete frozen state settings are required.');
classes=string(settings.classes(:)); normal=1;
if isfield(settings,'normal_class_id'),normal=settings.normal_class_id;end
assert(~isempty(classes) && numel(unique(classes))==numel(classes) && all(~ismissing(classes) & strlength(classes)>0) && ...
    isscalar(normal) && normal>=1 && normal<=numel(classes) && normal==fix(normal) && classes(normal)=="normal", ...
    'eba:StateSettings','Declared classes and normal class ID must agree.');
numeric={'threshold_on','threshold_off','min_windows','min_evidence_s','recovery_windows','refractory_s'};
for i=1:numel(numeric)
    v=settings.(numeric{i}); assert(isnumeric(v) && isreal(v) && isscalar(v) && isfinite(v), ...
        'eba:StateSettings','State thresholds and durations must be finite numeric scalars.');
end
assert(settings.threshold_off>=0 && settings.threshold_off<settings.threshold_on && settings.threshold_on<=1 && ...
    settings.min_windows>=1 && settings.min_windows==fix(settings.min_windows) && settings.min_evidence_s>0 && ...
    settings.recovery_windows>=1 && settings.recovery_windows==fix(settings.recovery_windows) && settings.refractory_s>=0, ...
    'eba:StateSettings','Invalid hysteresis, persistence or refractory settings.');
text={'method_version','model_version','dataset_version','git_commit','sequence_id'};
for i=1:numel(text)
    v=string(settings.(text{i})); assert(isscalar(v) && ~ismissing(v) && strlength(strtrim(v))>0, ...
        'eba:StateSettings','Versions and sequence identity must be nonempty scalars.');
end
allowed={'window_start_s','window_end_s','decision_time_s','class_id','confidence','severity', ...
    'voltage_rms_pu_min','frequency_hz','thd_pct'};
assert(isstruct(pred) && isscalar(pred) && all(isfield(pred,allowed(1:4))) && all(ismember(fieldnames(pred),allowed)), ...
    'eba:StatePrediction','Only arrived-window prediction evidence is accepted; truth metadata is forbidden.');
t=[pred.window_start_s pred.window_end_s pred.decision_time_s]; c=pred.class_id;
assert(isnumeric(t) && isreal(t) && numel(t)==3 && all(isfinite(t)) && t(1)>=0 && t(2)>t(1) && t(3)>=t(2) && ...
    isnumeric(c) && isreal(c) && isscalar(c) && isfinite(c) && c==fix(c) && c>=1 && c<=numel(classes), ...
    'eba:StateCausality','A decision cannot precede its complete arrived window.');
score=NaN;
if isfield(pred,'confidence')
    score=pred.confidence;
    assert(isnumeric(score) && isreal(score) && isscalar(score) && (isnan(score) || (isfinite(score) && score>=0 && score<=1)), ...
        'eba:StatePrediction','Confidence is a finite [0,1] evidence score, or missing NaN.');
end
severity="unknown";
if isfield(pred,'severity')
    severity=string(pred.severity);
    assert(isscalar(severity) && any(severity==["unknown","low","medium","high"]), ...
        'eba:StatePrediction','Severity must be an estimated project grade.');
end
for name=["voltage_rms_pu_min","frequency_hz","thd_pct"]
    if isfield(pred,name)
        value=pred.(name);
        assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && value>=0, ...
            'eba:StatePrediction','Physical estimates must be finite nonnegative window measurements.');
    end
end
signature=eba.hash(jsonencode(settings),'text');
if isempty(state)
    state=struct('phase',"NORMAL",'sequence_id',string(settings.sequence_id),'settings_sha256',signature, ...
        'last_window_start_s',-Inf,'last_window_end_s',-Inf,'last_decision_time_s',-Inf, ...
        'event_counter',0,'refractory_until_s',-Inf,'candidate',[], ...
        'current_event',[],'current_end_s',NaN,'recovery_count',0);
else
    assert(isstruct(state) && isscalar(state) && strcmp(state.settings_sha256,signature) && ...
        string(state.sequence_id)==string(settings.sequence_id),'eba:StateSettings','Settings or sequence changed during a stream.');
end
assert(t(1)>=state.last_window_start_s && t(2)>state.last_window_end_s && t(3)>state.last_decision_time_s, ...
    'eba:StateCausality','Windows and decision times must advance monotonically.');
event=[]; transition=struct('from',state.phase,'to',state.phase,'reason',"no_change", ...
    'phase_path',state.phase,'completed_event',[],'suppressed',false);
strong=c~=normal && isfinite(score) && score>=settings.threshold_on;
if any(state.phase==["CONFIRMED","RECOVERY"])
    held=c==state.current_event.class_id && isfinite(score) && score>=settings.threshold_off;
    if held
        state.phase="CONFIRMED"; state.recovery_count=0; state.current_end_s=t(2);
        transition.reason="same_class_above_off_threshold";
    else
        state.phase="RECOVERY"; state.recovery_count=state.recovery_count+1;
        transition.reason="recovery_evidence";
        if state.recovery_count>=settings.recovery_windows
            completed=state.current_event;
            completed.status="ENDED"; completed.estimated_end_s=state.current_end_s;
            completed.sim_time_end_s=state.current_end_s;
            completed.duration_ms=1000*(state.current_end_s-completed.estimated_start_s);
            completed.termination_decision_time_s=t(3);
            transition.completed_event=completed;
            state.phase="NORMAL"; state.current_event=[]; state.candidate=[]; state.recovery_count=0;
            state.refractory_until_s=t(3)+settings.refractory_s;
            transition.reason="recovery_complete";
        end
    end
    transition.phase_path(end+1)=state.phase;
end
if any(state.phase==["NORMAL","SUSPECTED"])
    if t(3)<state.refractory_until_s
        state.phase="NORMAL"; state.candidate=[]; transition.suppressed=true; transition.reason="refractory";
    elseif ~strong
        state.phase="NORMAL"; state.candidate=[]; transition.reason="insufficient_on_evidence";
    else
        if isempty(state.candidate) || state.candidate.class_id~=c
            state.candidate=struct('class_id',c,'windows',struct([]),'evidence_s',0, ...
                'union_end_s',t(1),'severity',severity,'measurements',struct());
        end
        candidate=state.candidate;
        window=struct('window_start_s',t(1),'window_end_s',t(2),'decision_time_s',t(3), ...
            'class_id',c,'evidence_score',score);
        if isempty(candidate.windows),candidate.windows=window;else,candidate.windows(end+1)=window;end
        candidate.evidence_s=candidate.evidence_s+max(0,t(2)-max(t(1),candidate.union_end_s));
        candidate.union_end_s=t(2); candidate.severity=severity;
        for name=["voltage_rms_pu_min","frequency_hz","thd_pct"]
            if isfield(pred,name),candidate.measurements.(name)=pred.(name);end
        end
        state.candidate=candidate; state.phase="SUSPECTED"; transition.reason="consecutive_same_class_evidence";
        if numel(candidate.windows)>=settings.min_windows && candidate.evidence_s+16*eps(max(t(2),1))>=settings.min_evidence_s
            state.event_counter=state.event_counter+1;
            event=confirmation(candidate,state.event_counter,t,settings,classes);
            state.current_event=event; state.current_end_s=t(2); state.phase="CONFIRMED"; state.candidate=[];
            transition.reason="confirmed";
        end
    end
    transition.phase_path(end+1)=state.phase;
end
state.last_window_start_s=t(1); state.last_window_end_s=t(2); state.last_decision_time_s=t(3);
transition.to=state.phase;
end

function event=confirmation(candidate,counter,t,settings,classes)
start=candidate.windows(1).window_start_s; cls=classes(candidate.class_id);
labels=cls;
if cls=="voltage_sag_harmonics",labels=["voltage_sag","harmonics"];
elseif cls=="voltage_swell_harmonics",labels=["voltage_swell","harmonics"];
elseif cls=="harmonics_flicker",labels=["harmonics","flicker"];end
device="simulated-device"; if isfield(settings,'device_id'),device=string(settings.device_id);end
method=string(settings.method_version); if isfield(settings,'method_id'),method=string(settings.method_id);end
country="not_implemented"; if isfield(settings,'country_profile'),country=string(settings.country_profile);end
calibrated=false;
if isfield(settings,'confidence_calibrated')
    assert(islogical(settings.confidence_calibrated) && isscalar(settings.confidence_calibrated), ...
        'eba:StateSettings','confidence_calibrated must be an explicit logical flag.');
    calibrated=settings.confidence_calibrated;
end
score=min([candidate.windows.evidence_score]);
event=struct('schema_version',"2.0.0",'status',"CONFIRMED", ...
    'event_id',string(settings.sequence_id)+":event:"+compose("%06d",counter), ...
    'device_id',device,'sequence',counter,'sequence_id',string(settings.sequence_id), ...
    'class_id',candidate.class_id,'class',cls,'labels',{cellstr(labels)},'primary_label',cls, ...
    'severity',candidate.severity,'project_severity',candidate.severity,'estimated_start',start,'estimated_start_s',start,'sim_time_start_s',start, ...
    'confirmation_time',t(3),'confirmation_time_s',t(3),'last_supporting_window_end_s',t(2), ...
    'duration_so_far',t(2)-start,'duration_so_far_s',t(2)-start,'sim_time_end_s',NaN,'duration_ms',NaN, ...
    'evidence_score',score,'confidence',score,'confidence_calibrated',calibrated, ...
    'confidence_semantics',"minimum supporting-window score; not a calibrated event probability", ...
    'supporting_windows',{num2cell(candidate.windows)},'evidence_duration_s',candidate.evidence_s, ...
    'method_id',method,'method_version',string(settings.method_version), ...
    'model_version',string(settings.model_version),'dataset_version',string(settings.dataset_version), ...
    'git_commit',string(settings.git_commit),'country_profile',country,'regulatory_monitoring_status',"not_implemented");
measurements=fieldnames(candidate.measurements);
for i=1:numel(measurements),event.(measurements{i})=candidate.measurements.(measurements{i});end
end
