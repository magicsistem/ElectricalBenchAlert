function check_stream_host()
%CHECK_STREAM_HOST Criterio del hito H2: stream_host da lo mismo que eba.processStream.
%   Corre stream_host en modo replay sin MQTT y lo compara, ventana por ventana,
%   con eba.processStream(..., false) sobre la misma secuencia de la demo
%   (demo_sequence: 11 clases, validacion a 20 dB).
%   Uso: startup; addpath('scripts'); check_stream_host
cfg = eba.config();
host = stream_host(Replay = true, Publish = false);

selection = jsondecode(fileread(fullfile(cfg.output, 'metrics', 'six_model_selection.json')));
method = string(selection.selected_method);
stored = load(fullfile(cfg.output, 'models', "model_rf_" + lower(method) + ".mat"), 'model'); model = stored.model;
input = load(fullfile(cfg.output, 'inputs', 'streambench_inputs.mat'), 'heavy');
ix = find(string(cellfun(@(q) q.model.method, input.heavy.candidateSets, 'UniformOutput', false)) == method);
settings = input.heavy.candidateSets{ix}.settings;
settings.model_version = model.model_version; settings.git_commit = model.training_git_commit;
settings.method_version = cfg.method_version; settings.dataset_version = cfg.dataset_version;
settings.confidence_calibrated = model.calibrated;
schedule = demo_sequence(cfg);
ref = eba.processStream(schedule, model, settings, cfg, false);
w = ref.window_predictions;

n = min(height(w), height(host));
assert(n > 0, 'check:Empty', 'No hay ventanas para comparar.');
sameState = all(string(w.state(1:n)) == host.state(1:n));
sameClass = all(string(cfg.classes(w.class_id(1:n))) == host.class(1:n));
maxConf = max(abs(w.confidence(1:n) - host.confidence(1:n)));
fprintf('Ventanas comparadas: %d | estados iguales: %d | clases iguales: %d | max |dif confianza|: %.3g\n', ...
    n, sameState, sameClass, maxConf);
fprintf('Eventos verdaderos: %d | confirmados offline: %d | terminados offline: %d\n', ...
    height(ref.truth), numel(ref.confirmed_events), numel(ref.completed_events));
for i = 1:numel(ref.completed_events)
    e = ref.completed_events(i);
    fprintf('Offline: %-24s inicio ~%7.3f s, confirmado %7.3f s, fin ~%7.3f s, duracion %5.0f ms\n', ...
        e.class, e.estimated_start_s, e.confirmation_time_s, e.estimated_end_s, e.duration_ms);
end
assert(sameState && sameClass && maxConf < 1e-9, 'check:Mismatch', 'stream_host difiere de processStream.');
fprintf('CHECK_STREAM_HOST_PASS\n');
end
