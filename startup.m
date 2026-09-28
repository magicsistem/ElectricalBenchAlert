function startup()
%STARTUP Add Legacy package and optional Source package to MATLAB path.
root = fileparts(mfilename('fullpath'));
addpath(root);
addpath(fullfile(root,'scripts'));
addpath(fullfile(root,'tests'));

sourceRoot = string(getenv("PQ_SOURCE_ROOT"));
if strlength(sourceRoot) > 0 && isfolder(sourceRoot)
    addpath(char(sourceRoot));
    candidates = dir(fullfile(char(sourceRoot),'**','+pq'));
    if ~isempty(candidates)
        addpath(candidates(1).folder);
    end
end

dirs = ["results","results/manifests","results/features","results/models", ...
        "results/metrics","results/figures","cache"];
for d = dirs
    p = fullfile(root,char(d));
    if ~isfolder(p), mkdir(p); end
end

fprintf("Legacy package initialized: %s\n", root);
if strlength(string(getenv("PQ_DATASET_ROOT"))) == 0
    fprintf("PQ_DATASET_ROOT is not set. Configure it before dataset scripts.\n");
end
end
