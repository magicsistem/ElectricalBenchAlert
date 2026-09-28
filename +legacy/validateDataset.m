function report = validateDataset(cfg,deep)
%VALIDATEDATASET Validate schema, split leakage and optionally all MAT records.
if nargin < 2, deep = false; end
T = legacy.loadMetadata(cfg);
report = struct();
report.ok = true;
report.n_records = height(T);
report.n_families = numel(unique(T.family_id));
report.n_classes = numel(unique(T.label));
report.labels = cellstr(unique(T.label));
report.errors = {};
report.warnings = {};

if numel(unique(T.signal_id)) ~= height(T)
    report.ok = false;
    report.errors{end+1} = 'signal_id is not unique';
end

% Family leakage check.
families = unique(T.family_id);
leaks = strings(0,1);
for k = 1:numel(families)
    s = unique(T.split(T.family_id==families(k)));
    if numel(s) > 1, leaks(end+1,1) = families(k); end %#ok<AGROW>
end
report.family_split_leaks = cellstr(leaks);
if ~isempty(leaks)
    report.ok = false;
    report.errors{end+1} = sprintf('%d families cross splits',numel(leaks));
end

splits = unique(T.split);
splitCounts = struct();
for k = 1:numel(splits)
    key = matlab.lang.makeValidName(char(splits(k)));
    splitCounts.(key) = sum(T.split==splits(k));
end
report.split_counts = splitCounts;

if deep
    failures = strings(0,1);
    for i = 1:height(T)
        try
            rec = legacy.loadRecord(T(i,:),cfg);
            if rec.Fs <= 0 || rec.duration_s <= 0
                error('invalid Fs/duration');
            end
        catch ME
            failures(end+1,1) = T.signal_id(i) + ": " + string(ME.message); %#ok<AGROW>
        end
    end
    report.deep_failures = cellstr(failures);
    if ~isempty(failures)
        report.ok = false;
        report.errors{end+1} = sprintf('%d records failed deep validation',numel(failures));
    end
else
    report.deep_failures = {};
end
end
