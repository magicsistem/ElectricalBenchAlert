function T = loadMetadata(cfg)
%LOADMETADATA Load and normalize metadata.csv.
root = string(cfg.dataset.root);
if strlength(root)==0
    error('legacy:DatasetRootUnset', ...
        'PQ_DATASET_ROOT is empty. Set it or assign cfg.dataset.root.');
end
path = fullfile(char(root),char(cfg.dataset.metadata_file));
if ~isfile(path)
    error('legacy:MetadataNotFound','metadata.csv not found: %s',path);
end
opts = detectImportOptions(path,'TextType','string','VariableNamingRule','preserve');
T = readtable(path,opts);

required = cfg.dataset.required_columns;
missing = required(~ismember(required,T.Properties.VariableNames));
if ~isempty(missing)
    error('legacy:MissingColumns','Missing metadata columns: %s',strjoin(missing,', '));
end

stringCols = {'signal_id','label','severity','split','family_id','file','parameters_json'};
for k = 1:numel(stringCols)
    c = stringCols{k};
    T.(c) = string(T.(c));
end
end
