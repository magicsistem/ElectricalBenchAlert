function ensureDirs(cfg)
%ENSUREDIRS Create reproducible output directories.
paths = {cfg.output.root,cfg.output.cache,cfg.output.features,cfg.output.models, ...
         cfg.output.metrics,cfg.output.figures,cfg.output.manifests};
for k = 1:numel(paths)
    if ~isfolder(paths{k}), mkdir(paths{k}); end
end
end
