function startup()
%STARTUP Initialize repository functions; no external package substitution.
root=fileparts(mfilename('fullpath'));
addpath(root,fullfile(root,'scripts'),fullfile(root,'tests'));
end
