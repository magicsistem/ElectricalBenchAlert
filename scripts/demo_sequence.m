function [schedule, n] = demo_sequence(cfg)
%DEMO_SEQUENCE Secuencia de la demo v1.1.0: un evento por cada una de las 11 clases.
%   Toma, para cada clase de evento, la primera familia de validacion (por
%   family_id) de severidad media y duracion del estrato 4, y las une en una
%   secuencia continua a 20 dB con la realizacion de ruido 1: la misma
%   condicion de la validacion que selecciono CWT-RF. No usa familias de test.
%   n es el numero de muestras que se reproducen: bloques completos de 1,250.
%   La usan export_stream_signal, stream_host(Replay=true) y check_stream_host.
if nargin < 1, cfg = eba.config(); end
F = eba.families(cfg.families_per_cell, cfg);
V = sortrows(F(F.split == "validation" & F.severity_stratum == 2 & F.duration_stratum == 4, :), 'family_id');
rows = zeros(numel(cfg.classes) - 1, 1);
for c = 2:numel(cfg.classes)
    rows(c - 1) = find(V.class_id == c, 1);
end
schedule = eba.continuousSchedule(V(rows, :), cfg, 20, "demo11", cfg.stream_seed + 300000, "development", 1);
n = floor(schedule.n_samples / 1250) * 1250;
end
