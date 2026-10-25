function info = export_stream_signal(outDir, opts)
%EXPORT_STREAM_SIGNAL Exporta la secuencia de la demo v1.1.0 para el chip de Wokwi (hito H0).
%   export_stream_signal(outDir) escribe en outDir:
%     signal_table.h            tabla int16 en base64 (x[n] en p.u. = valor * 1e-4)
%     demo11_ground_truth.csv   verdad de cada evento (solo para comparar; nunca va al host)
%     demo11_manifest.json      secuencia, familias, n, escala y SHA-256 de la tabla
%   Con ChipTemplate="<ruta>.chip.base.c" ademas escribe grid-signal.chip.c en
%   un solo archivo (la linea #include "signal_table.h" se reemplaza por la tabla),
%   porque el editor web de Wokwi compila el chip como un unico archivo C.
%   Verifica el criterio H0: la tabla, vuelta a p.u., coincide muestra a muestra
%   con eba.continuousSignal dentro de media unidad de la escala (5e-5 p.u.).
arguments
    outDir (1,1) string
    opts.ChipTemplate (1,1) string = ""
end
cfg = eba.config(); scale = 1e-4;
[schedule, n] = demo_sequence(cfg);
x = eba.continuousSignal(schedule, (0:n - 1)', cfg);
q = round(x / scale);
assert(all(abs(q) <= intmax('int16')), 'export:Range', 'La senal no cabe en int16 con escala %g.', scale);
q = int16(q);
maxErr = max(abs(double(q) * scale - x));
assert(maxErr <= scale / 2 + 1e-12, 'export:H0', 'La tabla no reproduce eba.continuousSignal.');
bytes = typecast(q(:)', 'uint8');      % little-endian, igual que el chip (WebAssembly)
sha = eba.hash(q, 'numeric');
b64 = matlab.net.base64encode(bytes);

if ~isfolder(outDir), mkdir(outDir); end
lines = cellstr(reshape([b64, repmat(' ', 1, mod(-strlength(b64), 120))], 120, []).');
lines = strtrim(lines);
header = sprintf(['// Generado por scripts/export_stream_signal.m (ElectricalBenchAlert v1.1.0). No editar.\n' ...
    '// Secuencia demo11: 11 familias de validacion, 20 dB, realizacion 1, Fs = %d Hz.\n' ...
    '// x[n] [p.u.] = (int16 little-endian) * SIGNAL_SCALE_PU.  SHA-256(int16) = %s\n' ...
    '#define SIGNAL_N %d\n#define SIGNAL_SCALE_PU %.0e\nstatic const char SIGNAL_B64[] =\n'], cfg.Fs, sha, n, scale);
table = [header, strjoin(strcat('"', lines, '"'), newline), sprintf(';\n')];
writeText(fullfile(outDir, 'signal_table.h'), table);

truth = schedule.events(schedule.events.end_sample <= n, ...
    {'event_id', 'family_id', 'class_name', 'project_severity', 'start_sample', 'end_sample', 'start_s', 'end_s'});
writetable(truth, fullfile(outDir, 'demo11_ground_truth.csv'));

info = struct('sequence_id', schedule.sequence_id, 'snr_db', schedule.snr_db, ...
    'noise_realization', schedule.noise_realization, 'seed', schedule.seed, 'Fs', cfg.Fs, ...
    'n_samples', n, 'duration_s', n / cfg.Fs, 'scale_pu', scale, 'max_abs_error_pu', maxErr, ...
    'table_int16_sha256', sha, 'families', {cellstr(schedule.family_ids)}, ...
    'n_events', height(truth), 'dataset_version', cfg.dataset_version);
eba.json(fullfile(outDir, 'demo11_manifest.json'), info);

if strlength(opts.ChipTemplate) > 0
    base = fileread(opts.ChipTemplate);
    marker = '#include "signal_table.h"';
    assert(contains(base, marker), 'export:Template', 'La plantilla no incluye signal_table.h.');
    writeText(fullfile(outDir, 'grid-signal.chip.c'), replace(base, marker, table));
end
fprintf('EXPORT_STREAM_SIGNAL_PASS n=%d (%.3f s) eventos=%d max_err=%.2e p.u. sha256=%s\n', ...
    n, n / cfg.Fs, height(truth), maxErr, sha);
end

function writeText(path, txt)
fid = fopen(path, 'w'); assert(fid > 0, 'export:Write', 'No se pudo escribir %s.', path);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, txt, 'char');
end
