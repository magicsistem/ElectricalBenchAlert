function log = stream_host(opts)
%STREAM_HOST Host de inferencia v1.1.0: muestras MQTT -> CWT-RF -> eventos MQTT.
%   Recibe los bloques que publica el ESP32 en <Base>/samples, los pasa a p.u.
%   con la escala de <Base>/config, clasifica ventanas de 0.5 s cada 125 ms con
%   el modelo congelado de v1.0.0 y publica en <Base>/events cada cambio de
%   estado: SUSPECTED, CONFIRMED, ENDED, NORMAL y GAP.
%
%   Uso (desde la raiz del repositorio, despues de startup):
%     stream_host()                          % escucha al ESP32 en Wokwi
%     stream_host(Replay=true)               % sin ESP32: reproduce la secuencia
%                                            % de la demo (demo_sequence) y publica
%     log = stream_host(Replay=true, Publish=false, MaxSeconds=6);  % solo local
%     stream_host(SaveSamples="captura.mat")  % ademas guarda los bloques recibidos
%
%   Broker: por defecto el broker publico de pruebas (tcp://broker.hivemq.com:1883).
%   Para un broker privado, copiar broker.example.json a broker.local.json en la
%   raiz del repositorio (ignorado por git) y llenar broker, puerto, usuario,
%   contrasena y, si usa TLS, el certificado raiz. Las opciones Broker, Port y
%   Base pasadas al llamar tienen prioridad. La contrasena nunca se imprime.
%
%   No reentrena nada: usa results/models/model_rf_cwt.mat y la misma
%   configuracion de estados que run_selected_six_model_demo.
%   Requiere Industrial Communication Toolbox (mqttclient) salvo con Publish=false.
arguments
    opts.Broker (1,1) string = ""        % vacio: broker.local.json o el broker publico
    opts.Port (1,1) double = NaN
    opts.Base (1,1) string = ""
    opts.Credentials (1,1) string = ""   % vacio: <raiz>/broker.local.json si existe
    opts.Replay (1,1) logical = false
    opts.Publish (1,1) logical = true
    opts.MaxSeconds (1,1) double = Inf
    opts.SaveSamples (1,1) string = ""   % .mat con los bloques recibidos (modo en vivo)
end

cfg = eba.config();
link = brokerSettings(opts, cfg);
[model, settings] = loadSelected(cfg);
Fs = cfg.Fs; N = model.window_samples; hop = model.hop_samples;
runId = string(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss'));
segment = 0;
settings = newSegment(settings, link.base, runId, segment);
fprintf('Host listo: %s-%s, ventana %d muestras, salto %d (%.3f s)\n', ...
    model.method, model.kind, N, hop, hop / Fs);

client = [];
if opts.Publish || ~opts.Replay
    client = connect(link);
    if ~opts.Replay
        subscribe(client, link.base + "/config");
        subscribe(client, link.base + "/samples");
    end
end

% Estado del stream
scale = [];                 % escala del ADC (desde config)
buf = zeros(0, 1);          % muestras en p.u. aun necesarias
bufStart = 0;               % indice absoluto de buf(1)
nextEnd = N;                % indice absoluto (exclusivo) del final de la proxima ventana
expectedSeq = [];
state = [];
candidate = 0;
log = table('Size', [0 7], 'VariableTypes', {'double', 'double', 'double', 'string', 'double', 'string', 'string'}, ...
    'VariableNames', {'window_start_s', 'window_end_s', 'decision_time_s', 'class', 'confidence', 'state', 'sent'});

if opts.Replay
    % La misma secuencia que reproduce el chip de Wokwi (demo_sequence).
    x = demoSignal(cfg, opts.MaxSeconds);
    for b = 0:floor(numel(x) / 1250) - 1
        ingest(x(b * 1250 + (1:1250)), b * 1250, b);
    end
else
    capture = struct('seq', zeros(0, 1), 't0_sample', zeros(0, 1), 'raw', {{}}, 'scale', {{}});
    waitStart = tic; lastMsg = [];   % el limite de 60 s cuenta desde la primera muestra
    fprintf('Esperando muestras en %s/samples...\n', link.base);
    while bufStart + numel(buf) < opts.MaxSeconds * Fs
        tt = read(client);     % timetable con columnas Topic y Data
        for r = 1:height(tt)
            topic = string(tt.Topic(r)); data = string(tt.Data(r));
            if endsWith(topic, "/config")
                c = jsondecode(data);
                scale = struct('v_ref', c.v_ref, 'v_offset', c.v_offset, 'k', c.k_v_per_pu);
                fprintf('config: v_ref=%.4f V, v_offset=%.3f V, k=%.6f V/p.u.\n', scale.v_ref, scale.v_offset, scale.k);
            elseif endsWith(topic, "/samples")
                if isempty(scale), continue; end   % sin escala no se puede convertir
                s = jsondecode(data);
                raw = double(typecast(matlab.net.base64decode(s.data), 'uint16'))';
                v = (raw * scale.v_ref / 4095 - scale.v_offset) / scale.k;
                ingest(v, s.t0_sample, s.seq);
                lastMsg = tic;
                if strlength(opts.SaveSamples) > 0
                    capture.seq(end + 1, 1) = s.seq; capture.t0_sample(end + 1, 1) = s.t0_sample;
                    capture.raw{end + 1, 1} = uint16(raw(:)); capture.scale{end + 1, 1} = scale;
                end
            end
        end
        if isempty(lastMsg) && toc(waitStart) > 600
            fprintf('No llegaron muestras en 10 min; se detiene.\n'); break;
        elseif ~isempty(lastMsg) && toc(lastMsg) > 60
            fprintf('Sin muestras por 60 s; se detiene.\n'); break;
        end
        pause(0.05);
    end
    if strlength(opts.SaveSamples) > 0
        windows = log;
        save(opts.SaveSamples, 'capture', 'windows', '-v7');
        fprintf('Captura guardada: %s (%d bloques)\n', opts.SaveSamples, numel(capture.seq));
    end
end
fprintf('Fin: %d ventanas procesadas.\n', height(log));

    % ------------------------------------------------------------------
    function ingest(v, t0, seq)
        if ~isempty(expectedSeq) && seq ~= expectedSeq
            % Bloques perdidos o ESP32 reiniciado: no se inventan muestras.
            send(struct('type', "GAP", 'event_id', settings.sequence_id + ":gap", ...
                'missing_from_seq', expectedSeq, 'resumed_at_seq', seq, 'sim_time_s', t0 / Fs));
            segment = segment + 1;
            settings = newSegment(settings, link.base, runId, segment);
            state = []; buf = zeros(0, 1); bufStart = t0; nextEnd = t0 + N;
        elseif isempty(expectedSeq)
            bufStart = t0; nextEnd = t0 + N;
        end
        expectedSeq = seq + 1;
        buf = [buf; v(:)];
        while bufStart + numel(buf) >= nextEnd
            w = buf(nextEnd - N - bufStart + (1:N));
            step(w, nextEnd);
            nextEnd = nextEnd + hop;
        end
        keep = max(0, nextEnd - N - bufStart);          % lo anterior ya no se usa
        buf = buf(keep + 1:end); bufStart = bufStart + keep;
    end

    function step(w, e)
        % Igual que eba.processStream, una ventana a la vez.
        feats = eba.features(w, Fs, model.method, model.parameters);
        [label, confidence] = eba.predict(model, feats);
        [grade, physical] = eba.severity(w, cfg.classes(label), Fs);
        pred = struct('window_start_s', (e - N) / Fs, 'window_end_s', e / Fs, 'decision_time_s', e / Fs, ...
            'class_id', label, 'confidence', confidence, 'severity', grade, ...
            'voltage_rms_pu_min', physical.voltage_rms_pu_min);
        [state, event, tr] = eba.stateStep(state, pred, settings);
        sent = "";
        % En una misma ventana un evento puede terminar (RECOVERY -> NORMAL) y
        % empezar otro candidato; se publica primero ENDED y luego SUSPECTED.
        if ~isempty(tr.completed_event)
            send(eventMsg("ENDED", tr.completed_event, e)); sent = "ENDED";
        end
        if tr.from ~= "SUSPECTED" && tr.to == "SUSPECTED"
            candidate = candidate + 1;
            send(struct('type', "SUSPECTED", 'event_id', candidateId(), ...
                'class', string(cfg.classes(label)), 'sim_time_s', e / Fs));
            sent = sent + " SUSPECTED";
        end
        if ~isempty(event)
            send(eventMsg("CONFIRMED", event, e)); sent = sent + " CONFIRMED";
        end
        if tr.from == "SUSPECTED" && tr.to == "NORMAL" && isempty(event)
            send(struct('type', "NORMAL", 'event_id', candidateId(), 'sim_time_s', e / Fs));
            sent = sent + " NORMAL";
        end
        log(end + 1, :) = {pred.window_start_s, pred.window_end_s, pred.decision_time_s, ...
            string(cfg.classes(label)), confidence, state.phase, strtrim(sent)};
        if strlength(sent) > 0
            fprintf('t=%.3f s  %-14s  %s\n', e / Fs, state.phase, strtrim(sent));
        end
    end

    function id = candidateId()
        id = settings.sequence_id + ":candidate:" + compose("%06d", candidate);
    end

    function m = eventMsg(type, ev, e)
        endS = NaN; dur = NaN;
        if isfield(ev, 'estimated_end_s'), endS = ev.estimated_end_s; end
        if isfield(ev, 'duration_ms'), dur = ev.duration_ms; end
        m = struct('type', type, 'event_id', string(ev.event_id), 'sequence', ev.sequence, ...
            'class', string(ev.class), 'severity', string(ev.severity), ...
            'estimated_start_s', ev.estimated_start_s, 'confirmation_time_s', ev.confirmation_time_s, ...
            'estimated_end_s', endS, 'duration_ms', dur, 'sim_time_s', e / Fs);
    end

    function send(m)
        m.published_at = string(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
        txt = jsonencode(m);   % NaN -> null
        if opts.Publish
            write(client, link.base + "/events", txt, QualityOfService = 1);
        end
    end
end

% ----------------------------------------------------------------------
function client = connect(link)
% En una sesion nueva de MATLAB el primer intento suele fallar; se reintenta.
args = {'ClientID', "eba-host-" + string(randi(1e9)), 'Port', link.port};
if strlength(link.username) > 0, args = [args, {'Username', link.username, 'Password', link.password}]; end
if strlength(link.ca_root_certificate) > 0, args = [args, {'CARootCertificate', link.ca_root_certificate}]; end
user = "sin usuario"; if strlength(link.username) > 0, user = "usuario " + link.username; end
for attempt = 1:3
    try
        client = mqttclient(link.broker, args{:});
        fprintf('Conectado a %s:%d (%s; configuracion: %s)\n', link.broker, link.port, user, link.source);
        return
    catch err
        fprintf('Conexion %d/3 con %s fallo: %s\n', attempt, link.broker, err.message);
        pause(2);
    end
end
rethrow(err);
end

function link = brokerSettings(opts, cfg)
% Prioridad: opciones al llamar > broker.local.json (ignorado por git) > broker publico.
link = struct('broker', "tcp://broker.hivemq.com", 'port', 1883, 'base', "eba/sim01", ...
    'username', "", 'password', "", 'ca_root_certificate', "", 'source', "valores por defecto");
path = opts.Credentials;
if strlength(path) == 0, path = fullfile(cfg.root, 'broker.local.json'); end
if isfile(path)
    s = jsondecode(fileread(path));
    for name = string(fieldnames(link))'
        if name ~= "source" && isfield(s, name), link.(name) = s.(name); end
    end
    link.source = string(path);
elseif strlength(opts.Credentials) > 0
    error('stream_host:Credentials', 'No existe el archivo de credenciales %s.', path);
end
if strlength(opts.Broker) > 0, link.broker = opts.Broker; end
if ~isnan(opts.Port), link.port = opts.Port; end
if strlength(opts.Base) > 0, link.base = opts.Base; end
for name = ["broker" "base" "username" "password" "ca_root_certificate"], link.(name) = string(link.(name)); end
link.port = double(link.port);
end

function [model, settings] = loadSelected(cfg)
% Mismo modelo y misma configuracion de estados que run_selected_six_model_demo.
selection = jsondecode(fileread(fullfile(cfg.output, 'metrics', 'six_model_selection.json')));
method = string(selection.selected_method);
assert(string(selection.selected_classifier) == "RF", 'stream_host:Selection', 'Se esperaba el RF seleccionado.');
stored = load(fullfile(cfg.output, 'models', "model_rf_" + lower(method) + ".mat"), 'model');
model = stored.model;
input = load(fullfile(cfg.output, 'inputs', 'streambench_inputs.mat'), 'heavy');
ix = find(string(cellfun(@(q) q.model.method, input.heavy.candidateSets, 'UniformOutput', false)) == method);
settings = input.heavy.candidateSets{ix}.settings;
settings.model_version = model.model_version;
settings.git_commit = model.training_git_commit;
settings.method_version = cfg.method_version;
settings.dataset_version = cfg.dataset_version;
settings.confidence_calibrated = model.calibrated;
settings.classes = cfg.classes;
end

function settings = newSegment(settings, base, runId, segment)
% Cada tramo continuo tiene su propio sequence_id, asi los event_id no se repiten.
settings.sequence_id = base + ":" + runId + ":" + compose("%02d", segment);
end

function x = demoSignal(cfg, maxSeconds)
% Misma secuencia que reproduce el chip de Wokwi (demo_sequence: 11 clases, 20 dB).
[schedule, n] = demo_sequence(cfg);
if isfinite(maxSeconds), n = min(n, round(maxSeconds * cfg.Fs)); end
x = eba.continuousSignal(schedule, 0:n - 1, cfg);
end
