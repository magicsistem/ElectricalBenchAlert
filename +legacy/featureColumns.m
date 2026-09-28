function names = featureColumns(T)
%FEATURECOLUMNS Return numeric DSP feature columns, excluding metadata/metrics.
reserved = {'Fs','duration_s','n_samples','SNR_db','event_start_s','event_end_s','seed', ...
    'detected_start_s','detected_end_s','processing_time_s','representation_bytes'};
names={};
for k=1:numel(T.Properties.VariableNames)
    n=T.Properties.VariableNames{k};
    if ismember(n,reserved), continue; end
    v=T.(n);
    if isnumeric(v)
        names{end+1}=n; %#ok<AGROW>
    end
end
end
