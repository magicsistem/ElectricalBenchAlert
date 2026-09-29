function schedule=continuousSchedule(F,cfg,snr,sequence_id,seed,mode,realization,options)
%CONTINUOUSSCHEDULE Nonoverlapping physical activations on one common baseline.
if nargin<6,mode="development";end
if nargin<7,realization=1;end
if nargin<8,options=struct();end
assert(isstruct(options) && isscalar(options) && all(ismember(fieldnames(options), ...
    {'gap_s','context_s','normal_duration_s'})),'eba:StreamSpacing','Unknown schedule timing option.');
for name=string(fieldnames(options)).'
    v=options.(name);assert(isnumeric(v) && isscalar(v) && isfinite(v) && v>0, ...
        'eba:StreamSpacing','Schedule timing options must be finite positive seconds.');
end
assert(isnumeric(realization) && isscalar(realization) && isfinite(realization) && ...
    realization==fix(realization) && realization>=1 && realization<=cfg.noise_realizations && realization<16, ...
    'eba:StreamRealization','A declared independent noise realization is required.');
mode=string(mode);
assert(isscalar(mode) && any(mode==["development","final"]),'eba:StreamMode','Unknown stream access mode.');
required={'family_id','split','class_id','class_name','labels_json','project_severity', ...
    'parameters_json','physical_event_duration_s','Fs_hz'};
assert(istable(F) && height(F)>0 && all(ismember(required,F.Properties.VariableNames)), ...
    'eba:StreamFamilies','A nonempty table of event families or one normal family is required.');
assert(isnumeric(cfg.Fs) && isscalar(cfg.Fs) && isfinite(cfg.Fs) && cfg.Fs>0 && cfg.Fs==fix(cfg.Fs), ...
    'eba:Sampling','Stream sampling must be a positive integer.');
classes=string(cfg.classes(:)); normal=find(classes=="normal");
assert(numel(normal)==1,'eba:StreamClasses','Exactly one normal class is required.');
ids=double(F.class_id(:)); names=string(F.class_name(:)); split=unique(string(F.split(:)));
assert(all(isfinite(ids) & ids==fix(ids) & ids>=1 & ids<=numel(classes)) && ...
    all(names==classes(ids)),'eba:StreamClasses','Schedules accept declared classes.');
normal_only=all(ids==normal);
assert((normal_only && height(F)==1) || all(ids~=normal),'eba:StreamClasses','Use one normal family or non-normal event families; do not mix them.');
assert(numel(split)==1 && any(split==["train","validation","test"]),'eba:StreamSplit','Every sequence has one inherited split.');
if mode=="development"
    assert(split~="test",'eba:TestFirewall','Development schedules deny test families.');
else
    freeze=eba.requireFrozen(cfg,'verify',F);
    if ~isempty(fieldnames(options))
        assert(isfield(freeze,'stream_protocol') && isfield(freeze.stream_protocol,'schedule_options'), ...
            'eba:TestFirewall','Final timing options must have been declared before test.');
        allowed=freeze.stream_protocol.schedule_options;found=false;
        for a=1:numel(allowed),if isequaln(orderfields(options),orderfields(allowed(a))),found=true;break;end;end
        assert(found,'eba:TestFirewall','Final schedule timing differs from the frozen recipe.');
    end
end
family=string(F.family_id(:));
assert(all(~ismissing(family) & strlength(strtrim(family))>0) && numel(unique(family))==height(F), ...
    'eba:StreamFamilies','Event family identities must be nonempty and unique within a sequence.');
assert(all(F.Fs_hz==cfg.Fs),'eba:Sampling','Family and sequence sampling differ.');
sequence_id=string(sequence_id);
assert(isscalar(sequence_id) && ~ismissing(sequence_id) && strlength(strtrim(sequence_id))>0, ...
    'eba:StreamSequence','A nonempty sequence ID is required.');
assert(isnumeric(seed) && isreal(seed) && isscalar(seed) && isfinite(seed) && seed>=0 && seed<2^32 && seed==fix(seed), ...
    'eba:StreamSeed','Sequence seed must be an unsigned 32-bit integer.');
assert(isnumeric(snr) && isreal(snr) && isscalar(snr) && (isfinite(snr) || snr==Inf), ...
    'eba:SNR','Stream SNR must be finite or positive infinity.');
noiseSeed=2000000000+double(seed)*16+realization;
assert(noiseSeed<2^32,'eba:StreamSeed','The hierarchical stream noise seed must fit unsigned 32 bits.');
r=RandStream('mt19937ar','Seed',double(seed));
baseline=struct('class_name','normal','frequency_hz',draw(r,cfg.fundamental_frequency_range_hz), ...
    'base_rms_pu',draw(r,cfg.base_rms_range_pu),'phase_rad',draw(r,[-pi pi]));
independent_families=family;
if normal_only
    p=jsondecode(F.parameters_json(1));
    assert(string(p.class_name)=="normal",'eba:StreamParameters','Normal family parameters disagree.');
    baseline=struct('class_name','normal','frequency_hz',p.frequency_hz,'base_rms_pu',p.base_rms_pu,'phase_rad',p.phase_rad);
    F=F([],:);
end
[~,order]=sort(string(F.family_id)); order=order(randperm(r,height(F))); F=F(order,:);
n=height(F);gapSeconds=2;if isfield(cfg,'stream_gap_s'),gapSeconds=cfg.stream_gap_s;end
if isfield(options,'gap_s'),gapSeconds=options.gap_s;end
assert(isnumeric(gapSeconds) && isscalar(gapSeconds) && isfinite(gapSeconds) && gapSeconds>0, ...
    'eba:StreamSpacing','A finite positive event spacing is required.');
gap=max(1,round(gapSeconds*cfg.Fs));context=gap;
if isfield(cfg,'stream_context_s')
    assert(isnumeric(cfg.stream_context_s) && isscalar(cfg.stream_context_s) && isfinite(cfg.stream_context_s) && cfg.stream_context_s>0, ...
        'eba:StreamSpacing','A finite positive pre/post context is required.');
    context=max(1,round(cfg.stream_context_s*cfg.Fs));
end
if isfield(options,'context_s'),context=max(1,round(options.context_s*cfg.Fs));end
onsetJitter=0;
if n>0,onsetJitter=randi(r,[0 cfg.Fs-1]);end
cursor=context+onsetJitter;
events=table('Size',[n 16],'VariableTypes', ...
    {'string','string','string','string','string','string','string','double','double','double','double','double','double','double','double','logical'}, ...
    'VariableNames',{'event_id','sequence_id','family_id','split','class_name','labels_json','project_severity', ...
    'class_id','start_sample','end_sample','start_s','end_s','physical_duration_s','canonical_physical_duration_s','severity_metric','steady_activation'});
parameters=strings(n,1);
for i=1:n
    p=jsondecode(F.parameters_json(i)); cls=string(F.class_name(i));
    assert(isstruct(p) && isscalar(p) && string(p.class_name)==cls && ...
        all(isfield(p,{'start_sample','end_sample','severity_metric'})), ...
        'eba:StreamParameters','Family parameters and class metadata disagree.');
    canonical=(double(p.end_sample)-double(p.start_sample))/cfg.Fs;
    assert(isfinite(canonical) && canonical>0 && abs(canonical-F.physical_event_duration_s(i))<1e-12, ...
        'eba:StreamSupport','Canonical support must equal the stored physical duration.');
    steady=any(cls==["harmonics","flicker","notching","harmonics_flicker"]);
    count=double(p.end_sample)-double(p.start_sample);
    if steady,count=randi(r,[cfg.Fs 3*cfg.Fs]);end
    assert(count==fix(count) && count>0,'eba:StreamSupport','Event duration must contain integer samples.');
    p.start_sample=cursor; p.end_sample=cursor+count;
    p.frequency_hz=baseline.frequency_hz; p.base_rms_pu=baseline.base_rms_pu; p.phase_rad=baseline.phase_rad;
    p.stream_taper_samples=0; if steady,p.stream_taper_samples=max(1,round(.001*cfg.Fs));end
    labels=string(jsondecode(F.labels_json(i))); expected=components(cls);
    assert(isequal(labels(:),expected(:)),'eba:StreamLabels','Component labels disagree with the declared class.');
    events.event_id(i)=sequence_id+":truth:"+compose("%06d",i);
    events.sequence_id(i)=sequence_id; events.family_id(i)=string(F.family_id(i)); events.split(i)=split;
    events.class_name(i)=cls; events.labels_json(i)=jsonencode(cellstr(labels(:)));
    events.project_severity(i)=string(F.project_severity(i)); events.class_id(i)=double(F.class_id(i));
    events.start_sample(i)=cursor; events.end_sample(i)=cursor+count;
    events.start_s(i)=cursor/cfg.Fs; events.end_s(i)=(cursor+count)/cfg.Fs;
    events.physical_duration_s(i)=count/cfg.Fs; events.canonical_physical_duration_s(i)=canonical;
    events.severity_metric(i)=p.severity_metric; events.steady_activation(i)=steady;
    parameters(i)=jsonencode(p);cursor=cursor+count+gap;
    if i==n,cursor=cursor-gap+context;end
end
events.parameters_json=parameters;
if normal_only
    seconds=30;if isfield(cfg,'normal_stream_duration_s'),seconds=cfg.normal_stream_duration_s;end
    if isfield(options,'normal_duration_s'),seconds=options.normal_duration_s;end
    assert(isnumeric(seconds) && isscalar(seconds) && isfinite(seconds) && seconds>0,'eba:StreamSupport','Normal exposure duration must be positive.');
    cursor=round(seconds*cfg.Fs);
end
schedule=struct('schema_version',"2.0.0",'sequence_id',sequence_id,'split',split,'access_mode',mode, ...
    'Fs',double(cfg.Fs),'n_samples',cursor,'duration_s',cursor/cfg.Fs,'seed',double(seed), ...
    'noise_seed',noiseSeed,'noise_realization',realization*isfinite(snr),'snr_db',double(snr),'baseline',baseline, ...
    'events',events,'family_ids',independent_families,'normal_exposure_s',(cursor-sum(events.end_sample-events.start_sample))/cfg.Fs, ...
    'normal_gap_s',gap/cfg.Fs,'normal_context_s',context/cfg.Fs,'initial_onset_jitter_s',onsetJitter/cfg.Fs,'noise_reference',"nominal_sequence_baseline_rms_power", ...
    'support_convention',"integer zero-based half-open [start_sample,end_sample)");
end

function value=draw(r,range)
assert(isnumeric(range) && isreal(range) && numel(range)==2 && all(isfinite(range(:))) && range(1)<=range(2), ...
    'eba:StreamBaseline','Invalid shared baseline range.');
value=range(1)+(range(2)-range(1))*rand(r);
end

function labels=components(cls)
switch cls
    case "voltage_sag_harmonics",labels=["voltage_sag","harmonics"];
    case "voltage_swell_harmonics",labels=["voltage_swell","harmonics"];
    case "harmonics_flicker",labels=["harmonics","flicker"];
    otherwise,labels=cls;
end
end
