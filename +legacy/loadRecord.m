function rec = loadRecord(row,cfg)
%LOADRECORD Load one signal from a metadata row.
if height(row) ~= 1
    error('legacy:OneRowRequired','loadRecord expects exactly one table row.');
end
fileRel = string(row.file);
path = fullfile(char(cfg.dataset.root),char(fileRel));
if ~isfile(path)
    % Compatibility if CSV contains only filename instead of signals/filename.
    alt = fullfile(char(cfg.dataset.root),char(cfg.dataset.signals_subdir),char(fileRel));
    if isfile(alt), path = alt; else
        error('legacy:SignalNotFound','Signal file not found: %s',path);
    end
end
S = load(path);
if ~isfield(S,'samples')
    error('legacy:MissingSamples','MAT file has no samples variable: %s',path);
end
x = double(S.samples(:));
if any(~isfinite(x))
    error('legacy:NonFiniteSignal','Signal contains NaN/Inf: %s',path);
end
if numel(x) ~= row.n_samples
    error('legacy:SampleCountMismatch','%s expected %d samples, got %d.', ...
        row.signal_id,row.n_samples,numel(x));
end

rec = struct();
rec.samples = x;
rec.Fs = double(row.Fs);
rec.duration_s = double(row.duration_s);
rec.signal_id = string(row.signal_id);
rec.label = string(row.label);
rec.severity = string(row.severity);
rec.SNR_db = double(row.SNR_db);
rec.event_start_s = double(row.event_start_s);
rec.event_end_s = double(row.event_end_s);
rec.seed = double(row.seed);
rec.split = string(row.split);
rec.family_id = string(row.family_id);
rec.file = string(path);
rec.parameters_json = string(row.parameters_json);
if isfield(S,'metadata'), rec.mat_metadata = S.metadata; else, rec.mat_metadata = struct(); end
end
