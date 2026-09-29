function report=run_report_figures()
%RUN_REPORT_FIGURES Native figures from recorded frozen outputs; no model fitting or tuning.
cfg=eba.config();freeze=eba.requireFrozen(cfg,'begin');cleanup=onCleanup(@() eba.requireFrozen(cfg,'reset'));
E=jsondecode(fileread(fullfile(cfg.output,'manifests','final_eventbench.json')));
B=jsondecode(fileread(fullfile(cfg.output,'manifests','final_streambench.json')));
assert(strcmp(E.extra.freeze_sha256,eba.hash(fullfile(cfg.root,'FROZEN_EXPERIMENT.json'),'file')) && ...
    strcmp(B.extra.freeze_sha256,E.extra.freeze_sha256),'eba:ReportSource','Both final workloads must bind the same freeze.');
verifyArtifacts(E,cfg);verifyArtifacts(B,cfg);
eventFolder=fileparts(fullfile(cfg.root,E.artifacts(1).path));streamFolder=fileparts(fullfile(cfg.root,B.artifacts(1).path));
stamp=string(datetime('now','TimeZone','UTC','Format',"yyyyMMdd'T'HHmmssSSS"));folder=fullfile(cfg.output,"report_"+stamp);assert(~isfolder(folder));mkdir(folder);
artifacts=strings(0,1);L=readtable(fullfile(cfg.output,'development_learning.csv'),'TextType','string');
f=figure('Visible','off');hold on;names=unique(L.method,'stable');
for name=names(:)'
    q=L(L.method==name,:);[~,order]=sort(q.fit_families_per_class);q=q(order,:);
    errorbar(q.fit_families_per_class,q.macro_f1,q.macro_f1-q.ci_low,q.ci_high-q.macro_f1,'-o','DisplayName',name);
end
xlabel('Independent fitting families per class');ylabel('Validation Macro F1');legend('Location','best');grid on;
artifacts(end+1)=saveFigure(f,folder,'family_learning_curves');
noise=readtable(fullfile(eventFolder,'dsp_svm_snr.csv'),'TextType','string');
f=figure('Visible','off');hold on;
for name=names(:)'
    q=noise(noise.method==name & isfinite(noise.SNR_db),:);q=sortrows(q,'SNR_db');
    errorbar(q.SNR_db,q.macro_f1,q.macro_f1-q.macro_f1_ci_low,q.macro_f1_ci_high-q.macro_f1,'-o','DisplayName',name);
end
xlabel('Requested disturbed-record SNR (dB)');ylabel('Frozen test Macro F1');legend('Location','best');grid on;
artifacts(end+1)=saveFigure(f,folder,'frozen_noise_robustness');
T=load(fullfile(eventFolder,'dsp_svm_statistics.mat'),'details');
f=figure('Visible','off','Position',[100 100 1300 650]);tiledlayout(2,3);
for m=1:numel(names)
    ax=nexttile;C=T.details.point_metrics{m}.confusion;C=C./max(sum(C,2),1);imagesc(ax,C,[0 1]);axis(ax,'square');colorbar(ax);
    title(ax,names(m));xlabel(ax,'Predicted class ID');ylabel(ax,'True class ID');xticks(ax,1:9);yticks(ax,1:9);
end
artifacts(end+1)=saveFigure(f,folder,'frozen_confusions_row_normalized');
svm=readtable(fullfile(eventFolder,'dsp_svm_metrics.csv'),'TextType','string');rf=readtable(fullfile(eventFolder,'dsp_rf_metrics.csv'),'TextType','string');
raw=readtable(fullfile(eventFolder,'raw_metrics.csv'),'TextType','string');
f=figure('Visible','off','Position',[100 100 1200 450]);tiledlayout(1,3);
tracks={svm,rf,raw};titles=["DSP / shared SVM","DSP / shared Random Forest","Raw fixed architectures and seeds"];
for k=1:3
    q=tracks{k};nexttile;bar(q.macro_f1);hold on;errorbar(1:height(q),q.macro_f1,q.macro_f1-q.macro_f1_ci_low,q.macro_f1_ci_high-q.macro_f1,'k.');
    xticks(1:height(q));xticklabels(q.method);xtickangle(45);ylim([0 1]);ylabel('Frozen test Macro F1');title(titles(k));grid on;
end
artifacts(end+1)=saveFigure(f,folder,'frozen_classification_tracks');
P=readtable(fullfile(cfg.output,'frozen_validation_pareto.csv'),'TextType','string');
f=figure('Visible','off');scatter(1000*P.inference_p95_s,P.twelve_class_event_f1,70,double(P.pareto),'filled');
text(1000*P.inference_p95_s,P.twelve_class_event_f1," "+P.method);set(gca,'XScale','log');
xlabel('Validation pipeline p95 inference (ms)');ylabel('Twelve-class validation event F1');title('Projection of the eight-objective Pareto front');grid on;
artifacts(end+1)=saveFigure(f,folder,'validation_pareto_projection');
S=load(fullfile(streamFolder,'single_stream_results.mat'),'details','report');matched=S.details.matched;
f=figure('Visible','off','Position',[100 100 1100 650]);tiledlayout(2,2);
fields=["latency_s","start_error_s","end_error_s","iou"];labels=["Detection latency (s)","Absolute start error (s)","Absolute end error (s)","Completed event IoU"];
for i=1:numel(fields)
    nexttile;v=matched.(fields(i));v=v(isfinite(v));
    if ~isempty(v),histogram(v,'Normalization','probability');else,text(.1,.5,'No defined matched estimates');end
    xlabel(labels(i));ylabel('Matched-event probability');grid on;
end
artifacts(end+1)=saveFigure(f,folder,'frozen_stream_temporal_distributions');
report=struct('freeze_id',freeze.experiment_id,'n_figures',numel(artifacts),'scope','MATLAB figures from recorded predictions and development decisions; conditional uncertainty and matched-event timing', ...
    'final_eventbench_manifest_sha256',eba.hash(fullfile(cfg.output,'manifests','final_eventbench.json'),'file'), ...
    'final_streambench_manifest_sha256',eba.hash(fullfile(cfg.output,'manifests','final_streambench.json'),'file'));
eba.requireFrozen(cfg,'end');eba.manifest('final_report_figures',cfg,report,artifacts);
fprintf('NATIVE_REPORT_FIGURES_PASS figures=%d fitting_calls=0\n',numel(artifacts));
end
function path=saveFigure(f,folder,name)
cleanup=onCleanup(@() close(f));path=fullfile(folder,string(name)+".png");exportgraphics(f,path,'Resolution',180);
end

function verifyArtifacts(m,cfg)
for i=1:numel(m.artifacts)
    path=fullfile(cfg.root,m.artifacts(i).path);
    assert(isfile(path) && strcmp(eba.hash(path,'file'),m.artifacts(i).sha256), ...
        'eba:ReportSource','Recorded final prediction/statistics artifact changed.');
end
end
