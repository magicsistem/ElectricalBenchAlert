function cfg = config()
%CONFIG The portable authoritative research configuration; choices remain development until freeze.
root=fileparts(fileparts(mfilename('fullpath')));
cfg=jsondecode(fileread(fullfile(root,'config','research_v2.json')));
cfg.root=root;
cfg.classes=string(cfg.classes(:));
cfg.output=fullfile(root,'results','v2');
if ~isfolder(cfg.output), mkdir(cfg.output); end
end
