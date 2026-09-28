function T = families(n_per_cell,cfg)
%FAMILIES Independent parameter families; stable 20-family blocks, no waveform reads.
if nargin<2, cfg=eba.config(); end
assert(isnumeric(n_per_cell) && isreal(n_per_cell) && isscalar(n_per_cell) && isfinite(n_per_cell) && ...
    n_per_cell>=20 && mod(n_per_cell,20)==0 && n_per_cell<=10000, ...
    'eba:FamilyCount','Families per cell must be a multiple of 20, from 20 to 10000.');
assert(numel(cfg.classes)==12 && cfg.severity_strata==3 && cfg.duration_strata==4, ...
    'eba:Design','This generator implements the declared 12 by 3 by 4 design.');
assert(isequal([cfg.split_per_block.train cfg.split_per_block.validation cfg.split_per_block.test],[14 3 3]), ...
    'eba:Design','Split allocation must be 14/3/3 within each 20-family block.');
assert(cfg.noise_realizations>=1 && cfg.noise_realizations<16 && cfg.noise_realizations==fix(cfg.noise_realizations), ...
    'eba:Design','Noise seed mapping supports integer realizations 1 through 15.');
assert(cfg.Fs==10000 && cfg.clip_duration_s==1 && cfg.nominal_frequency_hz==60, ...
    'eba:Design','Canonical v2 dataset sampling is 10 kHz, one second and nominal 60 Hz.');
N=round(cfg.Fs*cfg.clip_duration_s); total=12*3*4*n_per_cell;
names={'family_id','split','class_name','labels_json','project_severity','duration_category', ...
    'parameters_json','class_id','severity_stratum','duration_stratum','family_seed', ...
    'physical_event_duration_s','duration_cycles','event_start_sample','event_end_sample','Fs_hz','clip_duration_s','ieee_duration_category'};
T=table('Size',[total numel(names)],'VariableTypes',[repmat({'string'},1,7) repmat({'double'},1,10) {'string'}],'VariableNames',names);
row=0; severityNames=["low" "medium" "high"];
for c=1:12
    cls=string(cfg.classes(c)); labels=components(cls);
    for s=1:3
        for d=1:4
            cellIndex=((c-1)*3+s-1)*4+d-1;
            for b=1:n_per_cell/20
                splitSeed=200000000+double(cfg.split_seed)+cellIndex*10000+b;
                splitRng=RandStream('mt19937ar','Seed',splitSeed);
                order=randperm(splitRng,20); splits=strings(20,1);
                splits(order(1:14))="train"; splits(order(15:17))="validation"; splits(order(18:20))="test";
                for j=1:20
                    k=(b-1)*20+j; serial=cellIndex*10000+k;
                    familySeed=100000000+double(cfg.master_seed)+serial;
                    r=RandStream('mt19937ar','Seed',familySeed);
                    p=parameters(cls,s,d,r,cfg,N);
                    p.family_serial=serial; p.family_seed=familySeed; p.split_seed=splitSeed;
                    row=row+1; T.family_id(row)=sprintf('C%02d_S%d_D%d_F%05d',c,s,d,k);
                    T.split(row)=splits(j); T.class_name(row)=cls; T.labels_json(row)=jsonencode(cellstr(labels));
                    T.project_severity(row)=severityNames(s); if cls=="normal", T.project_severity(row)="none"; end
                    T.duration_category(row)=p.duration_category; T.parameters_json(row)=jsonencode(p);
                    T.class_id(row)=c; T.severity_stratum(row)=s; T.duration_stratum(row)=d; T.family_seed(row)=familySeed;
                    T.event_start_sample(row)=p.start_sample; T.event_end_sample(row)=p.end_sample;
                    T.physical_event_duration_s(row)=(p.end_sample-p.start_sample)/cfg.Fs;
                    T.duration_cycles(row)=T.physical_event_duration_s(row)*cfg.nominal_frequency_hz;
                    T.Fs_hz(row)=cfg.Fs; T.clip_duration_s(row)=cfg.clip_duration_s;
                    T.ieee_duration_category(row)=p.ieee_duration_category;
                end
            end
        end
    end
end
eba.validateFamilies(T,cfg);
end

function labels=components(cls)
switch cls
    case "voltage_sag_harmonics", labels=["voltage_sag" "harmonics"];
    case "voltage_swell_harmonics", labels=["voltage_swell" "harmonics"];
    case "harmonics_flicker", labels=["harmonics" "flicker"];
    otherwise, labels=cls;
end
end

function p=parameters(cls,s,d,r,cfg,N)
p=struct('class_name',char(cls),'frequency_hz',draw(r,cfg.fundamental_frequency_range_hz), ...
    'base_rms_pu',draw(r,cfg.base_rms_range_pu),'phase_rad',draw(r,[-pi pi]), ...
    'start_sample',NaN,'end_sample',NaN,'duration_category','not_applicable', ...
    'severity_metric',0,'severity_metric_name','none','ieee_duration_category','not_applicable');
if cls=="normal", return; end
amplitude=any(cls==["voltage_sag" "voltage_swell" "interruption" "voltage_sag_harmonics" "voltage_swell_harmonics"]);
localized=amplitude || any(cls==["oscillatory_transient" "impulsive_transient"]);
if amplitude
    edges=[.5 2 6 15 30]/cfg.nominal_frequency_hz;
    p.duration_category=sprintf('cycles_%g_%g',edges(d)*cfg.nominal_frequency_hz,edges(d+1)*cfg.nominal_frequency_hz);
    if contains(cls,'sag'), p.ieee_duration_category='instantaneous_sag_subset';
    elseif contains(cls,'swell'), p.ieee_duration_category='instantaneous_swell_subset';
    else, p.ieee_duration_category='momentary_interruption_subset'; end
elseif cls=="oscillatory_transient"
    edges=linspace(.003,.05,5); p.duration_category=sprintf('osc_duration_stratum_%d',d);
    p.ieee_duration_category='research_bounded_oscillatory_transient';
elseif cls=="impulsive_transient"
    edges=linspace(.001,.005,5); p.duration_category=sprintf('impulse_duration_stratum_%d',d);
    p.ieee_duration_category='research_millisecond_impulse';
else
    edges=[]; p.duration_category=sprintf('parameter_stratum_%d',d);
    p.ieee_duration_category='experimental_activation_not_normative_duration';
end
if localized
    lo=ceil(edges(d)*cfg.Fs); hi=floor(edges(d+1)*cfg.Fs);
    if d<4 && hi/cfg.Fs==edges(d+1), hi=hi-1; end
    count=randi(r,[lo hi]); context=ceil(cfg.minimum_context_s*cfg.Fs);
    assert(N-count>=2*context,'eba:ClipContext','Clip cannot contain the specified event and context.');
    p.start_sample=randi(r,[context N-context-count]); p.end_sample=p.start_sample+count;
    p.duration_design_range_s=edges(d:d+1);
else
    p.start_sample=0; p.end_sample=N;
end
if amplitude
    p.taper_samples=min(round(.001*cfg.Fs),floor((p.end_sample-p.start_sample)/8));
    p.taper_s=p.taper_samples/cfg.Fs;
    if any(cls==["voltage_sag" "voltage_sag_harmonics"])
        edges=[.9 .65 .35 .1]; p.voltage_factor=draw(r,sort(edges(s:s+1)));
        p.severity_metric=1-p.voltage_factor; p.severity_metric_name='voltage_reduction_pu';
    elseif any(cls==["voltage_swell" "voltage_swell_harmonics"])
        edges=[1.1 1.33 1.56 1.8]; p.voltage_factor=draw(r,edges(s:s+1));
        p.severity_metric=p.voltage_factor-1; p.severity_metric_name='voltage_increase_pu';
    else
        edges=[.099 .066 .033 .001]; p.voltage_factor=draw(r,sort(edges(s:s+1)));
        p.severity_metric=1-p.voltage_factor; p.severity_metric_name='voltage_reduction_pu';
    end
end
if contains(cls,"harmonics")
    edges=linspace(.04,.20,4); p.thd_ratio=draw(r,edges(s:s+1));
    low=[2 3 5 7 9]; chosen=low(randperm(r,numel(low),2));
    ranges=[10 20;21 30;31 40;41 50]; high=ranges(d,1):ranges(d,2);
    chosen=sort([chosen high(randperm(r,numel(high),randi(r,[1 3])))]);
    weights=.2+rand(r,1,numel(chosen));
    p.harmonic_orders=chosen; p.harmonic_ratios=weights/norm(weights)*p.thd_ratio;
    p.harmonic_phases_rad=2*pi*rand(r,1,numel(chosen))-pi;
    if ~amplitude, p.severity_metric=p.thd_ratio; p.severity_metric_name='thd_ratio'; end
end
if contains(cls,"flicker")
    edges=[.01 .03 .05 .07]; p.modulation_depth=draw(r,edges(s:s+1));
    edges=linspace(2,25,5); p.modulation_frequency_hz=draw(r,edges(d:d+1));
    p.modulation_phase_rad=draw(r,[-pi pi]);
    if cls=="flicker", p.severity_metric=p.modulation_depth; p.severity_metric_name='modulation_depth'; end
end
if cls=="oscillatory_transient"
    edges=[.1 .3 .55 .8]; p.transient_amplitude_pu=draw(r,edges(s:s+1));
    p.transient_frequency_hz=draw(r,[300 900]);
    p.decay_tau_s=(p.end_sample-p.start_sample)/cfg.Fs*draw(r,[.2 .6]);
    p.transient_phase_rad=draw(r,[-pi pi]); p.severity_metric=p.transient_amplitude_pu;
    p.severity_metric_name='transient_peak_coefficient_pu';
elseif cls=="impulsive_transient"
    edges=[.1 .3 .6 1]; p.transient_amplitude_pu=draw(r,edges(s:s+1));
    p.polarity=2*randi(r,[0 1])-1; p.pulse_shape='compact_sine_fourth';
    p.severity_metric=p.transient_amplitude_pu; p.severity_metric_name='transient_peak_coefficient_pu';
elseif cls=="notching"
    edges=[.05 .15 .275 .4]; p.notch_depth=draw(r,edges(s:s+1));
    edges=linspace(.001,.0026,5); p.notch_width_s=draw(r,edges(d:d+1));
    p.notches_per_cycle=2; p.notch_center_phase_rad=draw(r,[pi/6 5*pi/6]);
    p.severity_metric=p.notch_depth; p.severity_metric_name='multiplicative_notch_depth';
end
end

function x=draw(r,range)
x=range(1)+(range(2)-range(1))*rand(r);
end
