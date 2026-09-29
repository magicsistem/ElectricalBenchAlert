function summary=run_transform_coverage()
%RUN_TRANSFORM_COVERAGE Report native finite-record coverage, without any labels or test data.
cfg=eba.config();S=load(fullfile(cfg.output,'development_transform_selection.mat'),'selected','methods');
lengths=unique([round(cfg.Fs*cfg.clip_duration_s);round(cfg.Fs*cfg.stream_window_cycles(:)/cfg.nominal_frequency_hz)]);
rows=cell(numel(S.methods)*numel(lengths),1);k=0;
for m=1:numel(S.methods)
    for N=lengths(:)'
        p=eba.windowParameters(S.methods(m),S.selected{m},N);t=(0:N-1)'/cfg.Fs;
        [v,~,bytes,detail]=eba.features(sqrt(2)*sin(2*pi*cfg.nominal_frequency_hz*t),cfg.Fs,S.methods(m),p);
        assert(numel(v)==24 && all(isfinite(v)) && all(isfinite(detail.frequencies_hz)));
        limits=[min(detail.frequency_cells_hz(:,1)),max(detail.frequency_cells_hz(:,2))];
        inSpan=limits(1)<=cfg.nominal_frequency_hz && limits(2)>=cfg.nominal_frequency_hz;
        if isfield(detail,'nominal_fundamental_in_actual_span'),inSpan=detail.nominal_fundamental_in_actual_span;end
        edge=NaN;if isfield(detail,'edge_affected_fraction'),edge=mean(detail.edge_affected_fraction);end
        k=k+1;rows{k}=table(S.methods(m),N,N/cfg.Fs,cfg.Fs/N,limits(1),limits(2), ...
            inSpan,numel(detail.frequencies_hz),bytes,edge,string(detail.boundary),string(jsonencode(p)), ...
            'VariableNames',{'method','samples','duration_s','record_frequency_floor_hz','represented_low_hz', ...
            'represented_high_hz','nominal_fundamental_in_span','n_frequency_cells','representation_bytes', ...
            'mean_CWT_edge_affected_fraction','boundary','parameters_json'});
    end
end
summary=vertcat(rows{:});path=fullfile(cfg.output,'transform_finite_record_coverage.csv');writetable(summary,path);
eba.manifest('transform_finite_record_coverage',cfg,struct('scope','label-free native 60 Hz sinusoid controls; descriptive coverage, no tuning or test predictions', ...
    'methods',S.methods,'parameters',cell2struct(S.selected,cellstr(lower(S.methods)),1), ...
    'interpretation_limit','Nominal dyadic intervals are not resolved DWT frequency bins. Requested CWT limits can rise for finite support; coefficients inside the cone of influence are retained. Different band coverage is part of the declared representation protocol, not intrinsic transform superiority.'),{path});
fprintf('TRANSFORM_COVERAGE_PASS configurations=%d no_test_or_labels=1\n',height(summary));
end
