function freeze=run_selection_freeze()
%RUN_SELECTION_FREEZE Freeze validation Pareto choice and artifacts before test prediction access.
cfg=eba.config();target=fullfile(cfg.root,'FROZEN_EXPERIMENT.json');assert(~isfile(target),'eba:FreezeImmutable','The first freeze is immutable.');
[status,sha]=system('git rev-parse HEAD');[~,dirty]=system('git status --porcelain --untracked-files=normal');
assert(status==0 && isempty(strtrim(dirty)),'eba:FreezeSource','Freeze requires a clean committed scientific source tree.');sha=strtrim(sha);
acceptance=readtable(fullfile(cfg.output,'development_size_acceptance.csv'));
assert(height(acceptance)==5 && all(acceptance.accepted),'eba:DatasetAcceptance','All declared sample-size gates must pass.');
verification=jsondecode(fileread(fullfile(cfg.output,'release_development_checks.json')));
assert(verification.all_tests_passed && strcmp(verification.git_commit,sha),'eba:FreezeChecks','Current clean source must pass native development checks.');
methods=["FFT","STFT","DWT","CWT","ST"];kinds=["SVM","RF"];
% A returned ECOC object is insufficient; require native convergence and exact parent identity.
auditFiles=dir(fullfile(cfg.output,'manifests','native_solver_audit_*.json'));auditEvidence=strings(0,1);
for q=numel(auditFiles):-1:1
    auditPath=fullfile(auditFiles(q).folder,auditFiles(q).name);A=jsondecode(fileread(auditPath));
    if ~A.repository_state_clean || A.extra.n_binary_reruns~=180 || A.extra.n_converged_reruns~=180 || A.extra.n_exact_parent_matches~=180,continue;end
    assert(strcmp(A.config_hash,eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file')),'eba:SolverAuditReview','Audit config differs.');
    files=string({A.artifacts.path})';
    for j=1:numel(files),assert(strcmp(eba.hash(fullfile(cfg.root,files(j)),'file'),A.artifacts(j).sha256),'eba:SolverAuditReview','Audit artifact changed.');end
    csv=files(endsWith(files,'.csv') & ~endsWith(files,'_progress.csv'));assert(numel(csv)==1);
    numerical=readtable(fullfile(cfg.root,csv),'TextType','string');
    assert(height(numerical)==180 && all(numerical.rerun_converged & numerical.exact_parent_score_equality & numerical.exact_parent_parameter_equality),'eba:SolverAuditReview','Incomplete numerical certificate.');
    for j=1:5
        group=numerical(numerical.method==methods(j),:);
        parent=fullfile(cfg.output,"model_"+lower(methods(j))+"_svm.mat");
        assert(height(group)==36 && isequal(sort(group.binary_learner),(1:36)') && all(group.parent_model_sha256==string(eba.hash(parent,'file'))),'eba:SolverAuditReview','Certificate does not cover each saved primary binary decision function.');
    end
    auditEvidence=[string(auditPath);fullfile(cfg.root,files)];break;
end
assert(~isempty(auditEvidence),'eba:SolverAuditReview','Complete native numerical certificate is required before test authorization.');
S=load(fullfile(cfg.output,'stream_full_development.mat'),'retained','summary');
classification=readtable(fullfile(cfg.output,'validation_svm_metrics.csv'),'TextType','string');
noise=load(fullfile(cfg.output,'validation_svm_statistics.mat'),'details');robust=noise.details.robustness_summary;
rows=cell(0,1);workload="";endpoint="";runtimeCommit="";
for m=1:numel(methods)
    if isempty(S.retained{m}),continue;end
    path=fullfile(cfg.output,"runtime_stream_"+lower(methods(m))+".json");R=jsondecode(fileread(path));
    manifest=jsondecode(fileread(fullfile(cfg.output,'manifests',"runtime_stream_"+lower(methods(m))+".json")));
    assert(manifest.repository_state_clean && strcmp(manifest.git_commit,sha),'eba:RuntimeSource','Final candidate timings require this same clean source commit.');
    if workload=="",workload=string(R.shared_signal_sha256);endpoint=string(R.shared_endpoints_sha256);runtimeCommit=string(manifest.git_commit);
    else,assert(workload==string(R.shared_signal_sha256) && endpoint==string(R.shared_endpoints_sha256) && runtimeCommit==string(manifest.git_commit),'eba:RuntimeWorkload','Stream candidates must share physical signal and decision endpoints.');end
    assert(R.n_repetitions==cfg.runtime_repetitions && R.warmups==cfg.runtime_warmups);
    index=find(string(S.summary.method)==methods(m));offline=find(classification.method==methods(m));n=find(string(robust.method)==methods(m));assert(numel(index)==1 && numel(offline)==1 && numel(n)==1);
    row=S.summary(index,:);eligible=row.eligible && R.streaming_real_time_factor_p95<=1 && row.false_alarms_per_minute<=1;
    rows{end+1}=table(methods(m),classification.macro_f1(offline),robust.normalized_snr_auc(n),row.event_f1,row.matched_latency_s, ...
        R.total_p95_s,R.peak_process_RSS_bytes,R.model_serialized_bytes,R.streaming_real_time_factor_p95,eligible, ...
        'VariableNames',{'method','primary_nine_class_macro_f1','primary_nine_class_noise_auc','twelve_class_event_f1', ...
        'matched_latency_s','inference_p95_s','whole_session_peak_RSS_bytes','model_bytes','stream_RTF_p95','eligible'}); %#ok<AGROW>
end
pareto=vertcat(rows{:});objectives=pareto{:,2:9};directions=[1 1 1 -1 -1 -1 -1 -1];
pareto.pareto=eba.pareto(objectives,directions);eligible=find(pareto.eligible & pareto.pareto);
assert(~isempty(eligible),'eba:FreezeFeasibility','No nondominated pipeline meets declared validation feasibility.');
[~,order]=sortrows([-pareto.twelve_class_event_f1(eligible),pareto.matched_latency_s(eligible),eligible],[1 2 3]);chosenIndex=eligible(order(1));
pareto.selected=false(height(pareto),1);pareto.selected(chosenIndex)=true;method=pareto.method(chosenIndex);m=find(methods==method);chosen=S.retained{m};
selectedPath=fullfile('results','v2','stream_models',"full_"+lower(method)+".mat");model=chosen.model;settings=chosen.settings;
settings.method_version='1.0.0';settings.git_commit=sha;settings.method_id=char(method);settings.sequence_id='frozen_sequence';
modelHash=eba.hash(fullfile(cfg.root,selectedPath),'file');settings.model_version="stream-v1.0.0-"+string(modelHash(1:12));
% Native development demonstration must succeed before its family/recipe is frozen.
F=eba.families(cfg.families_per_cell,cfg);V=F(F.split=="validation" & F.class_name=="voltage_sag" & F.severity_stratum==3 & F.duration_stratum==4,:);
assert(height(V)>0);V=sortrows(V,'family_id');demo=[];
for i=1:height(V)
    schedule=eba.continuousSchedule(V(i,:),cfg,Inf,'confirmed_event_demo',cfg.stream_seed+200000);
    result=eba.processStream(schedule,model,settings,cfg,true);
    if result.stopped_at_confirmation && result.metrics.false_alarms==0 && result.metrics.n_matched_events==1 && ...
            any(result.phases=="NORMAL") && any(result.phases=="SUSPECTED")
        demo=struct('family_id',char(V.family_id(i)),'sequence_id','confirmed_event_demo','seed',cfg.stream_seed+200000, ...
            'scope','first successful deterministic long high-severity validation sag; illustrative, not unbiased test performance');break;
    end
end
assert(~isempty(demo),'eba:DemoFeasibility','No declared validation illustration reached genuine confirmation.');
% One shared classical workload and source across all ten models and four raw seed runs.
classicalWorkload="";offlineModels=struct('method',{},'classifier',{},'path',{});combinedModels=offlineModels;
for a=1:numel(methods)
    for k=1:2
        id="runtime_"+lower(methods(a))+"_"+lower(kinds(k));R=jsondecode(fileread(fullfile(cfg.output,id+".json")));
        M=jsondecode(fileread(fullfile(cfg.output,'manifests',id+".json")));assert(M.repository_state_clean && strcmp(M.git_commit,sha));
        if classicalWorkload=="",classicalWorkload=string(R.workload_sha256);else,assert(classicalWorkload==string(R.workload_sha256));end
        offlineModels(end+1)=struct('method',char(methods(a)),'classifier',char(kinds(k)), ...
            'path',char(fullfile('results','v2','deployment_models',"model_"+lower(methods(a))+"_"+lower(kinds(k))+".mat"))); %#ok<AGROW>
        combinedModels(end+1)=struct('method',char(methods(a)),'classifier',char(kinds(k)), ...
            'path',char(fullfile('results','v2',"combined_model_"+lower(methods(a))+"_"+lower(kinds(k))+".mat"))); %#ok<AGROW>
    end
end
rawModels=struct('method',{},'seed',{},'path',{});
for architecture=["CNN","TCN"]
    for seed=[cfg.model_seed cfg.model_seed+1]
        id="runtime_"+lower(architecture)+"_raw_seed"+seed;R=jsondecode(fileread(fullfile(cfg.output,id+".json")));
        M=jsondecode(fileread(fullfile(cfg.output,'manifests',id+".json")));assert(M.repository_state_clean && strcmp(M.git_commit,sha) && classicalWorkload==string(R.workload_sha256));
        stored=load(fullfile(cfg.root,R.model_path),'model');assert(~stored.model.structural_test_only && stored.model.calibrated);
        rawModels(end+1)=struct('method',char(architecture),'seed',seed,'path',R.model_path); %#ok<AGROW>
    end
end
parameters=eba.hash(jsonencode(table2struct(F)));split=eba.hash(jsonencode(table2struct(F(:,{'family_id','split'}))));
folder=fullfile(cfg.root,'data','manifests');assert(isfolder(folder));
familyPath=fullfile(folder,'frozen_families.csv');splitPath=fullfile(folder,'frozen_split.csv');
writetable(F,familyPath);writetable(F(:,{'family_id','split'}),splitPath);
bound=struct('path',{},'sha256',{},'role',{});
sourceFiles=[dir(fullfile(cfg.root,'+eba','*.m'));dir(fullfile(cfg.root,'scripts','*.m'));dir(fullfile(cfg.root,'tests','*.m'))];
for i=1:numel(sourceFiles),bound(end+1)=binding(fullfile(sourceFiles(i).folder,sourceFiles(i).name),'source',cfg);end %#ok<AGROW>
bound(end+1)=binding(fullfile(cfg.root,'startup.m'),'source',cfg);
bound(end+1)=binding(fullfile(cfg.root,'contracts','confirmed_event.schema.json'),'source',cfg);
configs=dir(fullfile(cfg.root,'config','*.json'));
for i=1:numel(configs),bound(end+1)=binding(fullfile(configs(i).folder,configs(i).name),'config',cfg);end %#ok<AGROW>
bound(end+1)=binding(familyPath,'dataset',cfg);bound(end+1)=binding(splitPath,'split',cfg);
catalog=dir(fullfile(cfg.output,'record_catalog_*','records.csv'));assert(numel(catalog)==1);
bound(end+1)=binding(fullfile(catalog.folder,catalog.name),'dataset',cfg);
paths=[string({offlineModels.path})';string({combinedModels.path})';string({rawModels.path})';selectedPath];
for i=1:numel(paths),bound(end+1)=binding(fullfile(cfg.root,paths(i)),'model',cfg);end %#ok<AGROW>
options=repmat(struct('gap_s',2,'context_s',2,'normal_duration_s',30),4,1);
gapCycles=[1 3 12];for i=2:4,options(i).gap_s=gapCycles(i-1)/cfg.nominal_frequency_hz;end
software=ver;requiredNames=["Signal Processing Toolbox","Wavelet Toolbox","Statistics and Machine Learning Toolbox","Deep Learning Toolbox"];
toolboxes=software(ismember(string({software.Name}),requiredNames));assert(numel(toolboxes)==4);
evidenceFiles=["development_learning.csv","development_size_acceptance.csv","development_transform_selection.csv", ...
    "validation_svm_metrics.csv","validation_svm_statistics.mat","validation_rf_metrics.csv","frozen_validation_pareto.csv","release_development_checks.json"];
writetable(pareto,fullfile(cfg.output,'frozen_validation_pareto.csv'));
for i=1:numel(evidenceFiles),bound(end+1)=binding(fullfile(cfg.output,evidenceFiles(i)),'evidence',cfg);end %#ok<AGROW>
for i=1:numel(auditEvidence),bound(end+1)=binding(auditEvidence(i),'evidence',cfg);end %#ok<AGROW>
freeze=struct('schema_version','1.0.0','experiment_id','eba-v1-confirmed-event','source_commit',sha, ...
    'test_access_authorized',true,'MATLAB_version',version,'required_toolbox_versions',toolboxes,'config_sha256',eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file'), ...
    'dataset_sha256',parameters,'split_sha256',split,'waveform_catalog_sha256',verification.waveform_catalog_sha256,'bound_files',bound, ...
    'offline_models',offlineModels,'combined_models',combinedModels,'raw_models',rawModels, ...
    'selected_stream',struct('path',char(selectedPath),'method',char(method),'training_model_version',char(model.model_version),'model_sha256',modelHash,'settings',settings), ...
    'stream_protocol',struct('mode','single_and_grouped','group_size',4,'noisy_snr_db',[20 5], ...
        'group_noisy_snr_db',20,'schedule_options',options,'sensitivity_iou_thresholds',[.1 .5]), ...
    'demo',demo,'selection_rule','eligible nondominated validation methods; maximum twelve-class event F1, then minimum conditional matched latency, then declared method order', ...
    'pareto_objectives',pareto.Properties.VariableNames(2:9),'pareto_directions',directions, ...
    'scope_limit','synthetic finite-distribution research; not regulatory certification or hard real time');
eba.json(target,freeze);eba.requireFrozen(cfg);
fprintf('TEST_FIREWALL_FROZEN_PASS method=%s models_bound=%d test_predictions_before_freeze=0\n',method,numel(paths));
end
function f=binding(path,role,cfg)
assert(isfile(path) && startsWith(path,[cfg.root filesep]));
f=struct('path',erase(char(path),[cfg.root filesep]),'sha256',eba.hash(path,'file'),'role',role);
end
