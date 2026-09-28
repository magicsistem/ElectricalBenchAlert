function info = environmentInfo()
%ENVIRONMENTINFO Capture MATLAB and toolbox provenance.
info = struct();
info.matlab_version = version;
info.matlab_release = version('-release');
info.computer = computer;
v = ver;
tb = repmat(struct('name',"",'version',""),numel(v),1);
for k = 1:numel(v)
    tb(k).name = string(v(k).Name);
    tb(k).version = string(v(k).Version);
end
info.toolboxes = tb;
end
