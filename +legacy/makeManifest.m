function manifest = makeManifest(stage,cfg,outputs,extra)
%MAKEMANIFEST Save machine-readable execution provenance.
if nargin < 3, outputs = {}; end
if nargin < 4, extra = struct(); end
legacy.ensureDirs(cfg);
manifest = struct();
manifest.stage = string(stage);
manifest.package_version = cfg.package_version;
manifest.timestamp_utc = string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ssXXX"));
manifest.seed = cfg.seed;
manifest.dataset_root = string(cfg.dataset.root);
manifest.environment = legacy.environmentInfo();
manifest.outputs = outputs;
manifest.extra = extra;
safeStage = regexprep(char(stage),'[^A-Za-z0-9_-]','_');
path = fullfile(cfg.output.manifests,[safeStage '.json']);
legacy.writeJson(path,manifest);
end
