function summary=run_severity_validation()
%RUN_SEVERITY_VALIDATION Oracle-class/onset diagnostics of the arrived-window RMS grade.
% This is not a detector score or a regulatory severity assessment.
cfg=eba.config();F=eba.families(cfg.families_per_cell,cfg);
F=F(F.split=="validation" & ismember(F.class_id,[2 3 4 10 11]),:);
cycles=cfg.stream_window_cycles(:).';rows=cell(height(F)*3*numel(cycles),1);predictions=zeros(height(F)*3,numel(cycles));
P=table('Size',[height(F)*3 5],'VariableTypes',{'string','string','double','double','double'}, ...
    'VariableNames',{'record_id','family_id','class_id','SNR_db','realization_id'});grades=["low","medium","high"];q=0;r=0;
for i=1:height(F)
    p=jsondecode(F.parameters_json(i));plateau=p.base_rms_pu*p.voltage_factor;
    if isfield(p,'thd_ratio'),plateau=plateau*sqrt(1+p.thd_ratio^2);end
    for snr=[Inf 20 5]
        q=q+1;signal=eba.record(F(i,:),snr,1,cfg,'development');
        P(q,:)={eba.recordId(F.family_id(i),snr,double(isfinite(snr))),F.family_id(i),F.severity_stratum(i),snr,double(isfinite(snr))};
        for w=1:numel(cycles)
            N=round(cfg.Fs*cycles(w)/cfg.nominal_frequency_hz);
            start=min(numel(signal)-N,max(0,round((p.start_sample+p.end_sample-N)/2)));
            [grade,physical]=eba.severity(signal(start+(1:N)),F.class_name(i),cfg.Fs);
            predictions(q,w)=find(grades==grade);
            estimate=physical.voltage_rms_pu_min;if contains(F.class_name(i),'swell'),estimate=physical.voltage_rms_pu_max;end
            r=r+1;rows{r}=table(F.family_id(i),F.class_name(i),F.project_severity(i),grade,cycles(w),snr, ...
                F.physical_event_duration_s(i),plateau,estimate,abs(estimate-plateau), ...
                'VariableNames',{'family_id','class_name','true_project_grade','estimated_grade','window_cycles','SNR_db', ...
                'physical_event_duration_s','ideal_plateau_nominal_rms_pu','window_rms_estimate_pu','absolute_rms_error_pu'});
        end
    end
end
raw=vertcat(rows{:});statCfg=cfg;statCfg.classes=grades(:);statCfg.comparison_family="severity_window_length_secondary";
names="severity_"+string(cycles)+"cycles";[summary,pairs,noise,details]=eba.familyStats(P,predictions,names,statCfg);
paths=[string(fullfile(cfg.output,'severity_validation_rows.csv'));string(fullfile(cfg.output,'severity_validation_metrics.csv')); ...
    string(fullfile(cfg.output,'severity_validation_paired.csv'));string(fullfile(cfg.output,'severity_validation_snr.csv'));string(fullfile(cfg.output,'severity_validation_statistics.mat'))];
writetable(raw,paths(1));writetable(summary,paths(2));writetable(pairs,paths(3));writetable(noise,paths(4));save(paths(5),'raw','summary','pairs','noise','details','P','predictions','-v7.3');
eba.manifest('severity_validation',cfg,struct('scope','validation-only amplitude families; true class and event-centred windows provided for estimator diagnostics; not online detection performance', ...
    'method','one-cycle RMS q10/q90 project grade','classifier','deterministic amplitude severity estimator', ...
    'parameters',struct('window_cycles',cycles,'snrs_db',[Inf 20 5],'realization',1), ...
    'dataset_hash',eba.hash(jsonencode(table2struct(F))),'split_hash',eba.hash(jsonencode(table2struct(F(:,{'family_id','split'})))), ...
    'limitation','Project grades describe relative gain; estimates use nominal RMS. Short events, noise, baseline variation and harmonics can change the arrived-window grade. Other physical severity types remain unknown.'),paths);
fprintf('SEVERITY_VALIDATION_COMPLETE families=%d diagnostic_windows=%d test_accessed=0\n',height(F),height(raw));
end
