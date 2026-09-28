function cfg = loadSelectedConfig(cfg)
%LOADSELECTEDCONFIG Apply persisted DWT selection when available.
path = fullfile(cfg.output.root,'dwt_selected.json');
if isfile(path)
    s = jsondecode(fileread(path));
    if isfield(s,'wavelet'), cfg.dwt.selected_wavelet = string(s.wavelet); end
    if isfield(s,'level'), cfg.dwt.selected_level = double(s.level); end
end
end
