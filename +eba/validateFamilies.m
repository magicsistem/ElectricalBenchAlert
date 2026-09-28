function report = validateFamilies(T,cfg)
%VALIDATEFAMILIES Fail closed on scientific identity, support, strata and split errors.
required={'family_id','split','class_name','labels_json','project_severity','duration_category', ...
    'parameters_json','class_id','severity_stratum','duration_stratum','family_seed', ...
    'physical_event_duration_s','duration_cycles','event_start_sample','event_end_sample','Fs_hz','clip_duration_s','ieee_duration_category'};
expectedClasses=["normal";"voltage_sag";"voltage_swell";"interruption";"harmonics";"flicker"; ...
    "oscillatory_transient";"impulsive_transient";"notching";"voltage_sag_harmonics";"voltage_swell_harmonics";"harmonics_flicker"];
assert(isequal(string(cfg.classes(:)),expectedClasses),'eba:Class','The closed class list or order differs from dataset v2.');
assert(cfg.noise_realizations>=1 && cfg.noise_realizations<16 && cfg.noise_realizations==fix(cfg.noise_realizations), ...
    'eba:Design','Noise seed mapping supports integer realizations 1 through 15.');
assert(istable(T) && height(T)>0 && all(ismember(required,T.Properties.VariableNames)), ...
    'eba:FamilySchema','Family metadata does not satisfy the schema.');
assert(numel(unique(string(T.family_id)))==height(T),'eba:FamilyLeakage','Duplicated family identity, including cross-split leakage.');
assert(all(ismember(string(T.split),["train" "validation" "test"])), 'eba:Split','Invalid split.');
assert(all(isfinite(T.class_id) & T.class_id==fix(T.class_id) & T.class_id>=1 & T.class_id<=numel(cfg.classes)), ...
    'eba:Class','Invalid class IDs.');
assert(all(string(T.class_name)==string(cfg.classes(T.class_id))),'eba:Class','Class ID/name inconsistency.');
assert(all(T.Fs_hz==cfg.Fs & T.clip_duration_s==cfg.clip_duration_s),'eba:Sampling','Sampling must be identical for every class.');
assert(all(isfinite(T.severity_stratum) & T.severity_stratum>=1 & T.severity_stratum<=3 & T.severity_stratum==fix(T.severity_stratum)) && ...
    all(isfinite(T.duration_stratum) & T.duration_stratum>=1 & T.duration_stratum<=4 & T.duration_stratum==fix(T.duration_stratum)), ...
    'eba:Strata','Invalid design strata.');
N=round(cfg.Fs*cfg.clip_duration_s); seeds=zeros(height(T),1); splitSeeds=zeros(height(T),1); noiseSeeds=zeros(height(T)*cfg.noise_realizations,1);
severityNames=["low" "medium" "high"];
for i=1:height(T)
    c=T.class_id(i); s=T.severity_stratum(i); d=T.duration_stratum(i); cls=string(T.class_name(i));
    tokens=regexp(char(T.family_id(i)),'^C(\d{2})_S([1-3])_D([1-4])_F(\d{5})$','tokens','once');
    assert(~isempty(tokens),'eba:FamilyIdentity','Malformed family ID.');
    values=cellfun(@str2double,tokens); k=values(4);
    assert(isequal(values(1:3),[c s d]) && k>=1 && k<=10000,'eba:FamilyIdentity','ID and strata disagree.');
    cellIndex=((c-1)*3+s-1)*4+d-1; serial=cellIndex*10000+k;
    expectedSeed=100000000+double(cfg.master_seed)+serial;
    splitSeed=200000000+double(cfg.split_seed)+cellIndex*10000+ceil(k/20);
    p=jsondecode(T.parameters_json(i));
    assert(isstruct(p) && isscalar(p) && all(isfield(p,{'class_name','frequency_hz','base_rms_pu','phase_rad', ...
        'start_sample','end_sample','duration_category','family_seed','family_serial','split_seed','severity_metric','severity_metric_name','ieee_duration_category'})), ...
        'eba:Parameters','Required generation parameters are missing.');
    assert(string(p.class_name)==cls && p.family_seed==expectedSeed && T.family_seed(i)==expectedSeed && ...
        p.family_serial==serial && p.split_seed==splitSeed,'eba:FamilySeed','Parameter identity or deterministic seeds differ.');
    assert(inside(p.frequency_hz,cfg.fundamental_frequency_range_hz) && inside(p.base_rms_pu,cfg.base_rms_range_pu) && ...
        inside(p.phase_rad,[-pi pi]),'eba:Nuisance','Invalid shared nuisance distribution.');
    seeds(i)=expectedSeed; splitSeeds(i)=splitSeed;
    noiseSeeds((i-1)*cfg.noise_realizations+(1:cfg.noise_realizations))= ...
        1000000000+double(cfg.master_seed)+serial*16+(1:cfg.noise_realizations);
    order=randperm(RandStream('mt19937ar','Seed',splitSeed),20); expected=strings(20,1);
    expected(order(1:14))="train"; expected(order(15:17))="validation"; expected(order(18:20))="test";
    assert(T.split(i)==expected(mod(k-1,20)+1),'eba:SplitIdentity','Family split differs from its seeded allocation.');
    expectedLabels=cls;
    if cls=="voltage_sag_harmonics", expectedLabels=["voltage_sag" "harmonics"];
    elseif cls=="voltage_swell_harmonics", expectedLabels=["voltage_swell" "harmonics"];
    elseif cls=="harmonics_flicker", expectedLabels=["harmonics" "flicker"];
    end
    labelText=strtrim(char(T.labels_json(i)));
    decodedLabels=string(jsondecode(labelText));
    assert(startsWith(labelText,'[') && endsWith(labelText,']') && ...
        isequal(decodedLabels(:),expectedLabels(:)),'eba:Labels','Labels must be the exact closed-class component array.');
    expectedSeverity=severityNames(s); if cls=="normal", expectedSeverity="none"; end
    assert(T.project_severity(i)==expectedSeverity,'eba:Severity','Project severity differs from the declared physical stratum.');
    assert(string(T.duration_category(i))==string(p.duration_category) && T.ieee_duration_category(i)==string(p.ieee_duration_category), ...
        'eba:Duration','Duration or IEEE/research category differs from parameters.');
    if cls=="normal"
        nullStart=isempty(p.start_sample) || (isscalar(p.start_sample) && isnan(p.start_sample));
        nullEnd=isempty(p.end_sample) || (isscalar(p.end_sample) && isnan(p.end_sample));
        assert(nullStart && nullEnd && all(isnan([T.event_start_sample(i) T.event_end_sample(i) ...
            T.physical_event_duration_s(i) T.duration_cycles(i)])) && T.duration_category(i)=="not_applicable" && ...
            p.severity_metric==0 && string(p.severity_metric_name)=="none" && T.ieee_duration_category(i)=="not_applicable", ...
            'eba:NormalSupport','Normal has no physical event boundaries or severity.');
    else
        bounds=[p.start_sample p.end_sample];
        assert(all(isfinite(bounds)) && all(bounds==fix(bounds)) && bounds(1)>=0 && bounds(2)>bounds(1) && bounds(2)<=N && ...
            isequal(bounds,[T.event_start_sample(i) T.event_end_sample(i)]),'eba:EventSupport','Invalid half-open event support.');
        duration=(bounds(2)-bounds(1))/cfg.Fs;
        assert(abs(duration-T.physical_event_duration_s(i))<1e-12 && ...
            abs(duration*cfg.nominal_frequency_hz-T.duration_cycles(i))<1e-12,'eba:Duration','Physical duration must derive from sample boundaries.');
        amplitude=any(cls==["voltage_sag" "voltage_swell" "interruption" "voltage_sag_harmonics" "voltage_swell_harmonics"]);
        localized=amplitude || any(cls==["oscillatory_transient" "impulsive_transient"]);
        if localized
            assert(bounds(1)>=ceil(cfg.minimum_context_s*cfg.Fs) && N-bounds(2)>=ceil(cfg.minimum_context_s*cfg.Fs), ...
                'eba:Context','Missing pre-event or post-event context.');
            if amplitude, edges=[.5 2 6 15 30]/cfg.nominal_frequency_hz;
            elseif cls=="oscillatory_transient", edges=linspace(.003,.05,5);
            else, edges=linspace(.001,.005,5); end
            assert(inside(duration,edges(d:d+1)) && (d==4 || duration<edges(d+1)) && ...
                isequal(p.duration_design_range_s(:),edges(d:d+1)'), 'eba:DurationStratum','Duration lies outside its stratum.');
            if contains(cls,'sag'), category="instantaneous_sag_subset";
            elseif contains(cls,'swell'), category="instantaneous_swell_subset";
            elseif cls=="interruption", category="momentary_interruption_subset";
            elseif cls=="oscillatory_transient", category="research_bounded_oscillatory_transient";
            else, category="research_millisecond_impulse"; end
            if amplitude, designCategory=sprintf('cycles_%g_%g',edges(d)*cfg.nominal_frequency_hz,edges(d+1)*cfg.nominal_frequency_hz);
            elseif cls=="oscillatory_transient", designCategory=sprintf('osc_duration_stratum_%d',d);
            else, designCategory=sprintf('impulse_duration_stratum_%d',d); end
            assert(T.duration_category(i)==designCategory,'eba:Duration','Duration design category differs from its stratum.');
        else
            assert(isequal(bounds,[0 N]) && T.duration_category(i)==sprintf('parameter_stratum_%d',d), ...
                'eba:SteadySupport','Steady classes require declared whole-clip activation.');
            category="experimental_activation_not_normative_duration";
        end
        assert(T.ieee_duration_category(i)==category,'eba:Duration','Incorrect IEEE subset or experimental duration interpretation.');
        if amplitude
            if contains(cls,"sag"), edges=[.9 .65 .35 .1]; metric=1-p.voltage_factor; metricName="voltage_reduction_pu";
            elseif contains(cls,"swell"), edges=[1.1 1.33 1.56 1.8]; metric=p.voltage_factor-1; metricName="voltage_increase_pu";
            else, edges=[.099 .066 .033 .001]; metric=1-p.voltage_factor; metricName="voltage_reduction_pu"; end
            assert(inside(p.voltage_factor,sort(edges(s:s+1))) && p.taper_samples==min(round(.001*cfg.Fs),floor(diff(bounds)/8)) && ...
                p.taper_s==p.taper_samples/cfg.Fs,'eba:Amplitude','Invalid amplitude severity or event taper.');
        elseif cls=="harmonics" || cls=="harmonics_flicker"
            metric=p.thd_ratio; metricName="thd_ratio";
        elseif cls=="flicker", metric=p.modulation_depth; metricName="modulation_depth";
        elseif cls=="notching", metric=p.notch_depth; metricName="multiplicative_notch_depth";
        else, metric=p.transient_amplitude_pu; metricName="transient_peak_coefficient_pu"; end
        assert(inside(p.severity_metric,[0 Inf]) && abs(p.severity_metric-metric)<1e-12 && string(p.severity_metric_name)==metricName, ...
            'eba:Severity','Physical severity metric and parameters disagree.');
        if contains(cls,"harmonics")
            edges=linspace(.04,.20,4); orders=p.harmonic_orders(:); ratios=p.harmonic_ratios(:);
            highRanges=[10 20;21 30;31 40;41 50]; high=orders(orders>=10);
            assert(inside(p.thd_ratio,edges(s:s+1)) && abs(norm(ratios)-p.thd_ratio)<1e-12 && ...
                all(isfinite(ratios) & ratios>0) && numel(orders)==numel(ratios) && ...
                numel(orders)==numel(p.harmonic_phases_rad) && all(isfinite(p.harmonic_phases_rad)) && ...
                numel(unique(orders))==numel(orders) && all(orders==fix(orders) & orders>=2 & orders<=50) && ...
                sum(orders<10)==2 && all(ismember(orders(orders<10),[2 3 5 7 9])) && numel(high)>=1 && numel(high)<=3 && ...
                all(high>=highRanges(d,1) & high<=highRanges(d,2)) && all(orders*p.frequency_hz<cfg.Fs/2), ...
                'eba:Harmonics','Invalid nonzero THD, sparse harmonics or sampling support.');
        end
        if contains(cls,"flicker")
            edges=[.01 .03 .05 .07]; frequencyEdges=linspace(2,25,5);
            assert(inside(p.modulation_depth,edges(s:s+1)) && inside(p.modulation_frequency_hz,frequencyEdges(d:d+1)) && ...
                inside(p.modulation_phase_rad,[-pi pi]),'eba:Flicker','Invalid modulation strata.');
        end
        if cls=="oscillatory_transient"
            edges=[.1 .3 .55 .8];
            assert(inside(p.transient_amplitude_pu,edges(s:s+1)) && inside(p.transient_frequency_hz,[300 900]) && ...
                inside(p.decay_tau_s,duration*[.2 .6]) && inside(p.transient_phase_rad,[-pi pi]),'eba:Transient','Invalid oscillatory transient.');
        elseif cls=="impulsive_transient"
            edges=[.1 .3 .6 1];
            assert(inside(p.transient_amplitude_pu,edges(s:s+1)) && any(p.polarity==[-1 1]) && ...
                diff(bounds)>=10 && string(p.pulse_shape)=="compact_sine_fourth",'eba:Transient','Invalid sampled impulse.');
        elseif cls=="notching"
            edges=[.05 .15 .275 .4]; widthEdges=linspace(.001,.0026,5);
            assert(inside(p.notch_depth,edges(s:s+1)) && inside(p.notch_width_s,widthEdges(d:d+1)) && ...
                p.notches_per_cycle==2 && inside(p.notch_center_phase_rad,[pi/6 5*pi/6]) && ...
                p.notch_width_s*pi*p.frequency_hz<min(p.notch_center_phase_rad,pi-p.notch_center_phase_rad), ...
                'eba:Notching','Invalid sign-preserving notch.');
        end
    end
end
assert(numel(unique(seeds))==height(T) && numel(unique(noiseSeeds))==numel(noiseSeeds) && ...
    all(isfinite([seeds;splitSeeds;noiseSeeds]) & [seeds;splitSeeds;noiseSeeds]>=0 & [seeds;splitSeeds;noiseSeeds]<2^32), ...
    'eba:SeedCollision','Family or realization seed collision.');
uniqueSplitSeeds=unique(splitSeeds);
assert(isempty(intersect(seeds,uniqueSplitSeeds)) && isempty(intersect(seeds,noiseSeeds)) && ...
    isempty(intersect(uniqueSplitSeeds,noiseSeeds)),'eba:SeedCollision','Different seed purposes collide.');
baseSeeds=[cfg.master_seed cfg.split_seed cfg.model_seed cfg.stream_seed];
assert(all(isfinite(baseSeeds) & baseSeeds>=0 & baseSeeds<2^32 & baseSeeds==fix(baseSeeds)) && ...
    numel(unique(baseSeeds))==numel(baseSeeds) && isempty(intersect(baseSeeds,[seeds;uniqueSplitSeeds;noiseSeeds])), ...
    'eba:SeedCollision','Master, split, model, stream or derived seed purposes collide.');
counts=zeros(numel(cfg.classes),3,4); splitCounts=zeros(numel(cfg.classes),3,4,3);
splitNames=["train" "validation" "test"];
for c=1:numel(cfg.classes)
    for s=1:3
        for d=1:4
            mask=T.class_id==c & T.severity_stratum==s & T.duration_stratum==d;
            ids=sort(arrayfun(@(i) str2double(extractAfter(T.family_id(i),'_F')),find(mask)));
            n=sum(mask); counts(c,s,d)=n;
            assert(n>=20 && mod(n,20)==0 && isequal(ids(:),(1:n)'), ...
                'eba:Balance','Every design cell requires complete nested 20-family blocks.');
            for z=1:3, splitCounts(c,s,d,z)=sum(mask & T.split==splitNames(z)); end
            assert(isequal(reshape(splitCounts(c,s,d,:),1,3),n/20*[14 3 3]),'eba:Balance','Split quotas are unbalanced.');
        end
    end
end
assert(all(counts(:)==counts(1)),'eba:Balance','Class by severity by duration/parameter design is unbalanced.');
report=struct('ok',true,'n_families',height(T),'n_classes',numel(cfg.classes),'families_per_cell',counts(1), ...
    'cell_counts',counts,'split_counts',splitCounts,'family_seed_count',numel(unique(seeds)), ...
    'split_seed_count',numel(uniqueSplitSeeds),'noise_seed_count',numel(unique(noiseSeeds)), ...
    'family_split_leaks',0,'test_access','structural_only_until_frozen');
end

function yes=inside(x,range)
yes=isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x) && x>=range(1) && x<=range(2);
end
